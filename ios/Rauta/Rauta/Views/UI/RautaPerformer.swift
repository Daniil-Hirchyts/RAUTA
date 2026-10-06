import Combine
import RiveRuntime
import SwiftUI

/// One on-screen RAUTA's body: the rig, and everything this placement does with
/// it.
///
/// Four things drive it, in order of who wins. Cues the director hears from the
/// app. A finger on the character itself. The person touching anywhere else,
/// which the eyes follow. And, when nothing is happening, the character's own
/// idle thoughts, chosen by mood. Between those moments it keeps its mood's
/// loop going at a gentler frame rate: on screen, it is never a still picture.
///
/// Nothing here publishes: the rig is imperative, and redrawing SwiftUI for a
/// glance would cost more than the glance.
@MainActor
final class RautaPerformer: ObservableObject {
    let rig: RautaRig
    let id = UUID()

    private let director = RautaDirector.shared
    private var cancellables = Set<AnyCancellable>()

    // Where it is, and whether anyone can see it.
    private var frame: CGRect = .zero
    /// Its laid-out width. A character being scaled down in flight keeps its
    /// placement — and its pace — rather than turning into a badge mid-move.
    private var layoutWidth: CGFloat = 0
    private var appeared = false
    private var onStage = true
    private var sceneActive = true
    private var reducedMotion = false
    /// On stage but not yet in the scene: running, unseen, about to take over
    /// from another character. It answers nobody and claims nothing.
    private var quiet = false
    /// A frame rate held for a piece of choreography; nil paces itself.
    private var pinnedFramesPerSecond: Int?
    private var placement: RautaPlacement { RautaPlacement(width: layoutWidth > 0 ? layoutWidth : frame.width) }
    private var performing: Bool { appeared && onStage && sceneActive }

    // How it feels.
    private var baseMood: RautaMood = .calm
    /// The look the line RAUTA is saying asks for — working, while it works.
    /// Only the character answering for RAUTA wears it.
    private var spokenMood: RautaMood?
    private var context = RautaContext()
    private var sulkUntil = Date.distantPast
    /// A mood held for the length of a gesture — see `beginDrag`.
    private var borrowedMood: RautaMood?
    private var applied: (mood: RautaMood, intensity: Double)?
    private var moodChangedAt = Date.distantPast

    // What it has been doing.
    private var activity = RautaActivity(now: RautaPerformer.nowMs)
    private var previousIdle: RautaIdleBeat?
    private var previousGazeDirection: RautaGazeDirection?
    private var tapTimes: [Date] = []
    private var spinTimes: [Date] = []
    private var acknowledgementIndex = 0
    /// Triggers waiting for a mood crossfade to settle, fired on the frame.
    private var pendingTriggers: [(reaction: RautaReaction, at: Date)] = []

    // Its body, moved on the rig's own frames.
    private var gaze = (x: 0.0, y: 0.0)
    private var gazeTarget = (x: 0.0, y: 0.0)
    /// How quickly the eyes close the distance, per second: fast for a look,
    /// slow for drifting home.
    private var gazeSpeed = 20.0
    private var facing = 0.0
    private var facingVelocity = 0.0
    private var springing = false

    // Touch.
    private var touchBegan: Date?
    private var dragging = false
    private var pressing = false

    // Energy.
    private var livelyUntil = Date.distantPast
    private var framesPerSecond = 0
    private var playingLively = false

    private var idleTask: Task<Void, Never>?
    private var gazeReturnTask: Task<Void, Never>?
    /// A look with more than one stop, still walking through them.
    private var glanceTask: Task<Void, Never>?
    private var pressTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var sulkTask: Task<Void, Never>?

    init() {
        rig = RautaArtwork.makeRig()
        rig.onAdvance = { [weak self] seconds in self?.advance(seconds) }
    }

    nonisolated private static var nowMs: Double { Date().timeIntervalSince1970 * 1000 }
    nonisolated private static func random() -> Double { Double.random(in: 0..<1) }

    // MARK: Lifecycle

