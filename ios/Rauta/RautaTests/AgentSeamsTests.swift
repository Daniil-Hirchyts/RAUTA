import Foundation
import Testing
@testable import Rauta

/// The seams RAUTA's agent works through: plans built before they are kept,
/// readiness reaching the engine, changes that can be taken back exactly, and
/// exercises found from the way people name them.
@Suite("Agent seams", .serialized)
struct AgentSeamsTests {
    // MARK: Finding exercises

    @Test func namesFoldToTheCataloguesWords() {
        #expect(ExerciseResolver.words("Pull-Ups") == ["pull", "up"])
        #expect(ExerciseResolver.words("pullup") == ["pull", "up"])
        #expect(ExerciseResolver.words("RDLs") == ["romanian", "deadlift"])
        #expect(ExerciseResolver.words("DB bench") == ["dumbbell", "bench"])
        #expect(ExerciseResolver.words("biceps") == ["biceps"])
        #expect(ExerciseResolver.words("bench press") == ["bench", "press"])
    }

    @Test func shorthandFindsTheExercise() throws {
        let rdl = try #require(ExerciseResolver.resolve("RDL").first)
        #expect(rdl.exercise.name.contains("romanian deadlift"))
        // "lat" is a word of its own here, not the start of "lateral".
        let pulldown = try #require(ExerciseResolver.resolve("lat pulldown").first)
        let words = ExerciseResolver.words(pulldown.exercise.name)
        #expect(words.contains("lat") && words.contains("pulldown"))
    }

    @Test func equipmentNarrowsTheMatch() throws {
        let bench = try #require(ExerciseResolver.resolve("bench press", equipment: ["barbell"]).first)
        #expect(bench.exercise.name == "barbell bench press")
    }

    @Test func whatThePersonDoesBreaksTies() throws {
        let dumbbell = try #require(ExerciseCatalogue.allByName.first { $0.name == "dumbbell bench press" })
        let match = try #require(ExerciseResolver.resolve("bench press", preferred: [dumbbell.id]).first)
        #expect(match.exercise.id == dumbbell.id)
    }

    @Test func anIdIsItsOwnAnswerAndNonsenseHasNone() throws {
        let exercise = try #require(ExerciseCatalogue.all.first)
        #expect(ExerciseResolver.resolve(exercise.id).first?.exercise.id == exercise.id)
        #expect(ExerciseResolver.resolve("xyzzy plugh").isEmpty)
    }

    // MARK: Readiness

