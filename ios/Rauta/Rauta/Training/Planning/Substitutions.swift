import Foundation

private let SUBSTITUTION_SIMILARITY_WEIGHTS = SimilarityWeights(
    family: 0.2,
    patterns: 0.25,
    directMuscles: 0.25,
    mechanics: 0.1,
    tracking: 0.1,
    laterality: 0.05,
    equipment: 0.05
)

enum Substitutions {
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
                    && ExerciseData.exclusionReasons(candidate, request.preferences, policy).isEmpty
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

enum ProgramSummary {
    struct ExerciseLine {
        var id: String
        var name: String?
        var sets: Int
        var reps: RepRange?
        var rir: Double?
        var resistance: ResistanceValue?
    }

    struct SessionLine {
        var id: String
        var scheduledAt: String
        var minutes: Int
        var exercises: [ExerciseLine]
    }

    struct WeekLine {
        var weekId: String
        var phase: TrainingWeek.Phase
        var minutes: Int
        var sessions: [SessionLine]
        var volume: MuscleVolumeMap
        var frequency: [MuscleId: Double]
    }

    struct Summary {
        var id: String
        var goal: TrainingGoal
        var split: String
        var score: Double
        var weeks: [WeekLine]
    }

    static func summarize(_ program: TrainingProgram, _ index: ExerciseIndex) -> Summary {
        let volume = Volume.programVolume(program, index)
        let frequency = Volume.programFrequency(program, index)
        let duration = SessionTiming.estimateProgram(program, index)

        return Summary(
            id: program.id,
            goal: program.goal,
            split: program.diagnostics.selectedSplit,
            score: program.diagnostics.score.total,
            weeks: program.weeks.enumerated().map { weekIndex, week in
                WeekLine(
                    weekId: week.id,
                    phase: week.phase,
                    minutes: Int((duration[weekIndex].seconds / 60).rounded()),
                    sessions: week.sessions.map { session in
                        SessionLine(
                            id: session.id,
                            scheduledAt: session.scheduledAt,
                            minutes: Int((session.duration.totalSeconds / 60).rounded()),
                            exercises: session.exercises.map { exercise in
                                ExerciseLine(
                                    id: exercise.exerciseId,
                                    name: index.byId[exercise.exerciseId]?.exercise.name,
                                    sets: exercise.workingSets.count,
                                    reps: exercise.workingSets.first?.targetReps,
                                    rir: exercise.workingSets.first?.targetRir,
                                    resistance: exercise.workingSets.first?.resistance
                                )
                            }
                        )
                    },
                    volume: volume[weekIndex].muscles,
                    frequency: frequency[weekIndex].muscles
                )
            }
        )
    }
}

/// Structural adapter for workouts recorded before structured set logging.
enum LegacyWorkouts {
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
