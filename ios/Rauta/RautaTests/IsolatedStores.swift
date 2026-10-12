import Foundation
import Testing
@testable import Rauta

/// Runs a test against stores of its own — defaults, files and backups in a
/// throwaway folder — and puts every store back as it was afterwards, a
/// workout running on the simulator included. Nothing a test writes reaches
/// the app's real data.
@MainActor
enum IsolatedStores {
    static func run(_ body: () async throws -> Void) async throws {
        let suite = "rauta-isolated-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)

        let previousDefaults = Storage.defaults
        let records = TrainingRecordsStore.shared.data
        let workouts = WorkoutsStore.PersistedWorkouts(
            workouts: WorkoutsStore.shared.workouts, deletions: WorkoutsStore.shared.deletions
        )
        let settings = SettingsStore.shared.preferences
        let filters = FiltersStore.shared.snapshot
        let favorites = FavoritesStore.shared.favoriteIds
        let profile = TrainingProfileStore.PersistedProfileState(
            profile: TrainingProfileStore.shared.profile,
            onboarding: TrainingProfileStore.shared.onboarding
        )
        let running = ActiveWorkoutStore.shared.session

        Storage.defaults = defaults
        Storage.directoryOverride = directory.appending(path: "Stores")
        BackupVault.folderOverride = directory.appending(path: "Backups")
        BackupVault.cloudFolderOverride = nil
        if running != nil { ActiveWorkoutStore.shared.setSession(nil, outcome: nil) }

        defer {
            if ActiveWorkoutStore.shared.session != nil {
                ActiveWorkoutStore.shared.setSession(nil, outcome: .cancelled)
            }
            TrainingRecordsStore.shared.replaceAll(records)
            WorkoutsStore.shared.replaceAll(workouts)
            SettingsStore.shared.replaceAll(settings)
            FiltersStore.shared.apply(filters)
            FavoritesStore.shared.replaceAll(favorites)
            TrainingProfileStore.shared.replaceAll(profile)
            Storage.defaults = previousDefaults
            Storage.directoryOverride = nil
            BackupVault.folderOverride = nil
            BackupVault.cloudFolderOverride = nil
            BackupVault.shared.refresh()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
            if let running { ActiveWorkoutStore.shared.setSession(running, outcome: nil) }
        }

        TrainingRecordsStore.shared.replaceAll(.empty())
        WorkoutsStore.shared.replaceAll(WorkoutsStore.PersistedWorkouts(workouts: [], deletions: [:]))
        FavoritesStore.shared.replaceAll([])
        FiltersStore.shared.clearAll()
        TrainingProfileStore.shared.resetTrainingProfile()
        SettingsStore.shared.update { $0.warmupSeconds = 0 }
        BackupVault.shared.refresh()
        try await body()
    }

    /// One finished workout with one logged working set, through the same
    /// start → log → finish path the app uses.
    @discardableResult
    static func finishWorkout(
        exercise phrase: String = "barbell bench press",
        date: String = CalendarDate.today,
        reps: Double = 8,
        rir: Double? = 2
    ) async throws -> String {
        let exercise = try #require(ExerciseResolver.resolve(phrase).first?.exercise.id)
        let id = try await EngineWorkout.createWorkout(date: date, exerciseIds: [exercise])
        let workout = try #require(WorkoutsStore.shared.workout(id))
        #expect(ActiveWorkoutStore.shared.start(workout).refusal == nil)
        let records = TrainingRecordsStore.shared
        let entry = try #require(records.data.activeWorkout?.exercises.first)
        let set = try #require(entry.sets.first { $0.setType == .working } ?? entry.sets.first)
        try records.recordSet(
            exerciseEntryId: entry.id,
            setDraftId: set.id,
            observation: PersistedSetObservation(
                reps: reps, resistance: set.target?.resistance ?? .bodyweight,
                rir: rir, completed: true, timestamp: ISOTime.now()
            )
        )
        guard case .saved = ActiveWorkoutStore.shared.finish() else {
            Issue.record("The workout did not finish")
            return id
        }
        return id
    }
}
