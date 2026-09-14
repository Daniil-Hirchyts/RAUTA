import Combine
import RiveRuntime
import SwiftUI

/// Uses the exact artboard and state machine shipped by the React app.
///
/// The view is a thin shell. What this character does with its body lives in
/// ``RautaPerformer``; what RAUTA knows about the app lives in
/// ``RautaDirector``; what it can express lives in `RautaVocabulary`.
struct RautaCharacter: View {
    var mood: RautaMood = .calm
    var reactionKey = ""
    var reaction: RautaReaction?
    var onActivate: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.rautaOnStage) private var onStage
    @StateObject private var performer = RautaPerformer()
    @State private var leash = CGSize.zero

    var body: some View {
        performer.rig.view()
            .offset(leash)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                performer.place(frame)
            }
            .onAppear {
                performer.appear(mood: mood, reducedMotion: reducedMotion, onStage: onStage)
                if let reaction { performer.explicit(reaction) }
            }
            .onDisappear { performer.disappear() }
            .onChange(of: mood) { _, next in performer.setMood(next) }
            .onChange(of: reactionKey) { _, _ in performer.explicit(reaction) }
            .onChange(of: reducedMotion) { _, next in performer.setReducedMotion(next) }
            .onChange(of: scenePhase) { _, next in performer.setSceneActive(next == .active) }
            .onChange(of: onStage) { _, next in performer.setOnStage(next) }
            .contentShape(Rectangle())
            .gesture(
                // One gesture for every kind of touch, so a tap, a held press and
                // a drag are told apart by what the finger did rather than by
                // which recognizer won.
                DragGesture(minimumDistance: 0)
                    .onChanged { value in leash = performer.touchChanged(value) }
                    .onEnded { value in
                        if performer.touchEnded(value) {
                            onActivate?()
                            Haptics.trigger(.light)
                        }
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.5)) { leash = .zero }
                    }
            )
            .accessibilityLabel(onActivate == nil ? "Interact with RAUTA" : "Open RAUTA actions")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                performer.tap()
                onActivate?()
            }
    }
}

private struct RautaOnStageKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False for a character on a page that another page currently covers. It
    /// keeps its place in the layout but stops performing, and never answers a
    /// cue nobody can see.
    var rautaOnStage: Bool {
        get { self[RautaOnStageKey.self] }
        set { self[RautaOnStageKey.self] = newValue }
    }
}

/// The artwork, parsed once for every character in the app rather than once per
/// placement.
@MainActor
private enum RautaArtwork {
    static let file: RiveFile? = try? RiveFile(name: "Media/rauta", extension: ".riv", in: .main, loadCdn: false)

    static func makeRig() -> RautaRig {
        guard let file else {
            return RautaRig(
                fileName: "Media/rauta",
                stateMachineName: "KettlebellBotMachine",
                autoPlay: true,
                artboardName: "KettlebellBot",
                loadCdn: false
            )
        }
        return RautaRig(
            RiveModel(riveFile: file),
            stateMachineName: "KettlebellBotMachine",
            autoPlay: true,
            artboardName: "KettlebellBot"
        )
    }
}

/// The rig, with a heartbeat. The runtime reports every frame it advances, and
/// the performer moves the eyes and the turn on that beat — in step with what is
/// drawn, and only while anything is drawn at all.
final class RautaRig: RiveViewModel {
    var onAdvance: (@MainActor (Double) -> Void)?

    override func player(didAdvanceby seconds: Double, riveModel: RiveModel?) {
        MainActor.assumeIsolated { onAdvance?(seconds) }
    }
}

