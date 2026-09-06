import type { ExerciseMetadata } from "./types"

export const PLANNER_SUPPORTED_TRACKING = [
  "external_load",
  "assistance",
  "bodyweight",
  "band_resistance",
] as const satisfies readonly ExerciseMetadata["tracking"][]

export function plannerSupportsTracking(
  tracking: ExerciseMetadata["tracking"]
): boolean {
  return PLANNER_SUPPORTED_TRACKING.includes(
    tracking as (typeof PLANNER_SUPPORTED_TRACKING)[number]
  )
}

export function plannerSupportsExercise(metadata: ExerciseMetadata): boolean {
  return (
    metadata.exerciseType === "resistance" &&
    plannerSupportsTracking(metadata.tracking)
  )
}
