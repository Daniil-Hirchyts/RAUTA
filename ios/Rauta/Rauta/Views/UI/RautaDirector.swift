import Combine
import SwiftUI
import UIKit

/// One RAUTA, however many are drawn.
///
/// Every placement renders its own character, but there is a single
/// personality behind them. The director is that personality's senses: it
/// watches the stores for things that happened, feels every touch on the screen,
/// keeps the clock of how long the person has been away, and remembers how the
/// last moment felt. Each on-screen character subscribes and answers in its own
/// place — and when several are visible, only the most prominent one answers a
/// cue while the others look over at it.
///
/// Screens do not need to call into it. What they record is diffed here, so the
/// character reacts to the product rather than to buttons.
@MainActor
final class RautaDirector {
    static let shared = RautaDirector()

    struct Beat {
        let id: Int
        let cue: RautaCue
        let reaction: RautaReaction
        let line: String
        let at: Date
    }

    enum TouchPhase { case began, moved, ended }

    struct Touch {
        /// In window coordinates, the same space as SwiftUI's `.global`.
        let point: CGPoint
        let phase: TouchPhase
    }

    /// Cues worth a reaction, already coalesced and varied.
    let beats = PassthroughSubject<Beat, Never>()
    /// Every finger anywhere on screen, throttled while moving.
    let touches = PassthroughSubject<Touch, Never>()
    let context = CurrentValueSubject<RautaContext, Never>(RautaContext())

    private(set) var lastInteraction = Date()

    private var started = false
    private var cancellables = Set<AnyCancellable>()

    private var pendingCue: RautaCue?
    private var flushTask: Task<Void, Never>?
    private var nextBeatId = 0
    /// A beat nobody was on screen to answer, kept briefly for the next
    /// character to appear — the one waiting on the page you return to.
    private var unanswered: Beat?

    private var restTask: Task<Void, Never>?
    private var afterglowTask: Task<Void, Never>?
    private var driftTask: Task<Void, Never>?
    private var backgroundedAt: Date?

    // What the stores looked like last time, for diffing.
    private var session: ActiveWorkoutSession?
    private var draftId: String?
    private var loggedSets = 0
    private var activePlanIds: Set<String> = []
    private var workoutIds: Set<String> = []
    private var favoriteCount = 0

    /// Characters currently on stage, by the frame they occupy.
    private var stage: [UUID: CGRect] = [:]

    /// Above zero while a change is being made that is answered somewhere else.
    private var quietDepth = 0

    private init() {}

    // MARK: Lifecycle

