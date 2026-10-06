import Foundation
import Testing
@testable import Rauta

/// Figures the app works out rather than stores: the streak, what a logged
/// kilogram means, and the frame the Lock Screen draws for a workout.

@Suite("Streak")
struct StreakTests {
    /// A Wednesday.
    private let today = CalendarDate.parse("2026-09-16") ?? Date()

    private func trained(_ dates: [String]) -> [Workout] {
        dates.enumerated().map { index, date in
            Workout(
                id: "w\(index)", name: "Workout", date: date, exerciseIds: ["a", "b"],
                completion: nil, createdAt: "", updatedAt: ""
            )
        }
    }

    /// With nothing logged yet today the run counts on from yesterday: a day
    /// still being lived in has not broken anything.
    @Test func aDayStillBeingLivedInBreaksNothing() {
        let streak = StreakBuilder.build(trained(["2026-09-14", "2026-09-15"]), today: today)
        #expect(streak.currentStreak == 2)
    }

    @Test func todayCountsOnceTrained() {
        let streak = StreakBuilder.build(trained(["2026-09-15", "2026-09-16"]), today: today)
        #expect(streak.currentStreak == 2)
    }

    @Test func aWholeDayMissedEndsTheRunButNotTheBest() {
        let streak = StreakBuilder.build(trained(["2026-09-13", "2026-09-14"]), today: today)
        #expect(streak.currentStreak == 0)
        #expect(streak.longestStreak == 2)
    }

    @Test func theBestRunCrossesMonthsAndCountsADayOnce() {
        let dates = ["2026-08-30", "2026-08-31", "2026-08-31", "2026-09-01", "2026-09-03"]
        #expect(StreakBuilder.build(trained(dates), today: today).longestStreak == 3)
    }

    /// The strip is the week being lived in, Monday to Sunday, with the days
    /// still ahead marked so they never read as missed.
    @Test func theWeekRunsMondayToSunday() {
        let streak = StreakBuilder.build(trained(["2026-09-14", "2026-09-14", "2026-09-20"]), today: today)
        #expect(streak.week.map(\.date) == (0..<7).map { CalendarDate.shift("2026-09-14", by: $0) })
        #expect(streak.week[0].workouts == 2)
        #expect(streak.week[0].exercises == 4)
        #expect(streak.week[2].isToday)
        let ahead = streak.week.map(\.isFuture)
        #expect(ahead == [false, false, false, true, true, true, true])
        #expect(streak.weekWorkouts == 3)
    }
}

@Suite("Resistance")
struct ResistanceTests {
    private func exercise(_ name: String) throws -> ExerciseSummary {
        try #require(ExerciseResolver.resolve(name).first?.exercise)
    }

    @Test func kilogramsAreWrittenTheWayAGymWritesThem() {
        #expect(Resistance.formatKg(80) == "80")
        #expect(Resistance.formatKg(82.5) == "82.5")
        #expect(Resistance.formatKg(82.50) == "82.5")
        #expect(Resistance.formatKg(1.25) == "1.25")
        #expect(Resistance.formatKg(0.333) == "0.33")
    }

    /// A dumbbell's kilograms are each hand's, a bar's are the whole load:
    /// two 30 kg dumbbells must never be read as 60 kg.
    @Test func theEquipmentSaysHowTheLoadIsHeld() throws {
        let bench = try exercise("barbell bench press")
        #expect(Resistance.modes(for: bench) == [.externalLoad])
        let bar = Resistance.loadContext(for: bench, mode: .externalLoad)
        #expect(bar.basis == .total)
        #expect(bar.stationId == bench.equipment)

        let curl = try exercise("dumbbell biceps curl")
        let dumbbell = Resistance.loadContext(for: curl, mode: .externalLoad)
        #expect(dumbbell.basis == .perImplement)
        #expect(dumbbell.grid.incrementKg == 2)
    }

    /// A pull-up is body weight, a weighted one added load, an assisted one
    /// assistance: three measurements progression must never mix.
    @Test func aBodyweightMovementKeepsItsThreeMeasurementsApart() throws {
        let pullUp = try exercise("pull up")
        let modes = Resistance.modes(for: pullUp)
        #expect(modes.contains(.bodyweight))
        #expect(modes.contains(.externalLoad))
        #expect(modes.first != .externalLoad)

        let added = Resistance.loadContext(for: pullUp, mode: .externalLoad)
        #expect(added.stationId == Resistance.addedLoadStation)
        let assisted = Resistance.loadContext(for: pullUp, mode: .assistance)
        #expect(assisted.stationId == Resistance.assistanceStation)
        #expect(assisted.basis == .total)

        #expect(Resistance.makeResistance(.bodyweight, 20, added) == .bodyweight)
        let weighted = Resistance.makeResistance(.externalLoad, 10, added)
        #expect(weighted.kg == 10)
        #expect(weighted.stationId == Resistance.addedLoadStation)
    }

