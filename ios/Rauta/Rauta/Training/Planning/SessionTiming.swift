import Foundation

enum SessionTiming {
    static func estimateSession(
        _ exercises: [PlannedExercise],
        _ index: ExerciseIndex,
        _ policy: TrainingPolicy
    ) -> SessionDurationEstimate {
        var specificWarmupSeconds = 0.0
        var workingSetSeconds = 0.0
        var restSeconds = 0.0
        var transitionSeconds = 0.0

        for planned in exercises {
            let metadata = index.byId[planned.exerciseId]?.metadata
            let sides: Double = (metadata?.laterality == .unilateral || metadata?.laterality == .alternating) ? 2 : 1
            for set in planned.warmupSets {
                let reps: Double = set.targetReps.max
                specificWarmupSeconds += reps * policy.secondsPerRep * sides + policy.warmupRestSeconds
            }
            for set in planned.workingSets {
                let reps: Double = set.targetReps.max
                workingSetSeconds += reps * policy.secondsPerRep * sides
            }
            let restingSets: Double = Swift.max(0, Double(planned.workingSets.count - 1))
            restSeconds += restingSets * planned.restSeconds
            transitionSeconds += metadata?.setupSeconds ?? 60
        }
        transitionSeconds += Swift.max(0, Double(exercises.count - 1)) * policy.transitionSeconds

        let generalWarmupSeconds = exercises.isEmpty ? 0 : policy.generalWarmupSeconds
        return SessionDurationEstimate(
            generalWarmupSeconds: generalWarmupSeconds,
            specificWarmupSeconds: specificWarmupSeconds,
            workingSetSeconds: workingSetSeconds,
            restSeconds: restSeconds,
            transitionSeconds: transitionSeconds,
            totalSeconds: generalWarmupSeconds + specificWarmupSeconds
                + workingSetSeconds + restSeconds + transitionSeconds,
            confidence: .low
        )
    }

}
