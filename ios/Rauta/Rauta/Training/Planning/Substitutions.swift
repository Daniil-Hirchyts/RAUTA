import Foundation

private nonisolated let SUBSTITUTION_SIMILARITY_WEIGHTS = SimilarityWeights(
    family: 0.2,
    patterns: 0.25,
    directMuscles: 0.25,
    mechanics: 0.1,
    tracking: 0.1,
    laterality: 0.05,
    equipment: 0.05
)

nonisolated enum Substitutions {
    struct Candidate {
        var exerciseId: String
        var score: Score
    }

    static func findExerciseSubstitutions(
        _ exerciseId: String,
        _ request: ProgramGenerationRequest,
        limit: Int = 10,
        index suppliedIndex: ExerciseIndex? = nil,
        selectedExerciseIds: [String]? = nil
    ) -> [Candidate] {
        let index = suppliedIndex ?? ExerciseData.createIndex(
            request.exercises,
            overrides: request.metadata ?? []
        )
        guard let source = index.byId[exerciseId] else { return [] }
        let policy = request.policy ?? DEFAULT_POLICY

        let focus = source.metadata.setRoles.filter { $0.role == .direct }.map(\.muscleId)
        let ranked = Ranking.rankExerciseCandidates(
            request,
            index: index,
            focus: focus,
            selectedExerciseIds: (selectedExerciseIds ?? []).filter { $0 != exerciseId }
        )
        var planningScores: [String: Double] = [:]
        for item in ranked { planningScores[item.exerciseId] = item.score.total }

        let sourceDirect = Set(
            source.metadata.setRoles.filter { $0.role == .direct }.map(\.muscleId)
        )

        let weights: [String: Double] = [
            "similarity": 4, "planning": 3, "tracking": 1,
            "skill": 0.5, "quality": 1, "preference": 0.5,
        ]

        return index.byId.values
            .filter { candidate in
                candidate.exercise.id != exerciseId
                    && planningScores[candidate.exercise.id] != nil
                    && candidate.metadata.setRoles.contains {
                        $0.role == .direct && sourceDirect.contains($0.muscleId)
                    }
                    && ExerciseData.exclusionReasons(
                        candidate, request.preferences, policy,
                        experience: request.profile.trainingExperience
                    ).isEmpty
            }
            .map { candidate -> Candidate in
                let preference: Double = {
                    if request.preferences.preferredExerciseIds?.contains(candidate.exercise.id) == true {
                        return 1
                    }
                    if request.preferences.dislikedExerciseIds?.contains(candidate.exercise.id) == true {
                        return 0
                    }
                    return 0.5
                }()
                return Candidate(
                    exerciseId: candidate.exercise.id,
                    score: Scoring.weightedScore(
                        [
                            ("planning", planningScores[candidate.exercise.id] ?? 0),
                            ("similarity", Scoring.exerciseSimilarity(
                                source, candidate, SUBSTITUTION_SIMILARITY_WEIGHTS
                            )),
                            ("tracking", candidate.metadata.tracking == source.metadata.tracking ? 1 : 0),
                            ("skill", candidate.metadata.skill == source.metadata.skill ? 1 : 0),
                            ("quality", candidate.metadata.classificationConfidence),
                            ("preference", preference),
                        ],
                        weights
                    )
                )
            }
            .sorted { left, right in
                if left.score.total != right.score.total { return left.score.total > right.score.total }
                return compareIds(left.exerciseId, right.exerciseId) < 0
            }
            .prefix(Swift.max(0, Swift.min(100, limit)))
            .map { $0 }
    }
}

/// Structural adapter for workouts recorded before structured set logging.
nonisolated enum LegacyWorkouts {
    struct LegacyCompletion {
        var startedAt: String
        var completedAt: String
        var durationMs: Double
        var completedExerciseIds: [String]
    }

    static func adapt(id: String, completion: LegacyCompletion?) -> CompletedSession? {
        guard let completion else { return nil }
        return CompletedSession(
            id: id,
            plannedSessionId: nil,
            startedAt: completion.startedAt,
            completedAt: completion.completedAt,
            durationSeconds: completion.durationMs / 1000,
            status: .completed,
            exercises: completion.completedExerciseIds.map {
                CompletedExercise(exerciseId: $0, sets: [])
            }
        )
    }
}
