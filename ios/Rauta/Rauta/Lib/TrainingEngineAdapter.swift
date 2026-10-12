import Foundation

/// The one boundary between RAUTA and the deterministic training engine.
///
/// Everything above it is application state a person edits — a profile, an
/// equipment selection, an Apple Health reading. Everything below it is the
/// engine's canonical request vocabulary. The dependency only ever points this
/// way: nothing in the engine knows this file exists.
@MainActor
enum TrainingEngineAdapter {
    /// What an exercise is lifted with (its resistance: dumbbell, cable, body
    /// weight) and what has to be there to perform it (a bar to hang from, a
    /// bench to lie on) are separate questions. The profile asks both: which
    /// equipment you train with, and which fixtures you have.
    ///
    /// Gym equipment grants the fixtures it cannot be used without — a cable
    /// stack its attachments, a barbell its rack and bench. Equipment people
    /// keep at home grants only household things (a chair, a wall, a step):
    /// owning dumbbells says nothing about owning a bench. Accessories nobody
    /// can assume — a pull-up bar, rings, a partner — are never implied, so an
    /// exercise that needs one stays out of a plan until the person says they
    /// have it.
    static let impliedAccessories: [String: [String]] = [
        "assisted": ["dip station", "pull-up bar", "band anchor", "towel"],
        "band": ["band anchor", "chair", "step"],
        "barbell": ["bench", "rack", "step"],
        "body weight": ["chair", "wall", "step", "towel", "support"],
        "bosu ball": ["chair"],
        "cable": [
            "bench", "rope attachment", "straight-bar attachment",
            "v-bar attachment", "arm blaster",
        ],
        "dumbbell": ["step", "arm blaster", "support"],
        "ez barbell": ["bench", "arm blaster"],
        "kettlebell": ["step"],
        "leverage machine": [
            "bench", "dip station", "pull-up bar", "step", "v-bar attachment", "glute-ham bench",
        ],
        "medicine ball": ["wall"],
        "olympic barbell": ["bench", "rack"],
        "resistance band": ["band anchor", "chair"],
        "rope": ["step", "wall"],
        "sled machine": ["step"],
        "smith machine": ["bench", "rack", "step"],
        "stability ball": ["wall"],
        "trap bar": ["rack"],
        "weighted": ["bench", "pull-up bar", "dip station", "step", "wall"],
    ]

    /// The fixtures a person can say they have, in the order they are offered.
    static let selectableFixtures: [String] = [
        "pull-up bar", "dip station", "bench", "rack", "low bar", "suspension trainer",
    ]

    /// Other names the catalogue uses for a selectable fixture.
    static let fixtureAliases: [String: [String]] = [
        "dip station": ["dip bars"],
    ]

    static func fixtureLabel(_ fixture: String) -> String {
        switch fixture {
        case "pull-up bar": return "Pull-up bar"
        case "dip station": return "Dip bars"
        case "bench": return "Bench"
        case "rack": return "Squat rack"
        case "low bar": return "Low bar for rows"
        case "suspension trainer": return "Suspension trainer"
        case "glute-ham bench": return "Glute-ham bench"
        case "slide board": return "Slide board"
        case "balance board": return "Balance board"
        case "band anchor": return "Band anchor"
        default: return Wording.titleCase(fixture)
        }
    }

    /// Fixtures this equipment granted before fixtures could be chosen. A
    /// profile saved then keeps planning exactly as it did until the person
    /// picks fixtures themselves.
    static func legacyFixtures(for equipment: [String]) -> [String] {
        let previous: [String: [String]] = [
            "band": ["bench"], "dumbbell": ["bench"], "kettlebell": ["bench"],
            "medicine ball": ["bench"], "resistance band": ["bench"],
            "stability ball": ["bench", "dip station"],
        ]
        var result: [String] = []
        for item in equipment {
            for fixture in previous[item] ?? [] where !result.contains(fixture) {
                result.append(fixture)
            }
        }
        return selectableFixtures.filter(result.contains)
    }

    /// Things a person could add to train more, the most practical for a
    /// beginner first, each with everything it brings along.
    static var unlockCandidates: [(name: String, provides: Set<String>)] {
        let fixtures: Set<String> = Set(selectableFixtures)
        let preferred = [
            "resistance band", "band", "dumbbell", "kettlebell", "pull-up bar", "low bar",
            "dip station", "bench", "suspension trainer", "medicine ball", "stability ball",
        ]
        let rest = ExerciseCatalogue.equipmentOptions.filter { !preferred.contains($0) && $0 != implicitEquipment }
        return (preferred + rest).map { name in
            let provides = fixtures.contains(name)
                ? toEngineEquipment([], fixtures: [name])
                : toEngineEquipment([name])
            return (name, Set(provides))
        }
    }

