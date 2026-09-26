import Foundation
import Testing
@testable import Rauta

/// The seams RAUTA's agent works through: plans built before they are kept,
/// readiness reaching the engine, changes that can be taken back exactly, and
/// exercises found from the way people name them.
@Suite("Agent seams", .serialized)
struct AgentSeamsTests {
    @Test func healthReadinessKeepsMissingDataMissingAndNeverSetsPain() {
        let empty = HealthReadinessSnapshot(sleepHours: nil, hrvTodayMs: nil,
            hrvBaselineMs: nil, restingHeartRateToday: nil,
            restingHeartRateBaseline: nil, exerciseMinutesYesterday: nil,
            activeEnergyYesterday: nil)
        #expect(ReadinessMapper.map(empty) == nil)
        var tired = empty
        tired.sleepHours = 5.5
        tired.hrvTodayMs = 30
        tired.hrvBaselineMs = 45
        let result = ReadinessMapper.map(tired)
        #expect(result?.readiness.perceivedReadiness == .low)
        #expect(result?.readiness.pain == nil)
        #expect(result?.reasons.count == 2)
    }

    /// The Hub cache lays a snapshot out as symlinks into its blobs; the size
    /// that counts is the blob's.
    @Test func aDownloadedSnapshotIsCompleteThroughItsSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "rauta-snapshot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let blobs = root.appending(path: "blobs")
        let snapshot = root.appending(path: "snapshots/abc")
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        func blob(_ name: String, bytes: Int) throws {
            try Data(count: bytes).write(to: blobs.appending(path: name))
        }
        func link(_ file: String, to name: String) throws {
            try FileManager.default.createSymbolicLink(
                atPath: snapshot.appending(path: file).path(percentEncoded: false),
                withDestinationPath: "../../blobs/\(name)")
        }
        try blob("config", bytes: 10)
        try blob("tokenizer", bytes: 10)
        try blob("stub", bytes: 10)
        try link("config.json", to: "config")
        try link("tokenizer.json", to: "tokenizer")
        try link("model.safetensors", to: "stub")
        #expect(!RautaModelFiles.isComplete(snapshot))

