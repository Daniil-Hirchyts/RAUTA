import type {
  IndexedExercise,
  OptimizationInput,
  PlannedExercise,
  PlannedSet,
  Score,
} from "../domain/types"
import { recommendProgression, roundLoad } from "../progression/progression"
export function prescribeExercise(
  e: IndexedExercise,
  count: number,
  sessionId: string,
  rationale: Score,
  input: OptimizationInput
): PlannedExercise {
  const { request, policy } = input
  const id = e.exercise.id
  const goal =
    policy.goals[
      request.preferences.goal === "power"
        ? "general_fitness"
        : request.preferences.goal
    ]
  const compound = e.metadata.mechanics === "compound"
  const heavySupported = e.metadata.tracking === "external_load"
  const reps =
    compound && heavySupported ? goal.compoundReps : goal.isolationReps
  const rir =
    request.profile.trainingExperience === "beginner"
      ? Math.max(policy.beginnerRir, goal.rir)
      : goal.rir
  const progression = recommendProgression({
    exercise: e,
    history: request.history,
    now: request.now,
    reps,
    rir,
    requiredSets: Math.min(count, policy.progressionEvidenceSets),
    loadContext: request.preferences.loadContexts?.[id],
    loadGrid: request.preferences.loadGrids?.[id],
    policy,
  })
  const workingSets: PlannedSet[] = Array.from({ length: count }, (_, i) => ({
    id: `${sessionId}/${id}/work/${i}`,
    setType: "working",
    targetReps: { ...progression.targetReps },
    targetRir: rir,
    resistance: { ...progression.resistance },
    loadAcquisition:
      progression.resistance.type === "bodyweight"
        ? "bodyweight"
        : progression.resistance.type === "unknown"
          ? "calibrate_by_rir"
          : "history",
    side: "both",
  }))
  const warmupSets: PlannedSet[] = compound
    ? policy.warmupFractions
        .slice(0, reps.max <= policy.heavyWarmupMaxReps ? 2 : 1)
        .map((fraction, i) => {
          const load = progression.resistance
          const grid = request.preferences.loadGrids?.[id]
          const kg =
            load.type === "external_load" && grid
              ? roundLoad(load.kg * fraction, grid, "down")
              : undefined
          return {
            id: `${sessionId}/${id}/warm/${i}`,
            setType: "warmup",
            targetReps: {
              min: policy.warmupReps[i],
              max: policy.warmupReps[i],
            },
            targetRir: 5,
            resistance:
              load.type === "external_load" && kg !== undefined
                ? { ...load, kg }
                : { type: "unknown" },
            loadAcquisition: kg === undefined ? "calibrate_by_rir" : "history",
            side: "both",
          }
        })
    : []
  return {
    exerciseId: id,
    order: 0,
    workingSets,
    warmupSets,
    restSeconds: compound ? goal.compoundRest : goal.isolationRest,
    targetMuscles: e.metadata.setRoles
      .filter((r) => r.role === "direct")
      .map((r) => r.muscleId),
    rationale,
    progression,
  }
}
