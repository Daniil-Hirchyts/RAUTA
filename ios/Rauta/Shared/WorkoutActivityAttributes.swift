import ActivityKit
import Foundation

/// The workout a Live Activity is following. Attributes are fixed for the life
/// of an activity, so anything that changes while exercising belongs in
/// ``ContentState`` instead — and starting a *different* workout has to end the
/// card and request a new one (see `WorkoutLiveActivity.start`).
nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
    /// One frame of a workout in progress. Kept small and `Hashable` so the
    /// system can tell two consecutive updates apart cheaply; the web layer
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
    }

    var workoutId: String
    var workoutName: String
    var workoutDate: String
}

nonisolated extension WorkoutActivityAttributes.ContentState {
    var progressText: String { "\(completedCount) of \(totalCount) done" }

    var accent: WorkoutActivityColor { WorkoutActivityPalette.accent(accentHex) }

    var isComplete: Bool { totalCount > 0 && completedCount >= totalCount }

    /// "MM:SS", widening to "H:MM:SS" past an hour — the same shape the app
    /// renders, so the Lock Screen and the screen agree.
    var elapsedText: String {
        let total = max(0, Int(elapsed))
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = total / 3600

        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}