    @Test func readinessReachesTheEngineRequest() {
        let readiness = Readiness(
            perceivedReadiness: .low,
            soreness: [SorenessEntry(muscleId: .quadriceps, level: .high)],
            pain: nil
        )
        let now = ISOTime.now()
        #expect(PlanGeneration.request(weekStart: nil, offsets: [0, 2, 4], now: now, readiness: readiness)
            .readiness == readiness)
        #expect(PlanGeneration.request(weekStart: nil, offsets: [0, 2, 4], now: now).readiness == nil)
    }

    // MARK: Building a plan before keeping it

    @Test func aPreviewSavesNothingAndKeepingItTwiceKeepsItOnce() async throws {
        try await withIsolatedStores {
            let records = TrainingRecordsStore.shared
            let dates = [CalendarDate.shift(CalendarDate.today, by: 7), CalendarDate.shift(CalendarDate.today, by: 9)]
            let before = records.data

            let outcome = try #require(await TrainingPlan.previewTrainingPlanForDates(dates: dates))
            guard case .ready(let preview) = outcome else {
                Issue.record("The simulator's profile could not be planned for: \(outcome)")
                return
            }
            #expect(records.data == before)
            #expect(WorkoutsStore.shared.workouts.isEmpty)
            #expect(preview.sessions.count == dates.count)
            #expect(preview.isCurrent())

            let sessions = try TrainingPlan.commit(preview)
            #expect(records.data.activeProgramId == preview.program.id)
            #expect(WorkoutsStore.shared.workouts.count == sessions.count)
            // Keeping it is itself a change to what it was built from.
            #expect(!preview.isCurrent())

            let programs = records.data.programs.count
            try TrainingPlan.commit(preview)
            #expect(records.data.programs.count == programs)
            #expect(WorkoutsStore.shared.workouts.count == sessions.count)
        }
    }

    @Test func aChangeSinceThePreviewMakesItStale() async throws {
        try await withIsolatedStores {
            let dates = [CalendarDate.shift(CalendarDate.today, by: 8)]
            let outcome = try #require(await TrainingPlan.previewTrainingPlanForDates(dates: dates))
            guard case .ready(let preview) = outcome else {
                Issue.record("The simulator's profile could not be planned for: \(outcome)")
                return
            }
            #expect(preview.isCurrent())
            WorkoutsStore.shared.createWorkout(
                name: "Extra", date: CalendarDate.today, exerciseIds: [], planned: nil
            )
            #expect(!preview.isCurrent())
        }
    }

    // MARK: Taking a change back

    @Test func aSetIsTakenBackOnlyWhileItIsAsTheChangeLeftIt() async throws {
        try await withIsolatedStores {
            let records = TrainingRecordsStore.shared
            let exerciseId = try #require(ExerciseResolver.resolve("barbell bench press").first?.exercise.id)
            try records.startFreeWorkout(exerciseIds: [exerciseId])
            defer { try? records.cancelWorkout() }
            let entry = try #require(records.data.activeWorkout?.exercises.first)

            let logged = PersistedSetObservation(
                reps: 8, resistance: nil, rir: 2, rpe: nil, completed: false, timestamp: nil
            )
            let setId = try records.addUnplannedSet(
                exerciseEntryId: entry.id, setType: .working, side: .both, observation: logged
            )
            var newer = logged
            newer.reps = 10

            #expect(throws: (any Error).self) {
                try records.revertSetObservation(
                    exerciseEntryId: entry.id, setDraftId: setId, expected: newer, restoring: nil
                )
            }
            try records.revertSetObservation(
                exerciseEntryId: entry.id, setDraftId: setId, expected: logged, restoring: nil
            )
            let set = records.data.activeWorkout?.exercises.first?.sets.first { $0.id == setId }
            #expect(set != nil)
            #expect(set?.observation == nil)
        }
    }

    @Test func aSwappedExerciseIsRestoredAsItWas() async throws {
        try await withIsolatedStores {
            let records = TrainingRecordsStore.shared
            let bench = try #require(ExerciseResolver.resolve("barbell bench press").first?.exercise.id)
            let press = try #require(ExerciseResolver.resolve("dumbbell bench press").first?.exercise.id)
            try records.startFreeWorkout(exerciseIds: [bench])
            defer { try? records.cancelWorkout() }
            let original = try #require(records.data.activeWorkout?.exercises.first)

            try records.substituteExercise(exerciseEntryId: original.id, exerciseId: press)
            let swapped = try #require(records.data.activeWorkout?.exercises.first)
            #expect(swapped.exerciseId == press)

            try records.restoreActiveExercise(original, expected: swapped)
            #expect(records.data.activeWorkout?.exercises.first == original)
            #expect(throws: (any Error).self) {
                try records.restoreActiveExercise(original, expected: swapped)
            }
        }
    }

    // MARK: Isolation

    /// Runs against empty stores kept in a temporary place, then puts the
    /// simulator's own data back. Refuses while a workout is running there,
    /// because clearing the workout list would end it.
    private func withIsolatedStores(_ body: () async throws -> Void) async throws {
        try #require(ActiveWorkoutStore.shared.session == nil, "Finish the simulator's workout first")
        let suite = "rauta-agent-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: suite, directoryHint: .isDirectory)
        let previousDefaults = Storage.defaults
        let records = TrainingRecordsStore.shared.data
        let workouts = WorkoutsStore.shared.workouts
        Storage.defaults = defaults
        Storage.directoryOverride = directory
        defer {
            TrainingRecordsStore.shared.replaceAll(records)
            WorkoutsStore.shared.replaceAll(workouts)
            Storage.defaults = previousDefaults
            Storage.directoryOverride = nil
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        TrainingRecordsStore.shared.replaceAll(.empty())
        WorkoutsStore.shared.replaceAll([])
        try await body()
    }
}