        try blob("weights", bytes: 2_000_000)
        try FileManager.default.removeItem(at: snapshot.appending(path: "model.safetensors"))
        try link("model.safetensors", to: "weights")
        #expect(RautaModelFiles.isComplete(snapshot))
    }

    @Test func agentWordsResolveDaysAndRejectInventedNumbers() {
        #expect(AgentWords.day("next Friday", today: "2026-09-26") == "2026-10-02")
        #expect(AgentWords.rescheduledDay("Thursday", workoutDate: "2026-09-30", today: "2026-09-26") == "2026-10-01")
        #expect(AgentWords.said(90, in: "Make sessions forty minutes") == nil)
        #expect(AgentWords.said(40, in: "Make sessions forty minutes") == 40)
        #expect(AgentWords.said(22.5, in: "Log 8 reps at 22.5 kg") == 22.5)
        #expect(AgentWords.said(25.0, in: "Log 8 reps at 22.5 kg") == nil)
        #expect(!AgentWords.isDate("2026-02-30"))
    }

    /// The two requests that failed on the iPhone — a schedule chip and a
    /// workout build — run from their words to a card without the model.
    @Test func plainRequestsReachACardWithoutTheModel() async throws {
        try await withIsolatedStores {
            let bench = try #require(ExerciseResolver.resolve("barbell bench press").first?.exercise.id)
            _ = WorkoutsStore.shared.createWorkout(
                name: "Push", date: CalendarDate.shift(CalendarDate.today, by: 1), exerciseIds: [bench])
            let host = AgentToolHost()

            let ask = "What's coming up?"
            host.begin(ask)
            await host.perform(try #require(AgentIntent.parse(ask, today: CalendarDate.today, running: false)), input: ask)
            guard case .sessions(_, let rows)? = host.outcome?.card else {
                Issue.record("No schedule card: \(host.outcome?.say ?? "nothing")"); return
            }
            #expect(rows.map(\.title) == ["Push"])

            let build = "Build the workout for shoulders and legs"
            host.begin(build)
            await host.perform(try #require(AgentIntent.parse(build, today: CalendarDate.today, running: false)), input: build)
            guard case .proposal(let proposal)? = host.outcome?.card else {
                Issue.record("No workout preview: \(host.outcome?.say ?? "nothing")"); return
            }
            #expect(proposal.state == .pending)
            #expect(!(proposal.rows.first?.exerciseIds.isEmpty ?? true))
            // A preview only: nothing was saved.
            #expect(WorkoutsStore.shared.workouts.count == 1)
        }
    }

    @Test func hostRejectsPastDatesAndUnknownReplacements() async throws {
        try await withIsolatedStores {
            let bench = try #require(ExerciseResolver.resolve("barbell bench press").first?.exercise.id)
            let id = WorkoutsStore.shared.createWorkout(
                name: "Push", date: CalendarDate.shift(CalendarDate.today, by: 1),
                exerciseIds: [bench]
            )
            let host = AgentToolHost()
            host.begin("Move Push to 2020-01-01")
            host.reschedule(workoutPhrase: id, dayPhrase: "2020-01-01")
            #expect(WorkoutsStore.shared.workout(id)?.date != "2020-01-01")
            #expect(host.outcome?.say.contains("today onward") == true)

            host.begin("Swap bench for xyzzy in Push")
            host.swap(workoutPhrase: id, exercisePhrase: "bench", replacementPhrase: "xyzzy")
            #expect(WorkoutsStore.shared.workout(id)?.exerciseIds == [bench])
            #expect(host.outcome?.say.contains("fitting replacement") == true)
        }
    }

    @Test func hostRefusesAPlanWhenItsBasisChanged() async throws {
        try await withIsolatedStores {
            let host = AgentToolHost()
            host.begin("Build a plan for two days a week")
            await host.proposePlan(daysPerWeek: 2, sessionMinutes: nil)
            guard case .proposal(let card) = host.outcome?.card else {
                Issue.record("Expected a plan preview")
                return
            }
            WorkoutsStore.shared.createWorkout(name: "Extra", date: CalendarDate.today,
                                               exerciseIds: [])
            let result = await host.apply(card.id)
            #expect(result.say.contains("changed"))
            #expect(TrainingRecordsStore.shared.data.programs.isEmpty)
        }
    }

    @Test func deletingAWorkoutWaitsForApplyAndCanBeUndone() async throws {
        try await withIsolatedStores {
            let id = WorkoutsStore.shared.createWorkout(
                name: "Push", date: CalendarDate.shift(CalendarDate.today, by: 1), exerciseIds: []
            )
            let host = AgentToolHost()
            host.begin("Delete my Push workout")
            host.proposeDelete("Push")
            guard case .proposal(let card) = host.outcome?.card else {
                Issue.record("Expected a delete preview")
                return
            }
            #expect(WorkoutsStore.shared.workout(id) != nil)
            let result = await host.apply(card.id)
            #expect(result.proposalApplied)
            #expect(WorkoutsStore.shared.workout(id) == nil)
            let undo = try #require(result.undo)
            #expect((await host.undo(undo)).say == "Undone.")
            #expect(WorkoutsStore.shared.workout(id) != nil)
        }
    }

    @Test func movingAWorkoutCanBeUndoneExactly() async throws {
        try await withIsolatedStores {
            let original = CalendarDate.shift(CalendarDate.today, by: 1)
            let moved = CalendarDate.shift(CalendarDate.today, by: 2)
            let id = WorkoutsStore.shared.createWorkout(name: "Push", date: original, exerciseIds: [])
            let host = AgentToolHost()
            host.begin("Move Push to \(moved)")
            host.reschedule(workoutPhrase: id, dayPhrase: moved)
            #expect(WorkoutsStore.shared.workout(id)?.date == moved)
            let action = try #require(host.outcome?.undo)
            #expect((await host.undo(action)).say == "Undone.")
            #expect(WorkoutsStore.shared.workout(id)?.date == original)
        }
    }

    @Test func aSupportedSwapCanBeUndone() async throws {
        try await withIsolatedStores {
            let bench = try #require(ExerciseResolver.resolve("barbell bench press").first?.exercise)
            let id = WorkoutsStore.shared.createWorkout(
                name: "Push", date: CalendarDate.shift(CalendarDate.today, by: 1),
                exerciseIds: [bench.id]
            )
            let replacementId = try #require(TrainingWorkflow.replacementIds(bench.id, workoutId: id).first)
            let replacement = try #require(ExerciseCatalogue.byId[replacementId])
            let host = AgentToolHost()
            host.begin("Swap \(bench.name) for \(replacement.name) in Push")
            host.swap(workoutPhrase: id, exercisePhrase: bench.name,
                      replacementPhrase: replacement.name)
            #expect(WorkoutsStore.shared.workout(id)?.exerciseIds == [replacementId])
            let action = try #require(host.outcome?.undo)
            #expect((await host.undo(action)).say == "Undone.")
            #expect(WorkoutsStore.shared.workout(id)?.exerciseIds == [bench.id])
        }
    }
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