    /// Nobody has to own their own body, and the engine already treats body
    /// weight as always available.
    static let implicitEquipment = "body weight"

    /// The profile stores what a session should aim for; the engine also wants
    /// the ceiling it must not cross. A little slack keeps a plan feasible when
    /// the conservative duration estimate lands just over the target.
    static let sessionDurationHeadroomMinutes: Double = 10

    /// Application equipment ids, plus the fixtures they stand on and the
    /// fixtures the person said they have.
    static func toEngineEquipment(_ equipment: [String], fixtures: [String] = []) -> [String] {
        // Body weight is always there, and with it the room around it.
        let selection = [implicitEquipment] + equipment
        var seen = Set<String>()
        var result: [String] = []
        func add(_ value: String) {
            if seen.insert(value).inserted { result.append(value) }
        }
        for item in selection {
            for value in [item] + (impliedAccessories[item] ?? []) { add(value) }
        }
        for fixture in fixtures {
            add(fixture)
            for alias in fixtureAliases[fixture] ?? [] { add(alias) }
        }
        // An implied fixture brings its other names along too.
        for (fixture, aliases) in fixtureAliases where seen.contains(fixture) {
            for alias in aliases { add(alias) }
        }
        return result
    }

    /// What an exercise needs that this equipment and these fixtures do not
    /// provide. Empty when it can be performed. The engine's own eligibility
    /// check reads the same requirement; this is the same answer for a screen.
    static func missingRequirements(
        _ exerciseId: String,
        equipment: [String],
        fixtures: [String]
    ) -> [String] {
        guard let item = TrainingWorkflow.trainingIndex().byId[exerciseId] else { return [] }
        let available = Set(toEngineEquipment(equipment, fixtures: fixtures))
        return item.metadata.requiredEquipment.filter {
            $0 != implicitEquipment && !available.contains($0)
        }
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
        /// A session length to plan for instead of the profile's, for a plan
        /// shown before the profile is changed to match it.
        var sessionMinutes: Double?
        /// Equipment and fixtures to plan around instead of the saved ones —
        /// "the bench is taken this week" — without changing the profile.
        var equipment: [String]?
        var fixtures: [String]?

        init(
            goal: TrainingGoal? = nil,
            availableEquipment: [String]? = nil,
            preferredExerciseIds: [String]? = nil,
            dislikedExerciseIds: [String]? = nil,
            excludedExerciseIds: [String]? = nil,
            strengthExerciseIds: [String]? = nil,
            sessionMinutes: Double? = nil,
            equipment: [String]? = nil,
            fixtures: [String]? = nil
        ) {
            self.goal = goal
            self.availableEquipment = availableEquipment
            self.preferredExerciseIds = preferredExerciseIds
            self.dislikedExerciseIds = dislikedExerciseIds
            self.excludedExerciseIds = excludedExerciseIds
            self.strengthExerciseIds = strengthExerciseIds
            self.sessionMinutes = sessionMinutes
            self.equipment = equipment
            self.fixtures = fixtures
        }
    }

    static func buildPlanningPreferences(
        _ profile: TrainingProfile,
        equipment: [String],
        fixtures: [String] = [],
        overrides: PreferenceOverrides = PreferenceOverrides(),
        configurations: [PersistedLoadConfiguration] = [],
        equipmentLoadIncrements: [String: Double] = [:]
    ) -> PlanningPreferences {
        let preferred = overrides.sessionMinutes ?? profile.preferredSessionDurationMinutes
        let equipment = overrides.equipment ?? equipment
        let loads = buildLoadPreferences(
            equipment: equipment,
            configurations: configurations,
            equipmentLoadIncrements: equipmentLoadIncrements
        )
        return PlanningPreferences(
            goal: overrides.goal ?? profile.goal,
            availableEquipment: overrides.availableEquipment
                ?? toEngineEquipment(equipment, fixtures: overrides.fixtures ?? fixtures),
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
                fixtures: filters.effectiveFixtures,
                overrides: overrides,
                configurations: loadConfigurations,
                equipmentLoadIncrements: filters.equipmentLoadIncrements
            )
        )
    }
}