    /// Idempotent. Called by the first character to appear, so nothing about
    /// app launch has to know RAUTA exists.
    func start() {
        installTouchObserver()
        guard !started else { return }
        started = true

        snapshotStores()
        updateWorkoutPhase()

        ActiveWorkoutStore.shared.changed
            .sink { [weak self] in self?.workoutChanged() }
            .store(in: &cancellables)
        TrainingRecordsStore.shared.changed
            .sink { [weak self] in self?.recordsChanged() }
            .store(in: &cancellables)
        WorkoutsStore.shared.changed
            .sink { [weak self] in self?.workoutsChanged() }
            .store(in: &cancellables)
        FavoritesStore.shared.changed
            .sink { [weak self] in self?.favoritesChanged() }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        center.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.backgroundedAt = Date() }
            .store(in: &cancellables)
        center.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.becameActive() }
            .store(in: &cancellables)

        startDriftClock()
    }

    private func becameActive() {
        installTouchObserver()
        if let away = backgroundedAt.map({ Date().timeIntervalSince($0) }), away > 15 * 60 {
            cue(.welcomeBack)
        }
        backgroundedAt = nil
        lastInteraction = Date()
        updateDrift()
        updateWorkoutPhase()
    }

    // MARK: Cues

    /// Makes a change whose result is already being shown — in the chat, say —
    /// so the stores are still followed but RAUTA does not announce it twice.
    func quietly<T>(_ body: () throws -> T) rethrows -> T {
        quietDepth += 1
        defer { quietDepth -= 1 }
        return try body()
    }

    func quietly<T>(_ body: () async throws -> T) async rethrows -> T {
        quietDepth += 1
        defer { quietDepth -= 1 }
        return try await body()
    }

    /// Something happened. Cues landing within a moment of each other are one
    /// event seen from several stores; the most meaningful of them is answered.
    private func cue(_ cue: RautaCue) {
        guard quietDepth == 0 else { return }
        if let pendingCue, pendingCue.salience >= cue.salience { return }
        pendingCue = cue
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            self?.flush()
        }
    }

    private func flush() {
        flushTask = nil
        guard let cue = pendingCue else { return }
        pendingCue = nil

        let response = RautaCues.pick(cue)
        nextBeatId += 1
        let beat = Beat(
            id: nextBeatId, cue: cue, reaction: response.reaction,
            line: response.line, at: Date()
        )
        if let glow = cue.afterglow { setAfterglow(glow.mood, for: glow.seconds) }
        // RAUTA says what it saw. Coming back to the app is answered with what
        // to do next instead, which the main screen works out.
        if cue != .welcomeBack {
            RautaSpeech.shared.say(Self.spoken(response.line, for: cue), reaction: nil)
        }

        if stage.isEmpty {
            unanswered = beat
        } else {
            unanswered = nil
            beats.send(beat)
        }
    }

    /// A saved set starts the rest, so RAUTA says how long it is: the person
    /// hears the timer from the one keeping it.
    private static func spoken(_ line: String, for cue: RautaCue) -> String {
        guard !line.isEmpty, cue == .setSaved || cue == .hardSetSaved || cue == .personalBest,
              let restUntil = ActiveWorkoutStore.shared.session?.restUntil
        else { return line }
        let seconds = Int(((restUntil - Date().timeIntervalSince1970 * 1000) / 1000).rounded())
        guard seconds > 0 else { return line }
        let clock = seconds >= 60
            ? WorkoutClock.format(seconds)
            : "\(seconds) s"
        return "\(line) Rest \(clock)."
    }

    /// The beat a character arriving on stage should still answer, if any.
    func claimUnanswered() -> Beat? {
        guard let beat = unanswered, Date().timeIntervalSince(beat.at) < 2.5 else {
            unanswered = nil
            return nil
        }
        unanswered = nil
        return beat
    }

    /// Haptics are the app's own record of "the person just did something".
    /// Strong ones are a cue; all of them count as the person being here.
    func feedback(_ input: HapticInput) {
        noteInteraction()
        switch input {
        case .success: cue(.confirmed)
        case .warning: cue(.warned)
        case .selection, .light, .medium, .heavy: break
        }
    }

    // MARK: Stage

    func enter(_ id: UUID, frame: CGRect) {
        stage[id] = frame
    }

    func leave(_ id: UUID) {
        stage[id] = nil
    }

    /// The character that answers cues: the biggest one on screen.
    var leader: UUID? {
        stage.max { lhs, rhs in
            let left = lhs.value.width * lhs.value.height
            let right = rhs.value.width * rhs.value.height
            return left == right ? lhs.key.uuidString > rhs.key.uuidString : left < right
        }?.key
    }

    func frame(of id: UUID?) -> CGRect? {
        id.flatMap { stage[$0] }
    }

    // MARK: Attention

    func noteInteraction() {
        lastInteraction = Date()
        guard let drift = context.value.drift else { return }
        var next = context.value
        next.drift = nil
        context.send(next)
        cue(drift == .sleepy ? .wokeUp : .noticed)
    }

    fileprivate func touch(_ point: CGPoint, phase: TouchPhase) {
        if phase == .began { noteInteraction() }
        touches.send(Touch(point: point, phase: phase))
    }

    private func installTouchObserver() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows
            where !(window.gestureRecognizers ?? []).contains(where: { $0 is RautaTouchObserver }) {
                window.addGestureRecognizer(RautaTouchObserver { [weak self] point, phase in
                    self?.touch(point, phase: phase)
                })
            }
        }
    }

    // MARK: Mood

    private func setAfterglow(_ mood: RautaMood, for seconds: TimeInterval) {
        var next = context.value
        next.afterglow = mood
        next.afterglowUntil = Date().addingTimeInterval(seconds)
        context.send(next)

        afterglowTask?.cancel()
        afterglowTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            var faded = self.context.value
            faded.afterglow = nil
            self.context.send(faded)
        }
    }

    private func startDriftClock() {
        driftTask?.cancel()
        driftTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                self?.updateDrift()
            }
        }
    }

    private func updateDrift() {
        guard UIApplication.shared.applicationState == .active else { return }
        let drift = RautaContext.drift(
            idleFor: Date().timeIntervalSince(lastInteraction),
            hour: Calendar.current.component(.hour, from: Date()),
            workout: context.value.workout
        )
        guard drift != context.value.drift else { return }
        var next = context.value
        next.drift = drift
        context.send(next)
    }

    private func updateWorkoutPhase() {
        let phase: RautaWorkoutPhase
        restTask?.cancel()
        if let session = ActiveWorkoutStore.shared.session {
            let now = ActiveWorkout.nowMillis()
            if session.runningSince == nil {
                phase = .paused
            } else if let restUntil = session.restUntil, restUntil > now {
                let deadline = Date(epochMillis: restUntil)
                phase = .resting(until: deadline)
                restTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(Int(restUntil - now)))
                    guard !Task.isCancelled, let self,
                          ActiveWorkoutStore.shared.session?.restUntil == restUntil
                    else { return }
                    self.cue(.restOver)
                    self.updateWorkoutPhase()
                }
            } else {
                phase = .working
            }
        } else {
            phase = .none
        }
        guard phase != context.value.workout else { return }
        var next = context.value
        next.workout = phase
        if phase != .none { next.drift = nil }
        context.send(next)
    }

    // MARK: Store diffs

    private func snapshotStores() {
        session = ActiveWorkoutStore.shared.session
        let records = TrainingRecordsStore.shared.data
        draftId = records.activeWorkout?.id
        loggedSets = Self.loggedSetCount(records.activeWorkout)
        activePlanIds = Self.activePlanIds(records)
        workoutIds = Set(WorkoutsStore.shared.workouts.map(\.id))
        favoriteCount = FavoritesStore.shared.favoriteIds.count
    }

    private func workoutChanged() {
        let store = ActiveWorkoutStore.shared
        let previous = session
        let current = store.session
        session = current
        defer { updateWorkoutPhase() }

        switch (previous, current) {
        case (nil, .some):
            cue(.workoutStarted)
        case (.some, nil):
            cue(store.lastOutcome == .finished ? .workoutFinished : .workoutCancelled)
        case let (.some(before), .some(after)):
            guard before.workoutId == after.workoutId else {
                cue(.workoutStarted)
                return
            }
            if before.runningSince != nil, after.runningSince == nil { cue(.workoutPaused) }
            if before.runningSince == nil, after.runningSince != nil { cue(.workoutResumed) }
            if !Set(after.completedIds).subtracting(before.completedIds).isEmpty {
                let everything = Set(after.exerciseIds).isSubset(of: Set(after.completedIds))
                cue(everything ? .allExercisesDone : .exerciseCompleted)
            }
        case (nil, nil):
            break
        }
    }

    private func recordsChanged() {
        let records = TrainingRecordsStore.shared.data

        let sets = Self.loggedSetCount(records.activeWorkout)
        if records.activeWorkout?.id == draftId, sets > loggedSets {
            if SummaryAnalytics.isPersonalBest(records.activeWorkout, history: records.sessions) {
                cue(.personalBest)
            } else {
                cue(Self.lastSetWasHard(records.activeWorkout) ? .hardSetSaved : .setSaved)
            }
        }
        draftId = records.activeWorkout?.id
        loggedSets = sets

        let plans = Self.activePlanIds(records)
        if let added = plans.subtracting(activePlanIds).first,
           let record = records.programs.first(where: { $0.id == added }) {
            cue(record.revision == nil ? .planCreated : .planAdjusted)
        }
        activePlanIds = plans
    }

    private func workoutsChanged() {
        let workouts = WorkoutsStore.shared.workouts
        let ids = Set(workouts.map(\.id))
        let added = ids.subtracting(workoutIds)
        let removed = workoutIds.subtracting(ids)
        workoutIds = ids
        // One at a time is a person; dozens at once is a sync, a restore or a
        // generated plan, which have their own cues.
        if added.count == 1, removed.isEmpty,
           workouts.first(where: { added.contains($0.id) })?.planned == nil {
            cue(.workoutCreated)
        } else if removed.count == 1, added.isEmpty {
            cue(.workoutDeleted)
        }
    }

    private func favoritesChanged() {
        let count = FavoritesStore.shared.favoriteIds.count
        if count == favoriteCount + 1 { cue(.favoriteAdded) }
        favoriteCount = count
    }

    private static func loggedSetCount(_ draft: PersistedActiveWorkoutDraft?) -> Int {
        draft?.exercises.reduce(0) { total, exercise in
            total + exercise.sets.filter { $0.observation?.completed == true }.count
        } ?? 0
    }

    /// A set taken to failure, by its reps in reserve or effort.
    private static func lastSetWasHard(_ draft: PersistedActiveWorkoutDraft?) -> Bool {
        let observations = draft?.exercises
            .flatMap { $0.sets.compactMap(\.observation) }
            .filter(\.completed) ?? []
        guard let latest = observations.max(by: { ($0.timestamp ?? "") < ($1.timestamp ?? "") })
        else { return false }
        return latest.rir == 0 || (latest.rpe ?? 0) >= 9.5
    }

    private static func activePlanIds(_ records: PersistedTrainingState) -> Set<String> {
        Set(records.programs
            .filter { $0.effectiveKind == .plan && $0.lifecycle == .active }
            .map(\.id))
    }
}

/// Watches every touch in a window without taking part in it.
///
/// It never recognises, never cancels or delays touches, and lets every other
/// recognizer run alongside it, so scrolling, buttons and SwiftUI gestures
/// behave exactly as if it were not there.
private final class RautaTouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let report: (CGPoint, RautaDirector.TouchPhase) -> Void
    private var lastMoveReport: TimeInterval = 0

    init(report: @escaping (CGPoint, RautaDirector.TouchPhase) -> Void) {
        self.report = report
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        report(touch.location(in: nil), .began)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        // Eyes following a finger need far fewer updates than the finger makes.
        guard touch.timestamp - lastMoveReport > 1.0 / 12 else { return }
        lastMoveReport = touch.timestamp
        report(touch.location(in: nil), .moved)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { report(touch.location(in: nil), .ended) }
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { report(touch.location(in: nil), .ended) }
        state = .failed
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool { true }
}
