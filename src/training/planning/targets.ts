import { MUSCLE_IDS } from "../../types"
import type {
  DerivedTrainingState,
  MuscleId,
  MuscleTarget,
  ProgramGenerationRequest,
  TrainingPolicy,
} from "../domain/types"
import { clamp } from "../numeric"
export const MAJOR_MUSCLES: MuscleId[] = [
  "chest",
  "upper-back",
  "deltoids",
  "biceps",
  "triceps",
  "quadriceps",
  "gluteal",
  "hamstring",
  "calves",
  "abs",
]
export function deriveProgramTargets(
  request: ProgramGenerationRequest,
  state: DerivedTrainingState,
  policy: TrainingPolicy
): MuscleTarget[] {
  const goal =
    policy.goals[
      request.preferences.goal === "power"
        ? "general_fitness"
        : request.preferences.goal
    ]
  return MUSCLE_IDS.map((muscleId) => {
    const level =
      request.preferences.priorityMuscles?.find((p) => p.muscleId === muscleId)
        ?.level ?? "normal"
    const importance = policy.priorityMultipliers[level]
    const targeted =
      MAJOR_MUSCLES.includes(muscleId) ||
      level === "high" ||
      level === "specialization"
    let preferred = targeted
      ? (request.profile.trainingExperience === "beginner"
          ? Math.min(policy.beginnerPreferredSets, goal.volume.preferred)
          : goal.volume.preferred) * importance
      : 0
    const muscleState = state.muscles[muscleId]
    if (
      preferred &&
      muscleState.confidence === "medium" &&
      muscleState.recentSessionCount >= policy.historyMinSessions
    ) {
      const recent = muscleState.rolling28DaySets / 4
      preferred = Math.min(preferred, recent + policy.maxWeeklyVolumeIncrease)
    }
    if (
      state.adherence.setCompletion !== undefined &&
      state.adherence.setCompletion < policy.adherenceReductionThreshold
    )
      preferred *= 1 - policy.reductionFraction
    if (
      request.readiness?.perceivedReadiness === "low" &&
      Object.values(state.exercises).filter((e) => e.trend === "declining")
        .length >= 2
    )
      preferred *= 1 - policy.reductionFraction
    const upperGuideline = targeted
      ? goal.volume.upperGuideline
      : goal.volume.upperGuideline
    preferred = Math.round(clamp(preferred, 0, upperGuideline))
    return {
      muscleId,
      minimum: targeted ? Math.min(goal.volume.minimum, preferred) : 0,
      preferred,
      upperGuideline,
      importance: targeted ? importance : 0.25,
      preferredExposures: preferred
        ? Math.min(
            request.schedule.days.length,
            Math.max(
              request.preferences.goal === "strength" ||
                request.preferences.goal === "strength_hypertrophy"
                ? 2
                : 1,
              Math.ceil(preferred / policy.sessionMuscleGuideline)
            )
          )
        : 0,
    }
  })
}
