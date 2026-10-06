import ActivityKit
import Foundation

/// The workout a Live Activity is following. Attributes are fixed for the life
/// of an activity, so anything that changes while exercising belongs in
/// ``ContentState`` instead — and starting a *different* workout has to end the
/// card and request a new one (see `WorkoutActivityBridge.start`).
nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
    /// One frame of a workout in progress. Kept small and `Hashable` so the
    /// system can tell two consecutive updates apart cheaply; `LiveActivitySync`
    /// already skips updates that would not change anything here.
    struct ContentState: Codable, Hashable {
        var exerciseName: String
        var completedCount: Int
        var totalCount: Int
        /// The instant a stopwatch would have had to start to read the current
        /// elapsed time. `nil` while paused — WidgetKit counts from this date
        /// on its own, which is what keeps a running workout push-free.
        var timerStart: Date?
        /// Frozen elapsed time, shown in place of the live timer while paused.
        var elapsed: TimeInterval
        var isPaused: Bool
        /// The app's accent, `0xRRGGBB`. In the state rather than the
        /// attributes so a card follows an accent changed mid-workout. Optional
        /// so a card from an older build still decodes.
        var accentHex: Int?

        // Optional too, for the same reason.

        /// What the workout is doing, which is what RAUTA does on the card.
        var phase: WorkoutActivityPhase?
        /// When the rest running now ends.
        var restUntil: Date?
        /// The instant RAUTA's frames count from. Fixed for the life of the
        /// card, so a fresh render never makes the animation jump.
        var animationEpoch: Date?
    }

    var workoutId: String
    var workoutName: String
    var workoutDate: String
}

/// What the workout is doing, as the Lock Screen shows it.
nonisolated enum WorkoutActivityPhase: String, Codable, Hashable, Sendable {
    case warmup, set, rest, paused, done
}

nonisolated extension WorkoutActivityAttributes.ContentState {
    var progressText: String { "\(completedCount) of \(totalCount) done" }

    /// Whether a rest is running at `date`: one that has run out is over,
    /// whether or not the app has said so yet.
    func isResting(at date: Date) -> Bool {
        guard let restUntil, !isPaused else { return false }
        return restUntil > date
    }

    var accent: WorkoutActivityColor { WorkoutActivityPalette.accent(accentHex) }

    var isComplete: Bool { totalCount > 0 && completedCount >= totalCount }

    var elapsedText: String { ElapsedClock.format(seconds: Int(max(0, elapsed))) }
}
