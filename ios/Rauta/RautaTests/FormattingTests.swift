import Foundation
import Testing
@testable import Rauta

/// The shapes durations and clocks take on screen, pinned so that the copies
/// folded into one helper keep saying exactly what they said.
@Suite("Formatting")
struct FormattingTests {
    @Test func trainingDurations() {
        #expect(SummaryAnalytics.duration(0) == "0m")
        #expect(SummaryAnalytics.duration(29) == "0m")
        #expect(SummaryAnalytics.duration(30) == "1m")
        #expect(SummaryAnalytics.duration(59 * 60) == "59m")
        #expect(SummaryAnalytics.duration(60 * 60) == "1h")
        #expect(SummaryAnalytics.duration(65 * 60) == "1h 5m")
        #expect(SummaryAnalytics.duration(147 * 3_600 + 43 * 60) == "147h 43m")
    }

    @Test func workoutClocks() {
        #expect(WorkoutClock.format(0) == "0:00")
        #expect(WorkoutClock.format(9) == "0:09")
        #expect(WorkoutClock.format(90) == "1:30")
        #expect(WorkoutClock.format(3_600) == "60:00")
        #expect(WorkoutClock.format(-5) == "0:00")
    }

    @Test func elapsedWorkoutTime() {
        #expect(ActiveWorkout.formatDuration(0) == "00:00")
        #expect(ActiveWorkout.formatDuration(65_000) == "01:05")
        #expect(ActiveWorkout.formatDuration(3_599_999) == "59:59")
        #expect(ActiveWorkout.formatDuration(3_661_000) == "1:01:01")
        #expect(ActiveWorkout.formatDuration(-1) == "00:00")
    }
}
