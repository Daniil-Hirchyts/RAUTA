import Foundation

/// A workout being performed right now. The timer is stored as a running
/// stretch plus banked time rather than a tick count, so it survives a relaunch,
/// a backgrounded app and a suspended process without drifting — and so the
/// Live Activity can be handed a single start instant and left to count on its
/// own.
struct ActiveWorkoutSession: Codable, Hashable, Sendable {
    var workoutId: String
    var workoutName: String
    var workoutDate: String
    var exerciseIds: [String]
    var completedIds: [String]
    var currentExerciseId: String?
    /// Epoch ms the current running stretch began; nil while paused.
    var runningSince: Double?
    /// Elapsed time banked by every stretch before the current one.
    var accumulatedMs: Double
    var startedAt: Double
    /// Epoch ms when the current set phase began. Unlike a view-local timer,
    /// this survives tab changes, backgrounding and relaunches with the session.
    var setPhaseStartedAt: Double?
    /// Epoch ms when the current rest period ends. While this is in the future
    /// the UI counts down; afterwards the next set counts up from that instant.
    var restUntil: Double?
    /// Epoch ms when the warm-up that opens the workout ends. Set only while
    /// the warm-up is on; the first set is due when it is cleared.
    var warmupUntil: Double? = nil
}

enum ExerciseStatus: String { case pending, active, completed }

enum ActiveWorkout {
    /// JavaScript's `Date.now()` — used by the React app and persisted transition
    /// journal — is an integer millisecond timestamp. Keep the native port on the
    /// same precision so an ISO-8601 round trip compares exactly in validation.
    static func nowMillis() -> Double {
        (Date().timeIntervalSince1970 * 1000).rounded(.down)
    }

    static func elapsedMs(_ session: ActiveWorkoutSession, now: Double = ActiveWorkout.nowMillis()) -> Double {
        let running = session.runningSince.map { now - $0 } ?? 0
        return Swift.max(0, session.accumulatedMs + running)
    }

    /// The instant a stopwatch would have to have been started for it to read
    /// `elapsedMs` right now. `Text(timerInterval:)` counts from a date entirely
    /// on its own, so shifting that date is how a paused and resumed workout
    /// stays correct without pushing an update every second.
    static func timerStartEpochMs(
        _ session: ActiveWorkoutSession,
        now: Double = ActiveWorkout.nowMillis()
    ) -> Double {
        now - elapsedMs(session, now: now)
    }

    static func formatDuration(_ ms: Double) -> String {
        ElapsedClock.format(seconds: Int(Swift.max(0, ms) / 1000))
    }

    static func status(_ session: ActiveWorkoutSession, _ exerciseId: String) -> ExerciseStatus {
        if session.completedIds.contains(exerciseId) { return .completed }
        return session.currentExerciseId == exerciseId ? .active : .pending
    }

    struct Progress {
        var completed: Int
        var total: Int
        var isComplete: Bool
    }

    static func progress(_ session: ActiveWorkoutSession) -> Progress {
        let completed = session.exerciseIds.filter { session.completedIds.contains($0) }.count
        return Progress(
            completed: completed,
            total: session.exerciseIds.count,
            isComplete: !session.exerciseIds.isEmpty && completed == session.exerciseIds.count
        )
    }

    /// The exercise to move to after `fromId` is done: the next one still
    /// pending in list order, wrapping past the end so an exercise skipped
    /// earlier is picked up rather than stranded. Nil once nothing is left.
    static func nextPendingExerciseId(
        _ session: ActiveWorkoutSession,
        from fromId: String? = nil
    ) -> String? {
        let target = fromId ?? session.currentExerciseId
        let ids = session.exerciseIds
        guard !ids.isEmpty else { return nil }
        let start = target.flatMap { ids.firstIndex(of: $0) } ?? -1

        for step in 1...ids.count {
            let index = ((start + step) % ids.count + ids.count) % ids.count
            let id = ids[index]
            if id != target && !session.completedIds.contains(id) { return id }
        }
        return nil
    }

    static func currentExercise(_ session: ActiveWorkoutSession) -> ExerciseSummary? {
        session.currentExerciseId.flatMap { ExerciseCatalogue.byId[$0] }
    }
}
