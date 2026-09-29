import Foundation
import Testing
@testable import Rauta

/// Deleting, reusing and filing workouts; what survives a relaunch; the warm-up
/// routine; Summary's figures; and the sound files the app plays.
@Suite("Workout flows", .serialized)
struct WorkoutFlowTests {
    // MARK: Deleting

    /// A trained workout takes its logged sessions with it, so nothing counts
    /// a workout that can no longer be seen.
    @Test func deletingATrainedWorkoutRemovesItsSessions() async throws {
        try await withIsolatedStores {
            let bench = try #require(ExerciseResolver.resolve("barbell bench press").first?.exercise.id)
            let id = try await EngineWorkout.createWorkout(date: CalendarDate.today, exerciseIds: [bench])
            let workout = try #require(WorkoutsStore.shared.workout(id))
            #expect(ActiveWorkoutStore.shared.start(workout).refusal == nil)

            let records = TrainingRecordsStore.shared
            let exercise = try #require(records.data.activeWorkout?.exercises.first)
            let set = try #require(exercise.sets.first { $0.setType == .working } ?? exercise.sets.first)
            try records.recordSet(
                exerciseEntryId: exercise.id,
                setDraftId: set.id,
                observation: PersistedSetObservation(reps: 8, resistance: set.target?.resistance ?? .bodyweight,
                                                     rir: 2, completed: true, timestamp: ISOTime.now())
            )
            guard case .saved = ActiveWorkoutStore.shared.finish() else {
                Issue.record("The workout did not finish"); return
            }
            #expect(records.data.sessions.contains { $0.sourceWorkoutId == id })
            #expect(TrainingEdits.isHistory(try #require(WorkoutsStore.shared.workout(id))))

            try TrainingEdits.deleteWorkout(id)
            #expect(WorkoutsStore.shared.workout(id) == nil)
            #expect(!records.data.sessions.contains { $0.sourceWorkoutId == id })
            #expect(PersistenceValidation.validate(records.data).isEmpty)
        }
    }

    @Test func aWorkoutStillToComeIsDeletedWithoutTouchingHistory() async throws {
        try await withIsolatedStores {
            let id = WorkoutsStore.shared.createWorkout(
                name: "Legs", date: CalendarDate.shift(CalendarDate.today, by: 2), exerciseIds: []
            )
            #expect(!TrainingEdits.isHistory(try #require(WorkoutsStore.shared.workout(id))))
            try TrainingEdits.deleteWorkout(id)
            #expect(WorkoutsStore.shared.workout(id) == nil)
        }
    }

    // MARK: Filing and reusing

    /// Only workouts more can still go into: not finished, not overdue, and
    /// never the one being reused.
    @Test func destinationsAreTheWorkoutsStillAhead() async throws {
        try await withIsolatedStores {
            let today = CalendarDate.today
            let store = WorkoutsStore.shared
            let overdue = store.createWorkout(name: "Overdue", date: CalendarDate.shift(today, by: -1), exerciseIds: [])
            let now = store.createWorkout(name: "Today", date: today, exerciseIds: [])
            let later = store.createWorkout(name: "Later", date: CalendarDate.shift(today, by: 3), exerciseIds: [])
            let source = store.createWorkout(name: "Source", date: CalendarDate.shift(today, by: 1), exerciseIds: [])
            let done = store.createWorkout(name: "Done", date: today, exerciseIds: [])
            store.completeWorkout(done, WorkoutCompletion(
                startedAt: ISOTime.now(), completedAt: ISOTime.now(), durationMs: 60_000,
                completedExerciseIds: [], activeCalories: 0, healthSyncStatus: .notRequested
            ))

            let ids = WorkoutTimeline.destinations(
                workouts: store.workouts,
                records: TrainingRecordsStore.shared.data,
                activeWorkoutId: nil,
                excluding: source
            ).map(\.id)
            #expect(ids == [now, later])
            #expect(!ids.contains(overdue))
        }
    }

