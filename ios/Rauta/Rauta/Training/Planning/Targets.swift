import Foundation

nonisolated let MAJOR_MUSCLES: [MuscleId] = [
    .chest, .upperBack, .deltoids, .biceps, .triceps,
    .quadriceps, .gluteal, .hamstring, .calves, .abs,
]

nonisolated extension TrainingGoal {
    /// Power falls back to the general-fitness prescription; the policy has no
    /// dedicated entry for it.
    var policyKey: TrainingGoal { self == .power ? .generalFitness : self }
}

nonisolated enum Targets {
    static func deriveProgramTargets(
        _ request: ProgramGenerationRequest,
        _ state: DerivedTrainingState,
        _ policy: TrainingPolicy
    ) -> [MuscleTarget] {
        let goal = policy.goal(request.preferences.goal.policyKey)

        return MuscleId.allCases.map { muscleId in
            let level = request.preferences.priorityMuscles?
                .first { $0.muscleId == muscleId }?.level ?? .normal
            let importance = policy.priorityMultiplier(level)
            let targeted = MAJOR_MUSCLES.contains(muscleId)
                || level == .high
                || level == .specialization

            var preferred: Double = targeted
                ? (request.profile.trainingExperience == .beginner
                    ? Swift.min(policy.beginnerPreferredSets, goal.volume.preferred)
                    : goal.volume.preferred) * importance
                : 0

            if let muscleState = state.muscles[muscleId],
               preferred > 0,
               muscleState.confidence.atLeast(.medium),
               muscleState.recentSessionCount >= Double(policy.historyMinSessions) {
                let recent = muscleState.rolling28DaySets / 4
                preferred = Swift.min(preferred, recent + policy.maxWeeklyVolumeIncrease)
            }

            if let setCompletion = state.adherence.setCompletion,
               setCompletion < policy.adherenceReductionThreshold {
                preferred *= 1 - policy.reductionFraction
            }

            if request.readiness?.perceivedReadiness == .low,
               state.exercises.values.filter({ $0.trend == .declining }).count >= 2 {
                preferred *= 1 - policy.reductionFraction
            }

            let upperGuideline = goal.volume.upperGuideline
            preferred = Num.clamp(preferred, 0, upperGuideline).rounded()

            let preferredExposures: Double = {
                guard preferred > 0 else { return 0 }
                let floorExposures: Double = (request.preferences.goal == .strength
                    || request.preferences.goal == .strengthHypertrophy) ? 2 : 1
                return Swift.min(
                    Double(request.schedule.days.count),
                    Swift.max(floorExposures, (preferred / policy.sessionMuscleGuideline).rounded(.up))
                )
            }()

            return MuscleTarget(
                muscleId: muscleId,
                minimum: targeted ? Swift.min(goal.volume.minimum, preferred) : 0,
                preferred: preferred,
                upperGuideline: upperGuideline,
                importance: targeted ? importance : 0.25,
                preferredExposures: preferredExposures
            )
        }
    }
}
