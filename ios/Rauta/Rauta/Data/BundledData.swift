import Foundation

/// The datasets that ship inside the app: the exercise catalogue, the anatomy
/// map outlines and the curated training metadata.
nonisolated enum BundledData {
    static func data(_ name: String, extension ext: String = "json") -> Data? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    static func json(_ name: String) -> JSONValue? {
        guard let data = data(name),
              let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        return JSONValue.from(any)
    }

    static func decode<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let data = data(name) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// The exercise catalogue plus the derived lookups the whole app browses by.
nonisolated enum ExerciseCatalogue {
    /// Any grid or list can realistically be asked to show hundreds at once, so
    /// every such list renders in bounded batches of this size.
    static let pageSize = 40

    static let all: [ExerciseSummary] = {
        BundledData.decode("exercises.generated", as: [ExerciseSummary].self) ?? []
    }()

    /// The catalogue in the order people read it. Sorted once: a locale-aware
    /// sort of the whole catalogue is too slow to repeat per query.
    static let allByName: [ExerciseSummary] = {
        all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    static let byId: [String: ExerciseSummary] = {
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }()

    static func exercise(_ id: String) -> ExerciseSummary? { byId[id] }
    static func has(_ id: String) -> Bool { byId[id] != nil }
    static func name(_ id: String) -> String? { byId[id]?.name }

    /// A deliberately editorial popularity order for a general gym audience.
    /// Product logic, not analytics: common, versatile equipment appears first
    /// and specialist or cardio accessories progressively follow.
    static let equipmentPopularity = [
        "body weight", "dumbbell", "barbell", "cable", "kettlebell",
        "resistance band", "band", "smith machine", "leverage machine",
        "assisted", "stability ball", "medicine ball", "ez barbell",
        "olympic barbell", "weighted", "rope", "sled machine", "stationary bike",
        "elliptical machine", "stepmill machine", "skierg machine", "trap bar",
        "bosu ball", "roller", "wheel roller", "tire", "hammer",
        "upper body ergometer",
    ]

    static let equipmentOptions: [String] = {
        var available = Set(all.map(\.equipment))
        var ordered: [String] = []
        for equipment in equipmentPopularity where available.remove(equipment) != nil {
            ordered.append(equipment)
        }
        return ordered + available.sorted { $0.localizedCompare($1) == .orderedAscending }
    }()

    private static let equipmentRank: [String: Int] = {
        Dictionary(uniqueKeysWithValues: equipmentPopularity.enumerated().map { ($1, $0) })
    }()

    static func equipmentForMuscles(_ muscles: [MuscleId], in exercises: [ExerciseSummary] = all) -> [String] {
        guard !muscles.isEmpty else { return equipmentOptions }
        let muscleSet = Set(muscles)
        var used = Set<String>()
        for exercise in exercises where exercise.muscles.contains(where: muscleSet.contains) {
            used.insert(exercise.equipment)
        }
        return equipmentOptions.filter(used.contains)
    }

    static func musclesForExerciseIds(_ ids: [String]) -> [MuscleId] {
        var muscles: [MuscleId] = []
        for id in ids {
            guard let exercise = byId[id] else { continue }
            for muscle in exercise.muscles where !muscles.contains(muscle) {
                muscles.append(muscle)
            }
        }
        return muscles
    }

    // MARK: Relevance

    private static let stretchPattern = Pattern(#"\bstretch(es|ing)?\b"#, caseInsensitive: true)
    private static let stretchPenalty = 0.75
    private static let equipmentSpread = 0.1
    private static let minFocus = 0.5

    private static func presentationQuality(_ exercise: ExerciseSummary) -> Double {
        let rank = Double(equipmentRank[exercise.equipment] ?? equipmentRank.count)
        let familiarity = 1 - rank / Double(equipmentRank.count)
        let penalty = stretchPattern.test(exercise.name) ? stretchPenalty : 1
        return (1 - equipmentSpread + equipmentSpread * familiarity) * penalty
    }

    /// How well an exercise answers a muscle selection, as the product of reach
    /// (how much of the picked muscles it trains) and focus (how much of the
    /// exercise lands on them rather than elsewhere).
    static func relevance(_ exercise: ExerciseSummary, _ selectedMuscles: Set<MuscleId>) -> Double {
        var reach = 0.0
        var effort = 0.0
        for (index, weight) in exercise.muscleWeights.enumerated() {
            effort += weight
            if index < exercise.muscles.count, selectedMuscles.contains(exercise.muscles[index]) {
                reach += weight
            }
        }
        guard reach > 0, effort > 0 else { return 0 }
        return reach * (minFocus + (1 - minFocus) * (reach / effort)) * presentationQuality(exercise)
    }

    private static let focusedRelevance = 0.5

    static func filter(
        _ exercises: [ExerciseSummary] = allByName,
        muscles selectedMuscles: [MuscleId],
        equipment selectedEquipment: [String]
    ) -> [ExerciseSummary] {
        guard !selectedMuscles.isEmpty, !selectedEquipment.isEmpty else { return [] }
        let muscles = Set(selectedMuscles)
        let equipment = Set(selectedEquipment)

        // Scored once each, then ordered by score with the name order as the tie
        // break — the input's own order, so no string comparison in the sort.
        var scored: [(exercise: ExerciseSummary, score: Double, order: Int)] = []
        for (order, exercise) in exercises.enumerated() where equipment.contains(exercise.equipment) {
            let score = relevance(exercise, muscles)
            if score > 0 { scored.append((exercise, score, order)) }
        }
        scored.sort { left, right in
            left.score != right.score ? left.score > right.score : left.order < right.order
        }
        return scored.map(\.exercise)
    }

    static func findAlternatives(
        to source: ExerciseSummary,
        excluding excludedIds: [String] = []
    ) -> [ExerciseSummary] {
        var excluded = Set(excludedIds)
        excluded.insert(source.id)
        let sourceMuscles = Set(source.muscles)

        func weightDifference(_ exercise: ExerciseSummary) -> Double {
            source.muscles.enumerated().reduce(0.0) { total, entry in
                let (index, muscle) = entry
                let alternativeIndex = exercise.muscles.firstIndex(of: muscle)
                let alternativeWeight = alternativeIndex.map { exercise.muscleWeights[$0] } ?? 0
                return total + abs(source.muscleWeights[index] - alternativeWeight)
            }
        }

        return all
            .filter { exercise in
                !excluded.contains(exercise.id)
                    && exercise.equipment != source.equipment
                    && exercise.muscles.count == source.muscles.count
                    && exercise.muscles.allSatisfy(sourceMuscles.contains)
            }
            .sorted { left, right in
                let leftPrimary = left.primaryMuscle != source.primaryMuscle ? 1 : 0
                let rightPrimary = right.primaryMuscle != source.primaryMuscle ? 1 : 0
                if leftPrimary != rightPrimary { return leftPrimary < rightPrimary }
                let leftWeight = weightDifference(left)
                let rightWeight = weightDifference(right)
                if leftWeight != rightWeight { return leftWeight < rightWeight }
                return left.name.localizedCompare(right.name) == .orderedAscending
            }
    }
}
