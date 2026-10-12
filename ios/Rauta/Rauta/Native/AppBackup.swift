import Foundation

/// The portable snapshot of everything a person has told the app.
///
/// The shape is exactly what the web build wrote, so a backup taken on either
/// side restores on the other. A complete backup — the files `BackupVault`
/// keeps and a manual export — includes the structured training records and a
/// manifest with a checksum. The compact copy in iCloud key-value storage
/// leaves the training records out: they grow with every set and do not fit
/// its size limit.
@MainActor
enum AppBackup {
    static let version = BackupArchive.envelopeVersion

    static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    /// Everything a backup carries, read from the stores now.
    static func backupData(includeLocalTraining: Bool) -> [String: JSONValue] {
        let favorites = FavoritesStore.shared
        let filters = FiltersStore.shared
        let settings = SettingsStore.shared
        let workouts = WorkoutsStore.shared
        let trainingProfile = TrainingProfileStore.shared

        var data: [String: JSONValue] = [
            "favorites": .object([
                "favoriteIds": .array(favorites.favoriteIds.map(JSONValue.string)),
            ]),
            "filters": filters.snapshotTree,
            "trainingProfile": .object([
                "profile": trainingProfile.profile.jsonTree,
                "onboarding": trainingProfile.onboarding.jsonTree,
            ]),
            "settings": settings.preferences.jsonTree,
            "workouts": workouts.snapshotTree,
        ]
        if includeLocalTraining {
            data["training"] = TrainingRecordsStore.shared.data.jsonTree
        }
        return data
    }

    static func createBackup(
        createdAt: String = ISOTime.now(),
        includeLocalTraining: Bool = false
    ) -> String {
        BackupArchive.envelope(
            data: backupData(includeLocalTraining: includeLocalTraining),
            createdAt: createdAt,
            appVersion: appVersion,
            complete: includeLocalTraining
        ).canonical
    }

    /// Defaults do not need to win a first-run conflict over an existing cloud
    /// copy.
    static func hasMeaningfulData() -> Bool {
        let favorites = FavoritesStore.shared
        let filters = FiltersStore.shared
        let settings = SettingsStore.shared.preferences
        let workouts = WorkoutsStore.shared
        let training = TrainingRecordsStore.shared.data

        // Structured training is local-only, so a cloud copy says nothing about
        // it — but a device holding real sessions, a plan or a described station
        // is not a fresh install, whatever else is empty.
        return !training.sessions.isEmpty
            || !training.programs.isEmpty
            || !training.settings.loadConfigurations.isEmpty
            || !favorites.favoriteIds.isEmpty
            || !filters.gymEquipment.isEmpty
            || !filters.equipmentPresets.isEmpty
            || !filters.equipmentLoadIncrements.isEmpty
            || !workouts.workouts.isEmpty
            || TrainingProfileStore.shared.isConfigured
            || settings != SettingsPreferences.defaults
    }

    /// A complete backup as a file for the share sheet, checked by reading it
    /// back before it is handed over.
    static func exportFileURL() throws -> URL {
        let data = createBackup(includeLocalTraining: true)
        let filename = "rauta-backup-\(CalendarDate.today).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, atomically: true, encoding: .utf8)
        do {
            _ = try BackupArchive.inspect(String(contentsOf: url, encoding: .utf8))
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw TrainingPersistenceError("The backup file couldn't be written correctly. Try again.")
        }
        return url
    }