    @Test func loadsStepAlongTheGridAndNeverBelowNothing() {
        let grid = LoadGrid(incrementKg: 2.5, minimumKg: 0)
        #expect(Resistance.stepLoad(60, 1, grid) == 62.5)
        #expect(Resistance.stepLoad(60, -1, grid) == 57.5)
        #expect(Resistance.stepLoad(0, -1, grid) == 0)
        #expect(Resistance.firstLoad(grid) == 0)
    }
}

@Suite("Live Activity frame")
struct LiveActivityFrameTests {
    private func session(
        running: Bool = true,
        restIn seconds: Double? = nil,
        warmupIn warmup: Double? = nil,
        allDone: Bool = false
    ) throws -> ActiveWorkoutSession {
        let bench = try #require(ExerciseResolver.resolve("barbell bench press").first?.exercise.id)
        let squat = try #require(ExerciseResolver.resolve("barbell full squat").first?.exercise.id)
        let now = ActiveWorkout.nowMillis()
        return ActiveWorkoutSession(
            workoutId: "w1",
            workoutName: "Push",
            workoutDate: CalendarDate.today,
            exerciseIds: [bench, squat],
            completedIds: allDone ? [bench, squat] : [],
            currentExerciseId: allDone ? nil : bench,
            runningSince: running ? now - 60_000 : nil,
            accumulatedMs: 30_000,
            startedAt: now - 600_000,
            setPhaseStartedAt: now - 20_000,
            restUntil: seconds.map { now + $0 * 1_000 },
            warmupUntil: warmup.map { now + $0 * 1_000 }
        )
    }

    /// A running workout hands the card the instant its stopwatch started, so
    /// the Lock Screen counts on its own with no updates.
    @Test func aRunningSetCountsFromWhenTheClockStarted() throws {
        let session = try session()
        let frame = LiveActivitySync.content(for: session)
        #expect(frame.phase == .set)
        #expect(!frame.isPaused)
        #expect(frame.timerStartEpochMs == (session.runningSince ?? 0) - session.accumulatedMs)
        #expect(frame.elapsedMs == 0)
        #expect(frame.restUntilEpochMs == nil)
        #expect(frame.completedCount == 0)
        #expect(frame.totalCount == 2)
        #expect(frame.animationEpochMs == session.startedAt - 60_000)
    }

    @Test func aPausedWorkoutCarriesItsTimeFrozen() throws {
        let paused = try session(running: false, restIn: 60)
        let frame = LiveActivitySync.content(for: paused)
        // Paused wins over a rest that is still running.
        #expect(frame.phase == .paused)
        #expect(frame.isPaused)
        #expect(frame.timerStartEpochMs == 0)
        #expect(frame.elapsedMs == 30_000)
    }

    @Test func aRestShowsUntilItRunsOut() throws {
        let resting = try session(restIn: 60)
        #expect(LiveActivitySync.content(for: resting).phase == .rest)
        #expect(LiveActivitySync.content(for: resting).restUntilEpochMs == resting.restUntil)

        let ended = try session(restIn: -1)
        let over = LiveActivitySync.content(for: ended)
        #expect(over.phase == .set)
        #expect(over.restUntilEpochMs == nil)
    }

    @Test func theWarmUpAndTheEndAreTheirOwnPhases() throws {
        let warmingUp = try session(warmupIn: 120)
        #expect(LiveActivitySync.content(for: warmingUp).phase == .warmup)
        let finished = try session(allDone: true)
        let done = LiveActivitySync.content(for: finished)
        #expect(done.phase == .done)
        #expect(done.completedCount == 2)
    }

    /// The same session gives the same frame, which is what lets the sync
    /// skip an update that would change nothing.
    @Test func theFrameIsAPureFunctionOfTheSession() throws {
        let session = try session(restIn: 45)
        #expect(LiveActivitySync.content(for: session) == LiveActivitySync.content(for: session))
    }
}
