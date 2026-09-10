import Foundation

/// The one boundary between RAUTA and the deterministic training engine.
///
/// Everything above it is application state a person edits — a profile, an
/// equipment selection, an Apple Health reading. Everything below it is the
/// engine's canonical request vocabulary. The dependency only ever points this
/// way: nothing in the engine knows this file exists.
@MainActor
enum TrainingEngineAdapter {
    /// Catalogue accessories are the fixtures equipment stands on rather than
    /// things worth asking about. The profile keeps asking one question — which
    /// equipment do you have — and the adapter grants the fixtures that
    /// equipment implies.
    ///
    /// Accessories nobody can assume — a pull-up bar for someone training with
    /// body weight alone, rings, a partner — are deliberately absent, so those
    /// exercises stay out of an automatic plan rather than being prescribed to a
    /// room that cannot run them.
    static let impliedAccessories: [String: [String]] = [
        "assisted": ["dip station", "pull-up bar", "band anchor", "towel"],
        "band": ["band anchor", "bench", "chair", "step"],
        "barbell": ["bench", "rack", "step"],
        "body weight": ["chair", "wall", "step", "towel", "support"],
        "bosu ball": ["chair"],
        "cable": [
            "bench", "rope attachment", "straight-bar attachment",
            "v-bar attachment", "arm blaster",
        ],
        "dumbbell": ["bench", "step", "arm blaster", "support"],
        "ez barbell": ["bench", "arm blaster"],
        "kettlebell": ["bench", "step"],
        "leverage machine": ["bench", "dip station", "pull-up bar", "step", "v-bar attachment"],
        "medicine ball": ["bench", "wall"],
        "olympic barbell": ["bench", "rack"],
        "resistance band": ["band anchor", "bench", "chair"],
        "rope": ["step", "wall"],
        "sled machine": ["step"],
        "smith machine": ["bench", "rack", "step"],
        "stability ball": ["bench", "wall", "dip station"],
        "trap bar": ["rack"],
        "weighted": ["bench", "pull-up bar", "dip station", "step", "wall"],
    ]

    /// Nobody has to own their own body, and the engine already treats body
    /// weight as always available.
    static let implicitEquipment = "body weight"

    /// The profile stores what a session should aim for; the engine also wants
    /// the ceiling it must not cross. A little slack keeps a plan feasible when
    /// the conservative duration estimate lands just over the target.
    static let sessionDurationHeadroomMinutes: Double = 10

