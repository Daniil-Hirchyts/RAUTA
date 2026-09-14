import Foundation

enum Prescribe {
    static func exercise(
        _ item: IndexedExercise,
        count: Int,
        sessionId: String,
        rationale: Score,
        input: OptimizationInput
    ) -> PlannedExercise {
        let request = input.request
        let policy = input.policy
        let id = item.exercise.id
        let goal = policy.goal(request.preferences.goal.policyKey)
        let compound = item.metadata.mechanics == .compound
        let heavySupported = item.metadata.tracking == .externalLoad
        let reps = compound && heavySupported ? goal.compoundReps : goal.isolationReps
        let rir = request.profile.trainingExperience == .beginner
            ? Swift.max(policy.beginnerRir, goal.rir)
            : goal.rir

        let progression = Progression.recommend(ProgressionInput(
            exercise: item,
            history: request.history,
            now: request.now,
            reps: reps,
            rir: rir,
            requiredSets: Swift.min(count, policy.progressionEvidenceSets),
            loadGrid: request.preferences.loadGrids?[id],
            loadContext: request.preferences.loadContexts?[id],
            policy: policy
        ))

        let loadAcquisition: LoadAcquisition = {
            switch progression.resistance.type {
            case .bodyweight: return .bodyweight
            case .bandResistance: return .bandResistance
            case .unknown: return .calibrateByRir
            default: return .history
            }
        }()

        let workingSets: [PlannedSet] = (0..<Swift.max(0, count)).map { index in
            PlannedSet(
                id: "\(sessionId)/\(id)/work/\(index)",
                setType: .working,
                targetReps: progression.targetReps,
                targetRir: rir,
                resistance: progression.resistance,
                loadAcquisition: loadAcquisition
            )
        }

        var warmupSets: [PlannedSet] = []
        if compound && heavySupported {
            let count = reps.max <= policy.heavyWarmupMaxReps ? 2 : 1
            let fractions = Array(policy.warmupFractions.prefix(count))
            let grid = request.preferences.loadGrids?[id]
            for (index, fraction) in fractions.enumerated() {
                let load = progression.resistance
                var kg: Double?
                if load.type == .externalLoad, let grid, let loadKg = load.kg {
                    kg = Progression.roundLoad(loadKg * fraction, grid, .down)
                }
                var resistance = ResistanceValue.unknown
                if load.type == .externalLoad, let kg {
                    resistance = load
                    resistance.kg = kg
                }
                let warmupReps = index < policy.warmupReps.count ? policy.warmupReps[index] : 5
                warmupSets.append(PlannedSet(
                    id: "\(sessionId)/\(id)/warm/\(index)",
                    setType: .warmup,
                    targetReps: RepRange(min: warmupReps, max: warmupReps),
                    targetRir: 5,
                    resistance: resistance,
                    loadAcquisition: kg == nil ? .calibrateByRir : .history
                ))
            }
        }

        return PlannedExercise(
            exerciseId: id,
            order: 0,
            workingSets: workingSets,
            warmupSets: warmupSets,
            restSeconds: restSeconds(item, goal: goal),
            targetMuscles: item.metadata.setRoles.filter { $0.role == .direct }.map(\.muscleId),
            rationale: rationale,
            progression: progression
        )
    }

    /// Rest between sets: a compound lift gets the goal's longer rest.
    static func restSeconds(_ item: IndexedExercise, goal: GoalPolicy) -> Double {
        item.metadata.mechanics == .compound ? goal.compoundRest : goal.isolationRest
    }
}

enum Ranking {
    struct Candidate: Sendable {
        var exerciseId: String
        var score: Score
    }

    /// The planner's candidate scoring, also used when a person builds a session.
    static func rankExerciseCandidates(
        _ request: ProgramGenerationRequest,
        index: ExerciseIndex? = nil,
        focus: [MuscleId] = [],
        selectedExerciseIds: [String] = []
    ) -> [Candidate] {
        let input = Generate.preparation(request, previousProgram: nil, index: index)
        let selected = Set(selectedExerciseIds)

        let sessionFocus = focus.isEmpty
            ? input.targets.filter { $0.preferred > 0 }.map(\.muscleId)
            : focus

        let session = PlannedSession(
            id: "selection",
            scheduledAt: request.now,
            focus: sessionFocus,
            exercises: selectedExerciseIds.compactMap { id -> PlannedExercise? in
                guard let exercise = input.index.byId[id] else { return nil }
                return Prescribe.exercise(
                    exercise,
                    count: 3,
                    sessionId: "selection",
                    rationale: .zero,
                    input: input
                )
            },
            duration: SessionTiming.estimateSession([], input.index, input.policy)
        )

        let week = TrainingWeek(
            id: "selection",
            start: request.schedule.weekStart,
            phase: .base,
            sessions: [session],
            targets: input.targets
        )
        let score = Scoring.createExerciseScorer(session, week, input)

        return input.index.byId.values
            .filter { candidate in
                !selected.contains(candidate.exercise.id)
                    && ExerciseData.exclusionReasons(candidate, request.preferences, input.policy).isEmpty
            }
            .map { Candidate(exerciseId: $0.exercise.id, score: score($0)) }
            .sorted { left, right in
                if left.score.total != right.score.total { return left.score.total > right.score.total }
                return compareIds(left.exerciseId, right.exerciseId) < 0
            }
    }
}
