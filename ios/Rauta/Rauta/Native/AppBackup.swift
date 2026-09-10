import Foundation

/// The portable snapshot of everything a person has told the app.
///
/// The shape is exactly what the web build wrote, so a backup taken on either
/// side restores on the other. Structured training records are local-only and
/// travel with a manual export, not with the compact iCloud snapshot.
@MainActor
enum AppBackup {
    static let version = 1

    static func createBackup(
        createdAt: String = ISOTime.now(),
        includeLocalTraining: Bool = false
    ) -> String {
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
            "workouts": .object([
                "workouts": .array(workouts.workouts.map { $0.jsonTree }),
            ]),
        ]
        if includeLocalTraining {
            data["training"] = TrainingRecordsStore.shared.data.jsonTree
        }

        return JSONValue.object([
            "app": .string("RAUTA"),
            "createdAt": .string(createdAt),
            "version": .number(Double(version)),
            "data": .object(data),
        ]).canonical
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
            || !filters.selectedMuscles.isEmpty
            || !filters.selectedEquipment.isEmpty
            || !filters.gymEquipment.isEmpty
            || !filters.equipmentPresets.isEmpty
            || !filters.equipmentLoadIncrements.isEmpty
            || !workouts.workouts.isEmpty
            || TrainingProfileStore.shared.isConfigured
            || settings != SettingsPreferences.defaults
    }

    static func exportFileURL() throws -> URL {
        // Manual exports include local training; the existing iCloud snapshot
        // stays unchanged.
        let data = createBackup(includeLocalTraining: true)
        let filename = "rauta-backup-\(CalendarDate.today).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func importBackup(_ json: String) throws {
        guard let parsed = JSONCoding.parse(json), let backup = parsed.objectValue else {
            throw TrainingPersistenceError("This is not a supported RAUTA backup.")
        }
        let app = backup["app"]?.stringValue
        guard app == "RAUTA" || app == "Gym Lib",
              Int(backup["version"]?.numberValue ?? -1) == version
        else {
            throw TrainingPersistenceError("This is not a supported RAUTA backup.")
        }
        guard let data = backup["data"]?.objectValue else {
            throw TrainingPersistenceError("The backup does not contain app data.")
        }

        // Training records are read before anything is written: a file this
        // device cannot make sense of leaves the app exactly as it was rather
        // than half replaced.
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

        ActiveWorkoutStore.shared.setSession(nil, outcome: .cancelled)
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
        FiltersStore.shared.apply(mergedFilters)
        SettingsStore.shared.replaceAll(settings)
        WorkoutsStore.shared.replaceAll(workouts.workouts)

        if data["trainingProfile"] != nil {
            TrainingProfileStore.shared.replaceAll(
                TrainingProfileStore.sanitizeState(data["trainingProfile"])
            )
        }
        if let training { TrainingRecordsStore.shared.replaceAll(training) }

        // A restored draft, or an intent caught mid-transition, has to be settled
        // before the app treats it as a running session.
        ActiveWorkoutStore.shared.reconcileRestored()
    }

    static func clearAllData() {
        ActiveWorkoutStore.shared.setSession(nil, outcome: .cancelled)
        FavoritesStore.shared.replaceAll([])
        FiltersStore.shared.clearAll()
        WorkoutsStore.shared.replaceAll([])
        TrainingRecordsStore.shared.replaceAll(.empty())
        SettingsStore.shared.resetSettings()
        TrainingProfileStore.shared.resetTrainingProfile()
        Storage.remove(AppSessionStore.storageKey)
    }
}
