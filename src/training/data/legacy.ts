import type { CompletedSession } from "../domain/types"
/** Structural adapter: deliberately no imports from stores, device APIs, or runtime persistence. */
export function adaptLegacyWorkout(workout: {
  id: string
  completion: null | {
    startedAt: string
    completedAt: string
    durationMs: number
    completedExerciseIds: string[]
  }
}): CompletedSession | undefined {
  const c = workout.completion
  return c
    ? {
        id: workout.id,
        startedAt: c.startedAt,
        completedAt: c.completedAt,
        durationSeconds: c.durationMs / 1000,
        status: "completed",
        exercises: c.completedExerciseIds.map((exerciseId) => ({
          exerciseId,
          sets: [],
        })),
      }
    : undefined
}
