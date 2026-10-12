import Foundation
import Testing
@testable import Rauta

/// Complete backups, restores and the iCloud copy: nothing a person logged is
/// lost to a damaged file, an older backup, a second device or a restore cut
/// short. Every test runs on stores and backup folders of its own.
@Suite("Backup and recovery", .serialized)
@MainActor
struct BackupRecoveryTests {
    // MARK: Round trips

    @Test func aCompleteBackupRestoresEverythingItWasMadeFrom() async throws {
        try await IsolatedStores.run {
            try await IsolatedStores.finishWorkout()
            let planned = WorkoutsStore.shared.createWorkout(
                name: "Legs", date: CalendarDate.shift(CalendarDate.today, by: 2), exerciseIds: []
            )
            FavoritesStore.shared.toggleFavorite("0662")
            FiltersStore.shared.setGymEquipment(["dumbbell", "band"])
            FiltersStore.shared.setGymFixtures(["pull-up bar"])
            TrainingProfileStore.shared.updateProfile(.init(trainingExperience: .intermediate, goal: .hypertrophy))

            let records = TrainingRecordsStore.shared.data
            let workouts = WorkoutsStore.shared.workouts
            #expect(records.sessions.count == 1)

            let json = AppBackup.createBackup(includeLocalTraining: true)
            let preview = try BackupArchive.inspect(json)
            #expect(preview.checksumVerified)
            #expect(preview.hasTraining)
            #expect(preview.counts.sessions == 1)
            #expect(preview.counts.workouts == 2)
            #expect(preview.counts.favorites == 1)
            #expect(preview.warnings.isEmpty)

            AppBackup.clearAllData()
            #expect(TrainingRecordsStore.shared.data.sessions.isEmpty)
            #expect(WorkoutsStore.shared.workouts.isEmpty)

            try AppBackup.importBackup(json)
            #expect(TrainingRecordsStore.shared.data == records)
            #expect(WorkoutsStore.shared.workouts == workouts)
            #expect(WorkoutsStore.shared.workout(planned) != nil)
            #expect(FavoritesStore.shared.favoriteIds == ["0662"])
            #expect(FiltersStore.shared.gymEquipment == ["dumbbell", "band"])
            #expect(FiltersStore.shared.gymFixtures == ["pull-up bar"])
            #expect(TrainingProfileStore.shared.profile.goal == .hypertrophy)
            #expect(PersistenceValidation.validate(TrainingRecordsStore.shared.data).isEmpty)
        }
    }

    @Test func theVaultWritesVerifiedBackupsAndRestoresWithAnUndo() async throws {
        try await IsolatedStores.run {
            let vault = BackupVault.shared
            try await IsolatedStores.finishWorkout()
            let first = try #require(vault.backUp(reason: .manual))
            #expect(first.counts?.sessions == 1)
            #expect(vault.lastSuccessAt == first.createdAt)

            // More training after that backup…
            try await IsolatedStores.finishWorkout(exercise: "dumbbell curl")
            #expect(TrainingRecordsStore.shared.data.sessions.count == 2)
            let after = TrainingRecordsStore.shared.data

            // …then the older backup is restored: one session again, and a copy
            // of the two-session state is kept to undo with.
            let json = try String(contentsOf: first.url, encoding: .utf8)
            try vault.restore(json, sourceName: first.url.lastPathComponent)
            #expect(TrainingRecordsStore.shared.data.sessions.count == 1)
            #expect(vault.undoableRestore != nil)
            #expect(vault.interruptedRestore == nil)

            try vault.undoLastRestore()
            #expect(TrainingRecordsStore.shared.data == after)
            #expect(vault.undoableRestore == nil, "An undo is spent once used")
        }
    }

