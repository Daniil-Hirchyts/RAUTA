import Foundation

/// Every lookup the planner needs over the catalogue, built once and shared.
nonisolated struct ExerciseIndex: Sendable {
    var byId: [String: IndexedExercise] = [:]
    var byMuscle: [MuscleId: [IndexedExercise]] = [:]
    var byDirectMuscle: [MuscleId: [IndexedExercise]] = [:]
    var byPrimaryMuscle: [MuscleId: [IndexedExercise]] = [:]
    var byEquipment: [String: [IndexedExercise]] = [:]
    var byMovementPattern: [MovementPattern: [IndexedExercise]] = [:]
    var byFamily: [String: [IndexedExercise]] = [:]
    var byAutomaticProgramming: [AutomaticProgramming: [IndexedExercise]] = [:]
    var byTracking: [TrackingMode: [IndexedExercise]] = [:]
    var byMechanics: [Mechanics: [IndexedExercise]] = [:]
    var byExerciseType: [ExerciseType: [IndexedExercise]] = [:]
    var issues: [PlanningIssue] = []
    var fingerprint: String = ""
}

nonisolated enum ExerciseData {
    static func validateExerciseData(_ exercises: [ExerciseSummary]) -> [PlanningIssue] {
        var ids = Set<String>()
        var issues: [PlanningIssue] = []
        for (index, exercise) in exercises.enumerated() {
            let invalid = ids.contains(exercise.id)
                || exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || exercise.id.isEmpty
                || exercise.equipment.isEmpty
                || exercise.muscles.count != exercise.muscleWeights.count
                || Set(exercise.muscles).count != exercise.muscles.count
                || exercise.muscleWeights.contains { !Num.isFinite($0, min: 0, max: 1) }
                || (exercise.primaryMuscle != nil && !exercise.muscles.contains(exercise.primaryMuscle!))
            ids.insert(exercise.id)
            if invalid {
                issues.append(PlanningIssue(
                    .invalidExerciseData,
                    path: "exercises.\(index)",
                    context: ["exerciseId": .string(exercise.id)]
                ))
            }
        }
        return issues
    }

    static func validateMetadata(_ metadata: ExerciseMetadata, _ exercise: ExerciseSummary?) -> [PlanningIssue] {
        guard let exercise else {
            return [PlanningIssue(.invalidExerciseData, context: ["metadata": .bool(true)])]
        }

        var valid = metadata.exerciseId == exercise.id
            && Num.isFinite(metadata.classificationConfidence, min: 0, max: 1)
            && Num.isFinite(metadata.setupSeconds, min: 0, max: 600)
            && (metadata.provenance != .rule || metadata.requiredEquipment.contains(exercise.equipment))
            && metadata.requiredEquipment.allSatisfy { !$0.isEmpty }
            && Set(metadata.setRoles.map(\.muscleId)).count == metadata.setRoles.count
            && !metadata.movementPatterns.isEmpty
            && metadata.movementPatterns.allSatisfy(ExerciseClassifier.validPatterns.contains)
            && !metadata.ruleVersion.isEmpty

        if let familyId = metadata.familyId, familyId.isEmpty { valid = false }
        if let variantOf = metadata.variantOf, variantOf.isEmpty || variantOf == metadata.exerciseId { valid = false }
        if let duplicateOf = metadata.duplicateOf, duplicateOf.isEmpty || duplicateOf == metadata.exerciseId {
            valid = false
        }
        if metadata.automaticProgramming == .allowed && !plannerSupportsExercise(metadata) { valid = false }
        if metadata.exerciseType == .resistance && metadata.automaticProgramming != .manualOnly {
            let hasDirect = metadata.setRoles.contains { $0.role == .direct }
            if !hasDirect || metadata.movementPatterns.contains(.unknown) || metadata.mechanics == .unknown {
                valid = false
            }
        }

        return valid ? [] : [PlanningIssue(.invalidExerciseData, context: ["metadata": .bool(true)])]
    }

    static func createIndex(
        _ exercises: [ExerciseSummary],
        overrides: [ExerciseMetadata] = []
    ) -> ExerciseIndex {
        var index = ExerciseIndex()
        index.issues = validateExerciseData(exercises)
        if !index.issues.isEmpty { return index }

        var metadataOverrides: [String: ExerciseMetadata] = [:]
        for override in overrides {
            index.issues += validateMetadata(
                override,
                exercises.first { $0.id == override.exerciseId }
            )
            if metadataOverrides[override.exerciseId] != nil {
                index.issues.append(PlanningIssue(
                    .invalidExerciseData,
                    context: ["duplicateMetadata": .string(override.exerciseId)]
                ))
            }
            metadataOverrides[override.exerciseId] = override
        }
        if !index.issues.isEmpty { return index }

        let exerciseIds = Set(exercises.map(\.id))
        var effectiveMetadata: [String: ExerciseMetadata] = [:]
        for exercise in exercises {
            let explicit = metadataOverrides[exercise.id]
            var metadata = explicit ?? CuratedExercises.resolveMetadata(exercise)
            // Built-in catalogue relationships may point outside a caller-supplied
            // subset. Keep the local index self-contained while requiring explicit
            // overrides to be valid.
            if explicit == nil {
                if let variantOf = metadata.variantOf, !exerciseIds.contains(variantOf) { metadata.variantOf = nil }
                if let duplicateOf = metadata.duplicateOf, !exerciseIds.contains(duplicateOf) {
                    metadata.duplicateOf = nil
                }
            }
            index.issues += validateMetadata(metadata, exercise)
            effectiveMetadata[exercise.id] = metadata
        }
        if !index.issues.isEmpty { return index }

        for metadata in effectiveMetadata.values {
            for relationship in [metadata.variantOf, metadata.duplicateOf] {
                if let relationship, !exerciseIds.contains(relationship) {
                    index.issues.append(PlanningIssue(
                        .invalidExerciseData,
                        context: [
                            "exerciseId": .string(metadata.exerciseId),
                            "invalidRelationship": .string(relationship),
                        ]
                    ))
                }
            }
        }

        if let cycle = relationshipCycle(exerciseIds, effectiveMetadata) {
            index.issues.append(PlanningIssue(
                .invalidExerciseData,
                context: ["relationshipCycle": .strings(cycle)]
            ))
        }
        if !index.issues.isEmpty { return index }

        for source in exercises.sorted(by: { compareIds($0.id, $1.id) < 0 }) {
            guard let metadata = effectiveMetadata[source.id] else { continue }
            let item = IndexedExercise(
                exercise: source,
                metadata: metadata,
                participation: source.muscles.enumerated().map { index, muscleId in
                    MuscleParticipation(
                        muscleId: muscleId,
                        relativeInvolvement: source.muscleWeights[index]
                    )
                }
            )
            index.byId[source.id] = item
            for role in metadata.setRoles {
                if role.role != .incidental { index.byMuscle[role.muscleId, default: []].append(item) }
                if role.role == .direct { index.byDirectMuscle[role.muscleId, default: []].append(item) }
            }
            if let primary = source.primaryMuscle {
                index.byPrimaryMuscle[primary, default: []].append(item)
            }
            for equipment in metadata.requiredEquipment {
                index.byEquipment[equipment, default: []].append(item)
            }
            for pattern in metadata.movementPatterns {
                index.byMovementPattern[pattern, default: []].append(item)
            }
            if let familyId = metadata.familyId {
                index.byFamily[familyId, default: []].append(item)
            }
            index.byAutomaticProgramming[metadata.automaticProgramming, default: []].append(item)
            index.byTracking[metadata.tracking, default: []].append(item)
            index.byMechanics[metadata.mechanics, default: []].append(item)
            index.byExerciseType[metadata.exerciseType, default: []].append(item)
        }

        let ordered = exercises
            .sorted { compareIds($0.id, $1.id) < 0 }
            .compactMap { index.byId[$0.id] }
        index.fingerprint = fingerprint(.array(ordered.map { item in
            .object([
                "exercise": item.exercise.jsonTree,
                "metadata": item.metadata.jsonTree,
                "participation": .array(item.participation.map { $0.jsonTree }),
            ])
        }))
        return index
    }

    private static func relationshipCycle(
        _ exerciseIds: Set<String>,
        _ metadata: [String: ExerciseMetadata]
    ) -> [String]? {
        enum VisitState { case visiting, visited }
        var state: [String: VisitState] = [:]
        var stack: [String] = []
        var cycle: [String]?

        func visit(_ exerciseId: String) -> Bool {
            if state[exerciseId] == .visiting {
                if let start = stack.firstIndex(of: exerciseId) {
                    cycle = Array(stack[start...]) + [exerciseId]
                }
                return true
            }
            if state[exerciseId] == .visited { return false }
            state[exerciseId] = .visiting
            stack.append(exerciseId)
            let current = metadata[exerciseId]
            for target in [current?.variantOf, current?.duplicateOf] {
                if let target, visit(target) { return true }
            }
            stack.removeLast()
            state[exerciseId] = .visited
            return false
        }

        for exerciseId in exerciseIds.sorted(by: { compareIds($0, $1) < 0 }) {
            if visit(exerciseId) { break }
        }
        return cycle
    }

    static func exclusionReasons(
        _ item: IndexedExercise,
        _ preferences: PlanningPreferences,
        _ policy: TrainingPolicy
    ) -> [PlanningIssue] {
        let context: [String: IssueContextValue] = ["exerciseId": .string(item.exercise.id)]
        var issues: [PlanningIssue] = []

        if preferences.excludedExerciseIds?.contains(item.exercise.id) == true {
            issues.append(PlanningIssue(.excludedExercise, context: context))
        }

        let missing = item.metadata.requiredEquipment.filter {
            $0 != "body weight" && !preferences.availableEquipment.contains($0)
        }
        if !missing.isEmpty {
            var withMissing = context
            withMissing["missing"] = .strings(missing)
            issues.append(PlanningIssue(.unavailableEquipment, context: withMissing))
        }

        let explicitlyRequested = preferences.preferredExerciseIds?.contains(item.exercise.id) == true
            || preferences.strengthExerciseIds?.contains(item.exercise.id) == true
        let automaticProgrammingBlocked = item.metadata.automaticProgramming == .manualOnly
            || (item.metadata.automaticProgramming == .specializedOnly && !explicitlyRequested)
        let minimumConfidence = item.metadata.automaticProgramming == .specializedOnly
            ? policy.minimumSpecializedClassificationConfidence
            : policy.minimumAutomaticClassificationConfidence
        let lowConfidenceRule = item.metadata.provenance == .rule
            && item.metadata.classificationConfidence < minimumConfidence
        let excludedPattern = item.metadata.movementPatterns.contains {
            preferences.excludedPatterns?.contains($0) == true
        }

        if item.metadata.exerciseType != .resistance
            || !plannerSupportsTracking(item.metadata.tracking)
            || automaticProgrammingBlocked
            || lowConfidenceRule
            || excludedPattern {
            issues.append(PlanningIssue(.unsupportedExercise, context: context))
        }

        return issues
    }
}