    func appear(mood: RautaMood, reducedMotion: Bool, onStage: Bool, quiet: Bool = false) {
        appeared = true
        baseMood = mood
        self.reducedMotion = reducedMotion
        self.onStage = onStage
        self.quiet = quiet
        director.start()
        context = director.context.value
        subscribe()
        framesPerSecond = 0
        guard performing else { return }
        beginPerforming()
    }

    func disappear() {
        appeared = false
        cancellables.removeAll()
        stopPerforming()
    }

    func setOnStage(_ value: Bool) {
        guard value != onStage else { return }
        onStage = value
        performing ? beginPerforming() : stopPerforming()
    }

    func setSceneActive(_ value: Bool) {
        guard value != sceneActive else { return }
        sceneActive = value
        performing ? beginPerforming() : stopPerforming()
    }

    /// A new mood. `blinks` false blends it in without the blink a change of
    /// feeling usually brings — for choreography, where it would read as a cut.
    func setMood(_ mood: RautaMood, blinks: Bool = true) {
        baseMood = mood
        applyMood(blinks: blinks)
    }

    /// Takes the character in or out of quiet: running unseen, ready to take
    /// over, and answering nothing until it does.
    func setQuiet(_ value: Bool) {
        guard value != quiet else { return }
        quiet = value
        if !quiet, performing { director.enter(id, frame: frame) }
    }

    /// Holds the renderer at `framesPerSecond`, or lets it pace itself again.
    func pin(framesPerSecond: Int?) {
        guard framesPerSecond != pinnedFramesPerSecond else { return }
        pinnedFramesPerSecond = framesPerSecond
        self.framesPerSecond = 0
        refreshPlayback()
    }

    /// The eyes go to a point on screen, and come back after a moment.
    func look(at point: CGPoint) {
        look(toward: point, hold: 0.9)
    }

    func setReducedMotion(_ value: Bool) {
        reducedMotion = value
        applyMood()
        refreshPlayback()
    }

    func place(_ frame: CGRect, layoutWidth: CGFloat) {
        let resized = RautaPlacement(width: layoutWidth) != placement
        self.frame = frame
        self.layoutWidth = layoutWidth
        guard performing else { return }
        if !quiet { director.enter(id, frame: frame) }
        if resized {
            framesPerSecond = 0
            refreshPlayback()
        }
    }