    @Test func reusingKeepsTheNameAndRefusesThePast() async throws {
        try await withIsolatedStores {
            let bench = try #require(ExerciseResolver.resolve("barbell bench press").first?.exercise.id)
            let source = WorkoutsStore.shared.createWorkout(
                name: "Push day", date: CalendarDate.shift(CalendarDate.today, by: -3), exerciseIds: [bench]
            )
            let tomorrow = CalendarDate.shift(CalendarDate.today, by: 1)
            let id = try await EngineWorkout.reuse(source, date: tomorrow)
            let reused = try #require(WorkoutsStore.shared.workout(id))
            #expect(reused.name == "Push day")
            #expect(reused.date == tomorrow)
            #expect(reused.exerciseIds == [bench])

            await #expect(throws: (any Error).self) {
                _ = try await EngineWorkout.reuse(source, date: CalendarDate.shift(CalendarDate.today, by: -1))
            }
        }
    }

    // MARK: What survives a relaunch

    @Test func rautaFocusSurvivesSanitizing() {
        let workout = Workout(
            id: "w1", name: "Upper", date: "2026-10-01", exerciseIds: [],
            completion: nil, createdAt: "", updatedAt: "", planned: nil,
            rautaFocus: [.chest, .triceps]
        )
        let restored = WorkoutsStore.sanitize(.object(["workouts": .array([workout.jsonTree])])).workouts
        #expect(restored.first?.rautaFocus == [.chest, .triceps])

        var plain = workout
        plain.rautaFocus = nil
        let restoredPlain = WorkoutsStore.sanitize(.object(["workouts": .array([plain.jsonTree])])).workouts
        #expect(restoredPlain.first?.rautaFocus == nil)
    }

    @Test func aWarmupStillRunningIsKeptAndOneOverIsDropped() throws {
        let bench = try #require(ExerciseResolver.resolve("barbell bench press").first?.exercise.id)
        let now = ActiveWorkout.nowMillis()
        func session(warmupUntil: Double) -> JSONValue {
            ActiveWorkoutSession(
                workoutId: "w1", workoutName: "Push", workoutDate: CalendarDate.today,
                exerciseIds: [bench], completedIds: [], currentExerciseId: bench,
                runningSince: now, accumulatedMs: 0, startedAt: now,
                setPhaseStartedAt: now, restUntil: nil, warmupUntil: warmupUntil
            ).jsonTree
        }
        #expect(ActiveWorkoutStore.sanitizeSession(session(warmupUntil: now + 60_000))?.warmupUntil == now + 60_000)
        #expect(ActiveWorkoutStore.sanitizeSession(session(warmupUntil: now - 60_000))?.warmupUntil == nil)
    }

    @Test(arguments: [
        (JSONValue.number(300), 300.0),
        (.number(0), 0),
        (.number(123), 180),
        (.string("long"), 180),
        (.null, 180),
    ])
    func warmupLengthIsOneOfTheChoices(_ stored: JSONValue, _ expected: Double) {
        let preferences = SettingsStore.sanitize(.object(["warmupSeconds": stored]))
        #expect(preferences.warmupSeconds == expected)
    }

    @Test func workoutSoundsStartOnAndInterfaceSoundsOff() {
        let preferences = SettingsStore.sanitize(.object([:]))
        #expect(preferences.workoutSoundsEnabled)
        #expect(!preferences.soundChimesEnabled)
    }

    // MARK: Warm-up

    @Test func everyWarmupStepSaysWhatToDoAndWhere() {
        for plan in WarmupRoutine.pulse + WarmupRoutine.upper + WarmupRoutine.lower + WarmupRoutine.full {
            #expect(!plan.muscles.isEmpty, "\(plan.title) lights nothing")
            #expect(plan.instruction.count > 20, "\(plan.title) says too little")
        }
    }

    @Test func aWarmupOpensWithThePulseAndSharesItsTime() throws {
        let bench = try #require(ExerciseResolver.resolve("barbell bench press").first?.exercise.id)
        let steps = WarmupRoutine.steps(for: [bench], seconds: 180, seed: "w1")
        #expect(steps.count == 4)
        #expect(WarmupRoutine.pulse.map(\.instruction).contains(try #require(steps.first).instruction))
        #expect(steps.dropFirst().map(\.title) == WarmupRoutine.upper.prefix(3).map(\.title))
        #expect(steps.first?.start == 0)
        #expect(steps.last?.end == 180)
        for (earlier, later) in zip(steps, steps.dropFirst()) {
            #expect(earlier.end == later.start)
        }
        #expect(WarmupRoutine.steps(for: [bench], seconds: 180, seed: "w1") == steps)
        #expect(WarmupRoutine.steps(for: [bench], seconds: 600, seed: "w1").count == 5)
        #expect(WarmupRoutine.steps(for: [bench], seconds: 0, seed: "w1").isEmpty)
        #expect(WarmupRoutine.region(for: [bench]) == .upper)
    }

    // MARK: Summary

    @Test func aMonthsWeeksCoverEveryDayOnce() {
        let ranges = SummaryAnalytics.weekRanges("2026-09")
        #expect(ranges.count == 5)
        #expect(ranges.first?.hasPrefix("1") == true)
        #expect(ranges.last { !$0.isEmpty }?.hasSuffix("30") == true)
        #expect(SummaryAnalytics.shiftMonth("2026-01", by: -1) == "2025-12")
        #expect(SummaryAnalytics.shiftMonth("2026-12", by: 1) == "2027-01")
    }

    /// A best is found per way of holding the weight, from working sets only,
    /// with Epley's estimate from the strongest.
    @Test func recordsKeepEachWayOfHoldingApart() {
        func set(_ kg: Double, _ reps: Double, _ basis: LoadBasis?, _ type: SetType = .working) -> CompletedSet {
            CompletedSet(id: UUID().uuidString, plannedSetId: nil, reps: reps,
                         resistance: ResistanceValue(type: .externalLoad, kg: kg, basis: basis),
                         rir: 2, rpe: nil, completed: true, setType: type, side: .both, timestamp: nil)
        }
        let session = PersistedCompletedSession(
            id: "s1", sourceWorkoutId: "w1", plannedProgramId: nil, plannedSessionId: nil,
            startedAt: "2026-09-01T18:00:00.000Z", completedAt: "2026-09-01T19:00:00.000Z",
            durationSeconds: 3_600, status: .completed,
            exercises: [
                PersistedCompletedExercise(id: "e1", exerciseId: "bench", plannedExerciseId: nil,
                                           exerciseNameSnapshot: nil,
                                           sets: [set(60, 8, .total), set(100, 1, .total, .warmup), set(62.5, 5, .total)]),
                PersistedCompletedExercise(id: "e2", exerciseId: "bench", plannedExerciseId: nil,
                                           exerciseNameSnapshot: nil,
                                           sets: [set(30, 10, .perImplement)]),
            ]
        )
        let records = SummaryAnalytics.records([session])
        #expect(records.count == 2)
        let total = records.first { $0.basis == .total }
        #expect(total?.heaviestKg == 62.5)
        #expect(total?.heaviestReps == 5)
        #expect(total?.sets == 2)
        #expect(abs((total?.estimatedMaxKg ?? 0) - 60 * (1 + 8.0 / 30)) < 0.01)
        #expect(records.first { $0.basis == .perImplement }?.heaviestKg == 30)
    }

    // MARK: Sounds

    @Test func everySoundIsBundled() {
        for sound in RautaSound.allCases {
            #expect(Bundle.main.url(forResource: sound.rawValue, withExtension: "caf") != nil, "Missing \(sound.rawValue).caf")
        }
        #expect(RautaSound.tick(secondsLeft: 3) == .tick3)
        #expect(RautaSound.tick(secondsLeft: 1) == .tick1)
        #expect(RautaSound.menuOpen.channel == .interface)
        #expect(RautaSound.restOver.channel == .cue)
    }

    // MARK: Isolation

    /// Runs `body` against empty stores in a throwaway storage location, with
    /// no warm-up, and puts everything back afterwards.
    private func withIsolatedStores(_ body: () async throws -> Void) async throws {
        try #require(ActiveWorkoutStore.shared.session == nil, "Finish the simulator's workout first")
        let suite = "rauta-flow-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: suite, directoryHint: .isDirectory)
        let previousDefaults = Storage.defaults
        let records = TrainingRecordsStore.shared.data
        let workouts = WorkoutsStore.shared.workouts
        let settings = SettingsStore.shared.preferences
        Storage.defaults = defaults
        Storage.directoryOverride = directory
        defer {
            if ActiveWorkoutStore.shared.session != nil {
                ActiveWorkoutStore.shared.setSession(nil, outcome: .cancelled)
            }
            TrainingRecordsStore.shared.replaceAll(records)
            WorkoutsStore.shared.replaceAll(workouts)
            SettingsStore.shared.replaceAll(settings)
            Storage.defaults = previousDefaults
            Storage.directoryOverride = nil
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        TrainingRecordsStore.shared.replaceAll(.empty())
        WorkoutsStore.shared.replaceAll([])
        SettingsStore.shared.update { $0.warmupSeconds = 0 }
        try await body()
    }
}