    /// Application equipment ids, plus the fixtures they stand on.
    static func toEngineEquipment(_ equipment: [String]) -> [String] {
        let selection = equipment.isEmpty ? [implicitEquipment] : equipment
        var seen = Set<String>()
        var result: [String] = []
        for item in selection {
            for value in [item] + (impliedAccessories[item] ?? []) where seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }

    struct LoadPreferences {
        var loadContexts: [String: LoadContext]
        var loadGrids: [String: LoadGrid]
    }

    /// What a kilogram means on each piece of equipment the person can reach.
    ///
    /// Availability decides which exercises are feasible; this decides how the
    /// load on them is measured. The engine compares kilograms only within one
    /// station and one basis, so a prescription of 30 kg for a dumbbell press
    /// has to be per-implement and a barbell press has to be total.
    static func buildLoadPreferences(
        equipment: [String],
        configurations: [PersistedLoadConfiguration] = [],
        equipmentLoadIncrements: [String: Double] = [:]
    ) -> LoadPreferences {
        let available = Set(toEngineEquipment(equipment))
        var loadContexts: [String: LoadContext] = [:]
        var loadGrids: [String: LoadGrid] = [:]

        for exercise in ExerciseCatalogue.all {
            guard available.contains(exercise.equipment) else { continue }
            // The shape the exercise is naturally logged in. Body weight and
            // band resistance carry no kilogram claim, so they get no station.
            guard let mode = Resistance.modes(for: exercise).first,
                  mode == .externalLoad || mode == .assistance
            else { continue }
            let saved = configurations.first { $0.exerciseId == exercise.id }
            let context = Resistance.loadContext(
                for: exercise,
                mode: mode,
                configuration: saved,
                equipmentIncrementKg: equipmentLoadIncrements[exercise.equipment]
            )
            loadContexts[exercise.id] = LoadContext(
                stationId: context.stationId, basis: context.basis
            )
            loadGrids[exercise.id] = context.grid
        }
        return LoadPreferences(loadContexts: loadContexts, loadGrids: loadGrids)
    }

    static func buildEngineProfile(
        _ profile: TrainingProfile,
        bodyWeightKg: Double? = nil
    ) -> UserTrainingProfile {
        UserTrainingProfile(
            age: profile.age,
            // Apple Health is the only source of body weight the app has, and it
            // is optional in both directions: absent here means the engine
            // estimates.
            bodyWeightKg: bodyWeightKg,
            heightCm: nil,
            trainingAgeMonths: nil,
            trainingExperience: profile.trainingExperience,
            health: profile.health
        )
    }

    struct PreferenceOverrides {
        var goal: TrainingGoal?
        var availableEquipment: [String]?
        var preferredExerciseIds: [String]?
        var dislikedExerciseIds: [String]?
        var excludedExerciseIds: [String]?
        var strengthExerciseIds: [String]?

        init(
            goal: TrainingGoal? = nil,
            availableEquipment: [String]? = nil,
            preferredExerciseIds: [String]? = nil,
            dislikedExerciseIds: [String]? = nil,
            excludedExerciseIds: [String]? = nil,
            strengthExerciseIds: [String]? = nil
        ) {
            self.goal = goal
            self.availableEquipment = availableEquipment
            self.preferredExerciseIds = preferredExerciseIds
            self.dislikedExerciseIds = dislikedExerciseIds
            self.excludedExerciseIds = excludedExerciseIds
            self.strengthExerciseIds = strengthExerciseIds
        }
    }

    static func buildPlanningPreferences(
        _ profile: TrainingProfile,
        equipment: [String],
        overrides: PreferenceOverrides = PreferenceOverrides(),
        configurations: [PersistedLoadConfiguration] = [],
        equipmentLoadIncrements: [String: Double] = [:]
    ) -> PlanningPreferences {
        let preferred = profile.preferredSessionDurationMinutes
        let loads = buildLoadPreferences(
            equipment: equipment,
            configurations: configurations,
            equipmentLoadIncrements: equipmentLoadIncrements
        )
        return PlanningPreferences(
            goal: overrides.goal ?? profile.goal,
            availableEquipment: overrides.availableEquipment ?? toEngineEquipment(equipment),
            preferredExerciseIds: overrides.preferredExerciseIds,
            dislikedExerciseIds: overrides.dislikedExerciseIds,
            excludedExerciseIds: overrides.excludedExerciseIds,
            excludedPatterns: nil,
            strengthExerciseIds: overrides.strengthExerciseIds,
            priorityMuscles: profile.priorityMuscles.isEmpty
                ? nil
                : profile.priorityMuscles.map {
                    MusclePriorityPreference(muscleId: $0.muscleId, level: $0.level)
                },
            preferredSessionDurationMinutes: preferred,
            maxSessionDurationMinutes: preferred + sessionDurationHeadroomMinutes,
            maxWeeklyWorkingSets: nil,
            muscleVolumeBounds: nil,
            loadGrids: loads.loadGrids,
            loadContexts: loads.loadContexts
        )
    }

    struct PlanSetup {
        var profile: UserTrainingProfile
        var preferences: PlanningPreferences
    }

    /// The saved profile as engine input. Reading the stores happens here and
    /// only here, so a planning caller never has to know which store holds what.
    static func buildEngineInputs(
        overrides: PreferenceOverrides = PreferenceOverrides()
    ) -> PlanSetup {
        let profile = TrainingProfileStore.shared.profile
        let settings = SettingsStore.shared
        let filters = FiltersStore.shared
        let loadConfigurations = TrainingRecordsStore.shared.data.settings.loadConfigurations

        return PlanSetup(
            profile: buildEngineProfile(
                profile,
                bodyWeightKg: settings.appleHealthEnabled ? settings.healthBodyWeightKg : nil
            ),
            preferences: buildPlanningPreferences(
                profile,
                equipment: filters.gymEquipment,
                overrides: overrides,
                configurations: loadConfigurations,
                equipmentLoadIncrements: filters.equipmentLoadIncrements
            )
        )
    }
}
