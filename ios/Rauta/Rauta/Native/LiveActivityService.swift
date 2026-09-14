import Combine
import Foundation

/// Everything the Lock Screen card and the Dynamic Island need for one frame.
///
/// The timer is deliberately *not* a duration: ActivityKit is handed the
/// wall-clock instant the stopwatch effectively started and left to count on its
/// own, so a running workout needs no per-second updates. A paused workout has no
/// instant to count from, so it carries the frozen elapsed time instead — which
/// keeps every field a pure function of the session and lets the sync skip
/// updates that would not change a pixel.
struct LiveActivityContent: Equatable {
    /// Identifies the card: a different workout replaces it rather than updating
    /// it, because ActivityKit attributes are immutable.
    var workoutId: String
    var workoutName: String
    var workoutDate: String
    /// Shown on the Lock Screen only; the Dynamic Island stays workout-level.
    var exerciseName: String
    var completedCount: Int
    var totalCount: Int
    /// Epoch ms; 0 while paused.
    var timerStartEpochMs: Double
    /// Frozen elapsed time; 0 while running.
    var elapsedMs: Double
    var isPaused: Bool
    /// The accent chosen in Settings, `0xRRGGBB`.
    var accentHex: Int
}

@MainActor
enum LiveActivitySync {
    /// The Live Activity frame for a session. Pure: same session, same frame.
    static func content(for session: ActiveWorkoutSession) -> LiveActivityContent {
        let exercise = ActiveWorkout.currentExercise(session)
        let progress = ActiveWorkout.progress(session)
        let isPaused = session.runningSince == nil

        return LiveActivityContent(
            workoutId: session.workoutId,
            workoutName: session.workoutName,
            workoutDate: CalendarDate.long(session.workoutDate),
            exerciseName: exercise.map { Wording.titleCase($0.name) } ?? "All exercises done",
            completedCount: progress.completed,
            totalCount: progress.total,
            timerStartEpochMs: isPaused ? 0 : (session.runningSince ?? 0) - session.accumulatedMs,
            elapsedMs: isPaused ? session.accumulatedMs : 0,
            isPaused: isPaused,
            accentHex: Int(SettingsStore.shared.accent.signature.primary)
        )
    }

    /// The closing frame: the timer stops and the progress reads as final.
    private static func endContent(for session: ActiveWorkoutSession) -> LiveActivityContent {
        var frame = content(for: session)
        frame.exerciseName = "Workout complete"
        frame.timerStartEpochMs = 0
        frame.elapsedMs = ActiveWorkout.elapsedMs(session)
        frame.isPaused = true
        return frame
    }

    private static var lastFrame: LiveActivityContent?
    private static var lastWorkoutId: String?
    private static var previousSession: ActiveWorkoutSession?
    private static var cancellable: AnyCancellable?
    private static var accentCancellable: AnyCancellable?

    private static func render(_ session: ActiveWorkoutSession) {
        let frame = content(for: session)
        if frame == lastFrame { return }

        // The first frame of a session starts the activity — which adopts a card
        // that outlived the last launch, so a session restored from storage
        // reconnects instead of orphaning it. Switching to a different workout
        // also starts: the card's workout name lives in ActivityKit attributes,
        // which are fixed for the life of an activity.
        let needsStart = lastWorkoutId != frame.workoutId
        lastFrame = frame
        lastWorkoutId = frame.workoutId

        if needsStart { WorkoutActivityBridge.start(frame) }
        else { WorkoutActivityBridge.update(frame) }
    }

    private static func stop(_ session: ActiveWorkoutSession, dismissImmediately: Bool) {
        guard lastFrame != nil else { return }
        lastFrame = nil
        lastWorkoutId = nil
        WorkoutActivityBridge.end(endContent(for: session), dismissImmediately: dismissImmediately)
    }

    /// Mirrors the workout store onto the ActivityKit lifecycle: one start when a
    /// workout begins, an update whenever a frame would actually differ, and one
    /// end when it stops.
    static func start() {
        let store = ActiveWorkoutStore.shared
        previousSession = store.session
        if let initial = store.session { render(initial) }

        cancellable = store.changed
            .sink {
                let current = store.session
                let previous = previousSession
                previousSession = current
                if current == previous { return }
                if let current {
                    render(current)
                } else if let previous {
                    stop(previous, dismissImmediately: store.lastOutcome != .finished)
                }
            }

        // A card already on the Lock Screen takes a new accent straight away;
        // the changed colour makes the frame differ, so this is one update.
        accentCancellable = SettingsStore.shared.changed
            .map { SettingsStore.shared.accent }
            // Seeded with the accent in use, so only a real change gets through
            // — including the very first one.
            .prepend(SettingsStore.shared.accent)
            .removeDuplicates()
            .dropFirst()
            .sink { _ in
                if let current = store.session { render(current) }
            }
    }
}