    private func subscribe() {
        cancellables.removeAll()
        director.beats
            .sink { [weak self] beat in self?.hear(beat) }
            .store(in: &cancellables)
        director.touches
            .sink { [weak self] touch in self?.notice(touch) }
            .store(in: &cancellables)
        director.context
            .dropFirst()
            .sink { [weak self] next in
                self?.context = next
                self?.applyMood()
            }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.framesPerSecond = 0
                self?.refreshPlayback()
            }
            .store(in: &cancellables)
    }

    private func beginPerforming() {
        if !quiet { director.enter(id, frame: frame) }
        applied = nil
        applyMood()
        enliven(for: 1.2)
        startIdle()
        // Something happened while no character was on screen — a set saved on
        // a page without one. The first to come back answers it; a quiet one,
        // waiting to take over, leaves it alone.
        if !quiet, let beat = director.claimUnanswered() { play(beat.reaction, source: .explicit) }
    }

    private func stopPerforming() {
        for task in [idleTask, gazeReturnTask, glanceTask, pressTask, playbackTask, sulkTask] {
            task?.cancel()
        }
        gazeReturnTask = nil
        glanceTask = nil
        pendingTriggers.removeAll()
        playingLively = false
        director.leave(id)
        rig.pause()
    }

    // MARK: Mood

    private var effectiveMood: RautaMood {
        if let borrowedMood { return borrowedMood }
        if let spokenMood { return spokenMood }
        let now = Date()
        if now < sulkUntil { return .skeptical }
        return context.mood(for: baseMood, now: now)
    }

    private func applyMood(blinks: Bool = true) {
        guard performing else { return }
        let mood = effectiveMood
        let intensity = mood.intensity * (reducedMotion ? 0.55 : 1)
        if let applied, applied.mood == mood, applied.intensity == intensity { return }
        let shifted = applied != nil && applied?.mood != mood
        applied = (mood, intensity)
        write("status", Double(mood.status))
        write("intensity", intensity)
        moodChangedAt = Date()
        guard shifted else { return }
        // A shift of feeling is a shift of attention, and people blink on those.
        if blinks { fire(.blink) }
        enliven(for: 0.9)
    }

    // MARK: Reactions

    /// A reaction the screen asked for. With none named, it varies what it says
    /// so the same screen does not answer the same way twice.
    /// A new line, or silence. The lead character takes on the line's look and
    /// plays its beat; the others leave it to that one.
    func hear(_ line: RautaSpeech.Line?) {
        let leads = performing && director.leader == id
        let mood = leads ? line?.mood : nil
        if mood != spokenMood {
            spokenMood = mood
            applyMood()
        }
        if leads, let reaction = line?.reaction { play(reaction, source: .explicit) }
    }

    func explicit(_ reaction: RautaReaction?) {
        let chosen = reaction
            ?? RautaCues.acknowledgements[acknowledgementIndex % RautaCues.acknowledgements.count]
        if reaction == nil { acknowledgementIndex += 1 }
        play(chosen, source: .explicit)
    }

    @discardableResult
    private func play(_ requested: RautaReaction, source: RautaSource) -> Bool {
        guard performing else { return false }
        var reaction = reducedMotion ? requested.gentle : requested
        if placement == .badge { reaction = reaction.compact }
        let outcome = RautaScheduler.request(activity, source: source, reaction: reaction, now: Self.nowMs)
        activity = outcome.activity
        guard let played = outcome.play else { return false }
        fire(played)
        return true
    }

    /// Fires a trigger, waiting out a mood crossfade that has only just begun:
    /// a trigger fired into the first ~100 ms of one can be consumed before the
    /// new state's outgoing edge is live.
    private func fire(_ reaction: RautaReaction) {
        guard performing else { return }
        let ready = moodChangedAt.addingTimeInterval(0.12)
        guard ready > Date() else {
            pull(reaction)
            return
        }
        pendingTriggers.append((reaction, ready))
        enliven(for: reaction.duration + 0.5)
    }

    private func hear(_ beat: RautaDirector.Beat) {
        guard performing, !quiet else { return }
        if director.leader == id {
            play(beat.reaction, source: .explicit)
        } else if let lead = director.frame(of: director.leader) {
            // Someone else is answering: look over at them, and blink.
            look(toward: CGPoint(x: lead.midX, y: lead.midY), hold: min(2.2, beat.reaction.duration + 0.4))
            fire(.blink)
        }
    }

    /// A tap on the character itself also moves its eyes: they go to the finger
    /// first, and only then does the body answer.
    private func lookAtSelf(_ location: CGPoint) {
        glanceTask?.cancel()
        glanceTask = nil
        aim(at: RautaGaze.toward(location, from: CGRect(origin: .zero, size: frame.size)), speed: 34)
        returnGaze(after: 1.1)
    }

    // MARK: Idle

    private func startIdle() {
        idleTask?.cancel()
        idleTask = Task { @MainActor [weak self] in
            var delay = 1.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                // A thought that could not happen — something else still holds
                // the floor, a glance is still out — is tried again shortly,
                // not a whole thought later: that wait is what used to leave
                // the character with nothing to do.
                delay = self.idle()
                    ? RautaIdle.delay(for: self.applied?.mood ?? self.baseMood, random: RautaPerformer.random)
                    : RautaIdle.retryDelay
            }
        }
    }

    /// One idle thought. Returns whether it happened.
    @discardableResult
    private func idle() -> Bool {
        guard performing, !quiet, !dragging, !pressing else { return false }
        let now = Self.nowMs
        guard now >= activity.ambientDueAt, !activity.isHeld(at: now) else { return false }
        let beat = RautaIdle.beat(
            for: applied?.mood ?? baseMood,
            placement: placement,
            reducedMotion: reducedMotion,
            previous: previousIdle,
            previousDirection: previousGazeDirection,
            random: Self.random
        )
        previousIdle = beat
        // Every thought is also a moment of the mood loop moving again.
        enliven(for: 1.8)
        switch beat {
        case let .glance(glance):
            // Never pull the eyes off something the person is doing.
            guard gazeReturnTask == nil, glanceTask == nil else { return false }
            previousGazeDirection = glance.direction
            look(through: glance)
            return true
        case let .play(reaction):
            return play(reaction, source: .ambient)
        }
    }

    /// Walks the eyes through a look's stops, then lets them come home. A look
    /// that is interrupted — by a finger, by a cue — is simply cancelled where
    /// it stands.
    private func look(through glance: RautaGlance) {
        glanceTask?.cancel()
        glanceTask = Task { @MainActor [weak self] in
            for stop in glance.stops {
                guard !Task.isCancelled, let self, self.performing else { return }
                self.aim(at: (stop.x, stop.y), speed: stop.speed)
                try? await Task.sleep(for: .seconds(stop.hold))
            }
            guard !Task.isCancelled, let self else { return }
            self.glanceTask = nil
            self.returnGaze(after: 0)
        }
    }

    // MARK: Attention

    private func notice(_ touch: RautaDirector.Touch) {
        guard performing, !quiet, !dragging, frame.width > 0 else { return }
        // A touch on the character itself is handled as touch, not as something
        // to look at.
        if frame.insetBy(dx: -6, dy: -6).contains(touch.point) { return }
        let distance = Double(hypot(touch.point.x - frame.midX, touch.point.y - frame.midY))
        switch touch.phase {
        case .began:
            look(toward: touch.point, hold: RautaTouch.noticeHold(distance: distance))
            // Where the finger went is the answer; now and then the character
            // has something to say about it too.
            if let reaction = RautaTouch.noticeReaction(distance: distance, random: Self.random) {
                if reaction.isEyesOnly {
                    fire(reaction)
                } else {
                    play(reaction, source: .ambient)
                }
            }
        case .moved:
            look(toward: touch.point, hold: 1.4)
        case .ended:
            returnGaze(after: 0.9)
        }
    }

    /// The eyes go to a point on screen. Whatever look was in progress gives
    /// way: what the person is doing always wins over the character's own
    /// thoughts.
    private func look(toward point: CGPoint, hold: TimeInterval) {
        glanceTask?.cancel()
        glanceTask = nil
        aim(at: RautaGaze.toward(point, from: frame), speed: 30)
        returnGaze(after: hold)
    }

    private func aim(at target: (x: Double, y: Double), speed: Double) {
        guard performing else { return }
        gazeTarget = target
        gazeSpeed = speed
        enliven(for: 0.5)
    }

    private func returnGaze(after delay: TimeInterval) {
        gazeReturnTask?.cancel()
        gazeReturnTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.gazeReturnTask = nil
            self.aim(at: RautaGaze.rest(random: RautaPerformer.random), speed: 7)
        }
    }

    // MARK: Frames

    /// One rendered frame: move whatever is still on its way somewhere.
    private func advance(_ seconds: Double) {
        guard performing, seconds > 0 else { return }
        let dt = min(seconds, 0.05)
        var moving = false

        if !pendingTriggers.isEmpty {
            let now = Date()
            let due = pendingTriggers.filter { $0.at <= now }
            pendingTriggers.removeAll { $0.at <= now }
            due.forEach { pull($0.reaction) }
        }

        let dx = gazeTarget.x - gaze.x
        let dy = gazeTarget.y - gaze.y
        if abs(dx) > 0.002 || abs(dy) > 0.002 {
            let closing = 1 - exp(-dt * gazeSpeed)
            gaze = abs(dx) < 0.004 && abs(dy) < 0.004
                ? gazeTarget
                : (gaze.x + dx * closing, gaze.y + dy * closing)
            rig.setInput("gazeX", value: gaze.x)
            rig.setInput("gazeY", value: gaze.y)
            moving = true
        }

        if springing {
            // Underdamped, so a released turn swings a little past the front
            // before it settles.
            let acceleration = -140 * facing - 13 * facingVelocity
            facingVelocity += acceleration * dt
            facing += facingVelocity * dt
            if abs(facing) < 0.4, abs(facingVelocity) < 3 {
                facing = 0
                facingVelocity = 0
                springing = false
            }
            pushFacing()
            moving = true
        }

        if moving { enliven(for: 0.25) }
    }

    // MARK: Touch

    /// A tap. Taps in quick succession escalate until the character sulks.
    func tap() {
        let now = Date()
        tapTimes = tapTimes.filter { now.timeIntervalSince($0) < RautaTouch.streakWindow } + [now]
        let streak = tapTimes.count
        director.noteInteraction()
        if RautaTouch.sulks(afterTap: streak) {
            tapTimes.removeAll()
            sulk()
        }
        play(RautaTouch.reaction(forTap: streak), source: .interaction)
    }

    private func sulk() {
        sulkUntil = Date().addingTimeInterval(RautaTouch.sulkDuration)
        applyMood()
        sulkTask?.cancel()
        sulkTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(RautaTouch.sulkDuration))
            guard !Task.isCancelled else { return }
            self?.applyMood()
        }
    }

    /// Returns how far the character should give toward the finger.
    func touchChanged(_ value: DragGesture.Value) -> CGSize {
        guard performing else { return .zero }
        if touchBegan == nil {
            touchBegan = value.time
            // The eyes find the finger before the body answers it.
            lookAtSelf(value.location)
            pressTask?.cancel()
            // Held still for a moment, the character is being pressed: it
            // squashes under the finger and stays squashed.
            pressTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled, let self, self.touchBegan != nil, !self.dragging else { return }
                self.pressing = true
                self.write("pressed", true)
                self.enliven(for: 1)
            }
        }
        if !dragging, hypot(value.translation.width, value.translation.height) > 8 {
            beginDrag()
        }
        guard dragging else { return .zero }

        let turn = -Double(value.translation.width) * RautaTouch.degreesPerPoint(placement)
        springing = false
        facing = max(-175, min(175, turn))
        pushFacing()
        aim(at: RautaGaze.toward(value.location, from: CGRect(origin: .zero, size: frame.size)), speed: 40)
        return reducedMotion ? .zero : RautaTouch.leash(value.translation, placement: placement)
    }

    /// Returns whether the touch was a tap, for the view to activate.
    func touchEnded(_ value: DragGesture.Value) -> Bool {
        pressTask?.cancel()
        defer {
            touchBegan = nil
            dragging = false
            if pressing {
                pressing = false
                if performing { write("pressed", false) }
            }
            refreshPlayback()
        }
        guard performing, let began = touchBegan else { return false }
        let held = value.time.timeIntervalSince(began)

        if dragging {
            release(value, held: held)
            return false
        }
        if pressing, held >= 0.45 {
            play(RautaTouch.release(afterHolding: held, placement: placement), source: .interaction)
            return false
        }
        tap()
        return true
    }

    /// A touch the system took away — a scroll, an edge swipe, a presentation.
    /// Puts the body back the way a release would, without reacting to it as
    /// a tap or a throw. Returns whether a touch was actually in progress.
    func touchCancelled() -> Bool {
        guard touchBegan != nil else { return false }
        pressTask?.cancel()
        touchBegan = nil
        if dragging {
            dragging = false
            borrowedMood = nil
            applyMood()
            springing = true
            facingVelocity = 0
        }
        if pressing {
            pressing = false
            if performing { write("pressed", false) }
        }
        returnGaze(after: 0.35)
        refreshPlayback()
        return true
    }

    private func beginDrag() {
        dragging = true
        pressTask?.cancel()
        glanceTask?.cancel()
        glanceTask = nil
        gazeReturnTask?.cancel()
        gazeReturnTask = nil
        if !pressing {
            pressing = true
            write("pressed", true)
        }
        // A mood with its own scripted head turn ignores `facing`, so for as long
        // as a hand is turning the character it listens instead.
        if effectiveMood.hasScriptedYaw {
            borrowedMood = .listening
            applyMood()
        }
    }

    private func release(_ value: DragGesture.Value, held: TimeInterval) {
        borrowedMood = nil
        applyMood()
        let velocity = value.velocity
        let turned = abs(facing)
        if !reducedMotion,
           abs(velocity.width) > RautaTouch.spinVelocity,
           abs(velocity.width) > abs(velocity.height) {
            // Flung sideways: it spins all the way round and lands facing you.
            springing = false
            facing = 0
            facingVelocity = 0
            pushFacing()
            let now = Date()
            spinTimes = spinTimes.filter { now.timeIntervalSince($0) < RautaTouch.spinWindow } + [now]
            play(RautaTouch.spin(spinTimes.count, rightward: velocity.width > 0), source: .interaction)
        } else {
            springing = true
            facingVelocity = 0
            enliven(for: 1.2)
            if -velocity.height > RautaTouch.hopVelocity {
                play(.celebrate, source: .interaction)
            } else if turned > 110 {
                play(.wobble, source: .interaction)
            } else if held > 1.6 {
                play(.relieved, source: .interaction)
            }
        }
        returnGaze(after: 0.35)
    }

    /// Holds the body turned to `yaw` degrees; nil lets it swing back to face
    /// you on the usual spring.
    func hold(yaw: Double?) {
        guard let yaw else {
            guard !springing, facing != 0 else { return }
            springing = true
            facingVelocity = 0
            enliven(for: 1.2)
            return
        }
        springing = false
        facingVelocity = 0
        facing = yaw
        pushFacing()
        enliven(for: 0.3)
    }

    private func pushFacing() {
        let wrapped = (facing.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        rig.setInput("facing", value: wrapped)
    }

    // MARK: Rig

    /// A write from outside the frame loop. The runtime resumes rendering on any
    /// input change, so each one also books the playback it needs — otherwise
    /// one late write would leave the renderer running unseen.
    private func write(_ input: String, _ value: Double) {
        rig.setInput(input, value: value)
        enliven(for: 0.4)
    }

    private func write(_ input: String, _ value: Bool) {
        rig.setInput(input, value: value)
        enliven(for: 0.4)
    }

    private func pull(_ reaction: RautaReaction) {
        rig.triggerInput(reaction.rawValue)
        enliven(for: reaction.duration + 0.4)
    }

    // MARK: Energy

    private func enliven(for seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        // Called on every frame of a gesture or a spring: only a real extension
        // is worth rescheduling for.
        if playingLively, until < livelyUntil.addingTimeInterval(0.1) { return }
        if until > livelyUntil { livelyUntil = until }
        refreshPlayback()
    }

    /// How hard the renderer works.
    ///
    /// The artwork re-composes thousands of grain paths on every frame the body
    /// moves, so the rig renders at full rate only while something is happening
    /// — a reaction for its whole length, a glance, a touch, an idle thought.
    /// Between moments it keeps the mood's own loop running at a gentler rate,
    /// lower still in Low Power Mode, so a character on screen never freezes.
    /// Only a character nobody can see stops rendering.
    private func refreshPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        playingLively = false
        guard performing else {
            rig.pause()
            return
        }

        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        // Choreography holds its pace: a change of rate mid-move reads as a
        // stumble.
        if let pinned = pinnedFramesPerSecond {
            let target = lowPower ? min(pinned, 30) : pinned
            rig.play()
            if target != framesPerSecond, rig.riveView != nil {
                framesPerSecond = target
                rig.setPreferredFramesPerSecond(preferredFramesPerSecond: target)
            }
            return
        }
        let lively = Date() < livelyUntil || dragging || pressing
        let target: Int
        if lively {
            target = placement == .hero && !lowPower ? 60 : 30
        } else if lowPower {
            target = 12
        } else {
            // Motion that is the expression itself — a hop, a tremor — needs
            // more frames to read than a breath does.
            let mood = applied?.mood ?? baseMood
            target = mood.keepsMoving || placement == .hero ? 24 : 20
        }
        rig.play()
        if target != framesPerSecond, rig.riveView != nil {
            framesPerSecond = target
            rig.setPreferredFramesPerSecond(preferredFramesPerSecond: target)
        }

        guard lively else { return }
        playingLively = true
        let remaining = max(dragging || pressing ? 0.25 : 0.05, livelyUntil.timeIntervalSinceNow)
        playbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.refreshPlayback()
        }
    }
}