/// One on-screen RAUTA's body: the rig, and everything this placement does with
/// it.
///
/// Four things drive it, in order of who wins. Cues the director hears from the
/// app. A finger on the character itself. The person touching anywhere else,
/// which the eyes follow. And, when nothing is happening, the character's own
/// idle thoughts, chosen by mood. Between those moments it holds its pose, so
/// the cost of drawing it follows how much is actually happening.
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
    private var appeared = false
    private var onStage = true
    private var sceneActive = true
    private var reducedMotion = false
    private var placement: RautaPlacement { RautaPlacement(width: frame.width) }
    private var performing: Bool { appeared && onStage && sceneActive }

    // How it feels.
    private var baseMood: RautaMood = .calm
    private var context = RautaContext()
    private var sulkUntil = Date.distantPast
    /// A mood held for the length of a gesture — see `beginDrag`.
    private var borrowedMood: RautaMood?
    private var applied: (mood: RautaMood, intensity: Double)?
    private var moodChangedAt = Date.distantPast

    // What it has been doing.
    private var activity = RautaActivity(now: RautaPerformer.nowMs)
    private var previousIdle: RautaIdleBeat?
    private var tapTimes: [Date] = []
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

    func appear(mood: RautaMood, reducedMotion: Bool, onStage: Bool) {
        appeared = true
        baseMood = mood
        self.reducedMotion = reducedMotion
        self.onStage = onStage
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

    func setMood(_ mood: RautaMood) {
        baseMood = mood
        applyMood()
    }

    func setReducedMotion(_ value: Bool) {
        reducedMotion = value
        applyMood()
        refreshPlayback()
    }

    func place(_ frame: CGRect) {
        let resized = RautaPlacement(width: frame.width) != placement
        self.frame = frame
        guard performing else { return }
        director.enter(id, frame: frame)
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
        director.enter(id, frame: frame)
        applied = nil
        applyMood()
        enliven(for: 1.2)
        startIdle()
        // Something happened while no character was on screen — a set saved on
        // a page without one. The first to come back answers it.
        if let beat = director.claimUnanswered() { play(beat.reaction, source: .explicit) }
    }

    private func stopPerforming() {
        for task in [idleTask, gazeReturnTask, pressTask, playbackTask, sulkTask] {
            task?.cancel()
        }
        gazeReturnTask = nil
        pendingTriggers.removeAll()
        playingLively = false
        director.leave(id)
        rig.pause()
    }

    // MARK: Mood

    private var effectiveMood: RautaMood {
        if let borrowedMood { return borrowedMood }
        let now = Date()
        if now < sulkUntil { return .skeptical }
        return context.mood(for: baseMood, now: now)
    }

    private func applyMood() {
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
        fire(.blink)
        enliven(for: 0.9)
    }

    // MARK: Reactions

    /// A reaction the screen asked for. With none named, it varies what it says
    /// so the same screen does not answer the same way twice.
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
        guard performing else { return }
        if director.leader == id {
            play(beat.reaction, source: .explicit)
        } else if let lead = director.frame(of: director.leader) {
            // Someone else is answering: look over at them, and blink.
            look(toward: CGPoint(x: lead.midX, y: lead.midY), hold: min(2.2, beat.reaction.duration + 0.4))
            fire(.blink)
        }
    }

    // MARK: Idle

    private func startIdle() {
        idleTask?.cancel()
        idleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let delay = self.map { RautaIdle.delay(for: $0.applied?.mood ?? $0.baseMood, random: RautaPerformer.random) } ?? 8
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.idle()
            }
        }
    }

    private func idle() {
        guard performing, !dragging, !pressing else { return }
        let now = Self.nowMs
        guard now >= activity.ambientDueAt, !activity.isHeld(at: now) else { return }
        let beat = RautaIdle.beat(
            for: applied?.mood ?? baseMood,
            placement: placement,
            reducedMotion: reducedMotion,
            previous: previousIdle,
            random: Self.random
        )
        previousIdle = beat
        // Every thought is also a moment of the mood loop moving again.
        enliven(for: 1.8)
        switch beat {
        case let .glance(x, y, hold):
            // Never pull the eyes off something the person is doing.
            guard gazeReturnTask == nil else { return }
            aim(at: (x, y), speed: 14)
            returnGaze(after: hold)
        case let .play(reaction):
            play(reaction, source: .ambient)
        }
    }

    // MARK: Attention

    private func notice(_ touch: RautaDirector.Touch) {
        guard performing, !dragging, frame.width > 0 else { return }
        // A touch on the character itself is handled as touch, not as something
        // to look at.
        if frame.insetBy(dx: -6, dy: -6).contains(touch.point) { return }
        switch touch.phase {
        case .began:
            look(toward: touch.point, hold: 1.6)
            if Self.random() < 0.2 { fire(.blink) }
        case .moved:
            look(toward: touch.point, hold: 1.4)
        case .ended:
            returnGaze(after: 0.9)
        }
    }

    private func look(toward point: CGPoint, hold: TimeInterval) {
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
            self.aim(at: (0, 0), speed: 7)
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

    private func beginDrag() {
        dragging = true
        pressTask?.cancel()
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
            play(velocity.width > 0 ? .spinRight : .spinLeft, source: .interaction)
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
    /// Between moments the character holds its pose, unless its mood is motion
    /// itself, which keeps a slow loop. Reduce Motion and Low Power Mode always
    /// hold still between moments, and a character nobody can see does not
    /// render at all.
    private func refreshPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        playingLively = false
        guard performing else {
            rig.pause()
            return
        }

        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let lively = Date() < livelyUntil || dragging || pressing
        let target: Int
        if lively {
            target = placement == .hero && !lowPower ? 60 : 30
        } else {
            let mood = applied?.mood ?? baseMood
            guard mood.keepsMoving, !reducedMotion, !lowPower else {
                rig.pause()
                return
            }
            target = placement == .hero ? 15 : 12
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

struct CompanionAction: Identifiable {
    var title: String
    var systemImage: String = "sparkles"
    var primary = false
    var action: () -> Void
    var id: String { title }
}

/// A compact header-sized RAUTA on a static glass circle. The character owns
/// any interaction; the glass behind it never flexes like a button.
struct RautaHeaderBadge: View {
    var mood: RautaMood = .focused
    var reactionKey = ""
    var reaction: RautaReaction?
    var onActivate: (() -> Void)?

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 44, height: 44)
                .glassSurface(
                    .regular,
                    in: Circle(),
                    border: Theme.Glassware.controlEdge,
                    legacyFill: .clear
                )
                .allowsHitTesting(false)

            RautaCharacter(
                mood: mood,
                reactionKey: reactionKey,
                reaction: reaction,
                onActivate: onActivate
            )
            .frame(width: 54, height: 54)
            .frame(width: 44, height: 44)
        }
        .frame(width: 44, height: 44)
    }
}