    /// Replaces the app's data with a backup's.
    ///
    /// The whole file is checked before anything is written — envelope,
    /// version, checksum and training records — so a file this device cannot
    /// make sense of leaves the app exactly as it was rather than half replaced.
    ///
    /// `keepingRunningWorkout` is for a copy arriving from iCloud — another
    /// device's edit — while a workout runs here. That workout is this device's
    /// alone: its session, its record in the workout list and its draft stay
    /// exactly as they are, so a change made on an iPad cannot end a workout in
    /// progress on the iPhone. `mergingWorkouts` merges the workout list with
    /// this device's instead of replacing it, so neither side's workouts are
    /// lost to the other's older copy. A file the person chose to restore
    /// replaces everything, as it says it will.
    static func importBackup(
        _ json: String,
        keepingRunningWorkout: Bool = false,
        mergingWorkouts: Bool = false
    ) throws {
        do {
            _ = try BackupArchive.inspect(json)
        } catch {
            throw TrainingPersistenceError(error.message)
        }
        guard let backup = JSONCoding.parse(json)?.objectValue,
              let data = backup["data"]?.objectValue
        else {
            throw TrainingPersistenceError("The backup does not contain app data.")
        }

        var training: PersistedTrainingState?
        if let raw = data["training"] {
            do {
                training = try PersistenceValidation.migrate(raw)
            } catch {
                throw TrainingPersistenceError("The backup contains invalid training records.")
            }
        }

        let favorites = FavoritesStore.sanitize(data["favorites"])
        let filters = FiltersStore.sanitize(data["filters"])
        let settings = SettingsStore.sanitize(data["settings"])
        let workouts = WorkoutsStore.sanitize(data["workouts"])

        let running = keepingRunningWorkout ? ActiveWorkoutStore.shared.session : nil
        if running == nil {
            ActiveWorkoutStore.shared.setSession(nil, outcome: .cancelled)
        }
        FavoritesStore.shared.replaceAll(favorites)

        // A backup written before a field existed says nothing about it, which
        // is not the same as saying it is empty. Anything the file does not
        // carry is left exactly as this device already has it.
        var mergedFilters = filters
        let filterFields = data["filters"]?.objectValue ?? [:]
        if filterFields["gymEquipment"] == nil {
            mergedFilters.gymEquipment = FiltersStore.shared.gymEquipment
        }
        if filterFields["equipmentLoadIncrements"] == nil {
            mergedFilters.equipmentLoadIncrements = FiltersStore.shared.equipmentLoadIncrements
        }
        if filterFields["gymFixtures"] == nil {
            mergedFilters.gymFixtures = FiltersStore.shared.gymFixtures
        }
        FiltersStore.shared.apply(mergedFilters)
        SettingsStore.shared.replaceAll(settings)
        if mergingWorkouts {
            let local = WorkoutsStore.PersistedWorkouts(
                workouts: WorkoutsStore.shared.workouts,
                deletions: WorkoutsStore.shared.deletions
            )
            WorkoutsStore.shared.replaceAll(
                WorkoutsStore.merge(local: local, remote: workouts, runningId: running?.workoutId)
            )
        } else {
            var next = workouts
            next.workouts = Self.keeping(running, in: workouts.workouts)
            WorkoutsStore.shared.replaceAll(next)
        }

        if data["trainingProfile"] != nil {
            TrainingProfileStore.shared.replaceAll(
                TrainingProfileStore.sanitizeState(data["trainingProfile"])
            )
        }
        if var training {
            if running != nil {
                // The draft being logged right now, and any transition it is
                // part of, are this device's: never another copy's.
                let local = TrainingRecordsStore.shared.data
                training.activeWorkout = local.activeWorkout
                training.transition = local.transition
            }
            TrainingRecordsStore.shared.replaceAll(training)
        }

        // A restored draft, or an intent caught mid-transition, has to be settled
        // before the app treats it as a running session. A workout kept running
        // was never restored, so there is nothing to settle.
        if running == nil {
            ActiveWorkoutStore.shared.reconcileRestored()
        }
    }

    /// The imported workout list, with the running workout's record as this
    /// device has it: in the imported one's place, or added if the other device
    /// no longer lists it.
    static func keeping(_ running: ActiveWorkoutSession?, in imported: [Workout]) -> [Workout] {
        guard let running, let local = WorkoutsStore.shared.workout(running.workoutId) else { return imported }
        guard let index = imported.firstIndex(where: { $0.id == local.id }) else { return imported + [local] }
        var kept = imported
        kept[index] = local
        return kept
    }

    static func clearAllData() {
        RautaAgent.shared.startOver()
        // The system's notifications and calendar are the person's own; a test
        // clearing its data must not reach them.
        if !AppEnvironment.isRunningTests {
            WorkoutReminders.shared.removeAll()
            CalendarService.shared.removeAllLinkedEvents()
        }
        RestAlerts.shared.cancel()
        WatchConnectivityService.shared.forgetProcessedActions()
        HealthService.shared.forgetWatchClaims()
        ActiveWorkoutStore.shared.setSession(nil, outcome: .cancelled)
        FavoritesStore.shared.replaceAll([])
        FiltersStore.shared.clearAll()
        WorkoutsStore.shared.clearAll()
        TrainingRecordsStore.shared.replaceAll(.empty())
        SettingsStore.shared.resetSettings()
        TrainingProfileStore.shared.resetTrainingProfile()
        Storage.remove(AppSessionStore.storageKey)
        // "Delete everything" includes the backups of it.
        if !AppEnvironment.isRunningTests { BackupVault.shared.deleteAllBackups() }
    }
}