    @Test func theVaultKeepsOnlyTheNewestBackupsAndNeverTheirTemporaryFiles() async throws {
        try await IsolatedStores.run {
            let vault = BackupVault.shared
            let folder = BackupVault.folder
            for index in 0..<(BackupVault.keep + 3) {
                let createdAt = ISOTime.addDays("2026-10-01T10:00:00.000Z", Double(index))
                _ = try BackupVault.write(
                    AppBackup.createBackup(createdAt: createdAt, includeLocalTraining: true),
                    createdAt: createdAt, reason: .automatic, to: folder
                )
            }
            try Data("half written".utf8).write(to: folder.appending(path: ".dat.nosync1234.tmp"))
            BackupVault.prune(folder)
            vault.refresh()
            #expect(vault.generations.count == BackupVault.keep)
            #expect(vault.generations.first?.createdAt == ISOTime.addDays("2026-10-01T10:00:00.000Z", Double(BackupVault.keep + 2)))
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path())
                .filter { $0.hasSuffix(".tmp") }
            #expect(leftovers.isEmpty)
        }
    }

    // MARK: Damaged and older files

    @Test func aDamagedBackupIsRefusedBeforeAnythingChanges() async throws {
        try await IsolatedStores.run {
            try await IsolatedStores.finishWorkout()
            let json = AppBackup.createBackup(includeLocalTraining: true)
            let before = TrainingRecordsStore.shared.data
            // One digit changed inside the data: the checksum no longer matches.
            let tampered = json.replacingOccurrences(of: "\"reps\":8", with: "\"reps\":9")
            #expect(tampered != json)
            #expect(throws: BackupArchiveError.damaged) { try BackupArchive.inspect(tampered) }
            #expect(throws: (any Error).self) { try AppBackup.importBackup(tampered) }
            #expect(TrainingRecordsStore.shared.data == before)

            #expect(throws: BackupArchiveError.notABackup) { try BackupArchive.inspect("{\"hello\":1}") }
            #expect(throws: BackupArchiveError.notABackup) { try BackupArchive.inspect("not json at all") }
            #expect(throws: BackupArchiveError.unsupportedVersion) {
                try BackupArchive.inspect("{\"app\":\"RAUTA\",\"version\":7,\"data\":{}}")
            }
        }
    }

    @Test func invalidTrainingRecordsAreRefusedWholeEvenWithoutAChecksum() async throws {
        try await IsolatedStores.run {
            let json = """
            {"app":"RAUTA","version":1,"createdAt":"2026-10-01T10:00:00.000Z",
             "data":{"training":{"schemaVersion":99,"sessions":"nonsense"}}}
            """
            #expect(throws: BackupArchiveError.invalidTraining) { try BackupArchive.inspect(json) }
        }
    }

    /// A backup from before training records, fixtures or a profile existed
    /// restores what it has and leaves the rest as this device has it.
    @Test func anOlderBackupKeepsWhatItDoesNotMention() async throws {
        try await IsolatedStores.run {
            try await IsolatedStores.finishWorkout()
            FiltersStore.shared.setGymEquipment(["kettlebell"])
            FiltersStore.shared.setGymFixtures(["bench"])
            let sessions = TrainingRecordsStore.shared.data.sessions

            let legacy = """
            {"app":"Gym Lib","version":1,"createdAt":"2025-01-01T10:00:00.000Z",
             "data":{"favorites":{"favoriteIds":["0662"]},
                     "filters":{"selectedMuscles":[],"equipmentPresets":[]},
                     "settings":{},
                     "workouts":{"workouts":[{"id":"old-1","name":"Old","date":"2025-01-01","exerciseIds":["0662"]}]}}}
            """
            let preview = try BackupArchive.inspect(legacy)
            #expect(!preview.hasTraining)
            #expect(!preview.checksumVerified)
            #expect(preview.warnings.count >= 3)

            try AppBackup.importBackup(legacy)
            #expect(TrainingRecordsStore.shared.data.sessions == sessions, "Training history stays")
            #expect(FiltersStore.shared.gymEquipment == ["kettlebell"])
            #expect(FiltersStore.shared.gymFixtures == ["bench"])
            #expect(WorkoutsStore.shared.workout("old-1") != nil)
            #expect(FavoritesStore.shared.favoriteIds == ["0662"])
        }
    }

    // MARK: Interrupted restores

    @Test func aRestoreCutShortCanBeFinishedOrPutBack() async throws {
        try await IsolatedStores.run {
            let vault = BackupVault.shared
            try await IsolatedStores.finishWorkout()
            let backup = try #require(vault.backUp(reason: .manual))
            try await IsolatedStores.finishWorkout(exercise: "dumbbell curl")
            let current = TrainingRecordsStore.shared.data
            let safety = try #require(vault.backUp(reason: .beforeRestore))

            // The marker a restore writes first, as if the app died after it.
            let marker = InterruptedRestore(
                startedAt: ISOTime.now(),
                sourceFile: backup.url.lastPathComponent,
                safetyFile: safety.url.lastPathComponent
            )
            try JSONEncoder().encode(marker).write(to: BackupVault.folder.appending(path: ".restore-in-progress.json"))
            vault.refresh()
            #expect(vault.interruptedRestore == marker)

            try vault.resolveInterruptedRestore(finish: false)
            #expect(TrainingRecordsStore.shared.data == current)
            #expect(vault.interruptedRestore == nil)

            try JSONEncoder().encode(marker).write(to: BackupVault.folder.appending(path: ".restore-in-progress.json"))
            vault.refresh()
            try vault.resolveInterruptedRestore(finish: true)
            #expect(TrainingRecordsStore.shared.data.sessions.count == 1)
        }
    }

    @Test func aRestoreWaitsForTheWorkoutInProgress() async throws {
        try await IsolatedStores.run {
            let backup = AppBackup.createBackup(includeLocalTraining: true)
            let bench = try #require(ExerciseResolver.resolve("barbell bench press").first?.exercise.id)
            let id = try await EngineWorkout.createWorkout(date: CalendarDate.today, exerciseIds: [bench])
            #expect(ActiveWorkoutStore.shared.start(try #require(WorkoutsStore.shared.workout(id))).refusal == nil)
            #expect(throws: (any Error).self) { try BackupVault.shared.restore(backup, sourceName: "x.json") }
            #expect(ActiveWorkoutStore.shared.session?.workoutId == id)
        }
    }

    // MARK: Two devices

    @Test func workoutListsFromTwoDevicesMergeWithoutLosingEither() {
        func workout(_ id: String, updatedAt: String, name: String = "W") -> Workout {
            Workout(id: id, name: name, date: "2026-10-12", exerciseIds: [], completion: nil,
                    createdAt: "2026-10-01T10:00:00.000Z", updatedAt: updatedAt, planned: nil)
        }
        let local = WorkoutsStore.PersistedWorkouts(
            workouts: [
                workout("shared", updatedAt: "2026-10-05T10:00:00.000Z", name: "Local edit"),
                workout("only-here", updatedAt: "2026-10-06T10:00:00.000Z"),
                workout("deleted-there", updatedAt: "2026-10-02T10:00:00.000Z"),
            ],
            deletions: ["gone-here": "2026-10-07T10:00:00.000Z"]
        )
        let remote = WorkoutsStore.PersistedWorkouts(
            workouts: [
                workout("shared", updatedAt: "2026-10-04T10:00:00.000Z", name: "Older remote edit"),
                workout("only-there", updatedAt: "2026-10-06T11:00:00.000Z"),
                workout("gone-here", updatedAt: "2026-10-03T10:00:00.000Z"),
            ],
            deletions: ["deleted-there": "2026-10-08T10:00:00.000Z"]
        )
        let merged = WorkoutsStore.merge(local: local, remote: remote)
        let byId = Dictionary(uniqueKeysWithValues: merged.workouts.map { ($0.id, $0) })
        #expect(byId["shared"]?.name == "Local edit", "The newer edit wins")
        #expect(byId["only-here"] != nil)
        #expect(byId["only-there"] != nil)
        #expect(byId["gone-here"] == nil, "Deleted here after its last edit stays deleted")
        #expect(byId["deleted-there"] == nil, "Deleted there after its last edit stays deleted")
        #expect(merged.deletions.keys.contains("gone-here"))
        #expect(merged.deletions.keys.contains("deleted-there"))
    }

    @Test func aWorkoutEditedAfterItsDeletionElsewhereComesBack() {
        let edited = Workout(id: "w", name: "Edited later", date: "2026-10-12", exerciseIds: [], completion: nil,
                             createdAt: "2026-10-01T10:00:00.000Z", updatedAt: "2026-10-09T10:00:00.000Z", planned: nil)
        let merged = WorkoutsStore.merge(
            local: .init(workouts: [edited], deletions: [:]),
            remote: .init(workouts: [], deletions: ["w": "2026-10-08T10:00:00.000Z"])
        )
        #expect(merged.workouts.map(\.id) == ["w"])
    }

    @Test func aCloudCopyMergesIntoTheListAndKeepsTheRunningWorkout() async throws {
        try await IsolatedStores.run {
            let bench = try #require(ExerciseResolver.resolve("barbell bench press").first?.exercise.id)
            let other = WorkoutsStore.shared.createWorkout(
                name: "From the iPad", date: CalendarDate.shift(CalendarDate.today, by: 2), exerciseIds: []
            )
            let cloudCopy = AppBackup.createBackup()
            WorkoutsStore.shared.replaceAll([])
            let mine = WorkoutsStore.shared.createWorkout(
                name: "Added here", date: CalendarDate.shift(CalendarDate.today, by: 3), exerciseIds: []
            )
            let running = try await EngineWorkout.createWorkout(date: CalendarDate.today, exerciseIds: [bench])
            #expect(ActiveWorkoutStore.shared.start(try #require(WorkoutsStore.shared.workout(running))).refusal == nil)
            let draft = TrainingRecordsStore.shared.data.activeWorkout

            try AppBackup.importBackup(cloudCopy, keepingRunningWorkout: true, mergingWorkouts: true)
            #expect(WorkoutsStore.shared.workout(other) != nil)
            #expect(WorkoutsStore.shared.workout(mine) != nil, "A workout added here survives an older copy")
            #expect(WorkoutsStore.shared.workout(running) != nil)
            #expect(ActiveWorkoutStore.shared.session?.workoutId == running)
            #expect(TrainingRecordsStore.shared.data.activeWorkout == draft)
        }
    }

    @Test func aFullBackupArrivingMidWorkoutNeverReplacesTheDraft() async throws {
        try await IsolatedStores.run {
            try await IsolatedStores.finishWorkout()
            let backup = AppBackup.createBackup(includeLocalTraining: true)
            let bench = try #require(ExerciseResolver.resolve("barbell bench press").first?.exercise.id)
            let running = try await EngineWorkout.createWorkout(date: CalendarDate.today, exerciseIds: [bench])
            #expect(ActiveWorkoutStore.shared.start(try #require(WorkoutsStore.shared.workout(running))).refusal == nil)
            let draft = try #require(TrainingRecordsStore.shared.data.activeWorkout)

            try AppBackup.importBackup(backup, keepingRunningWorkout: true, mergingWorkouts: true)
            #expect(TrainingRecordsStore.shared.data.activeWorkout == draft)
            #expect(ActiveWorkoutStore.shared.session?.workoutId == running)
        }
    }

    @Test func clearingRemembersEachDeletionSoOtherDevicesClearToo() async throws {
        try await IsolatedStores.run {
            let id = WorkoutsStore.shared.createWorkout(name: "W", date: CalendarDate.today, exerciseIds: [])
            let copy = WorkoutsStore.PersistedWorkouts(workouts: WorkoutsStore.shared.workouts, deletions: [:])
            WorkoutsStore.shared.clearAll()
            #expect(WorkoutsStore.shared.deletions[id] != nil)
            let merged = WorkoutsStore.merge(
                local: copy,
                remote: .init(workouts: [], deletions: WorkoutsStore.shared.deletions)
            )
            #expect(merged.workouts.isEmpty)
        }
    }

    /// The compact iCloud copy stays inside the key-value store's limit and
    /// never carries the training records; a complete backup always does.
    @Test func theCompactCopyLeavesTrainingOutAndTheCompleteOneNever() async throws {
        try await IsolatedStores.run {
            try await IsolatedStores.finishWorkout()
            let compact = AppBackup.createBackup()
            let complete = AppBackup.createBackup(includeLocalTraining: true)
            #expect(JSONCoding.parse(compact)?["data"]?["training"] == nil)
            #expect(JSONCoding.parse(complete)?["data"]?["training"] != nil)
            #expect(compact.lengthOfBytes(using: .utf8) < 900_000)
            #expect(try BackupArchive.inspect(compact).hasTraining == false)
        }
    }
}
