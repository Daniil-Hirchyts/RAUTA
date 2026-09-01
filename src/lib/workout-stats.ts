import { toISODate } from "@/lib/date"
import type { Workout } from "@/store/use-workouts"

/** Moderate-to-vigorous resistance training, expressed as a MET estimate. */
const STRENGTH_TRAINING_MET = 6
const FALLBACK_BODY_WEIGHT_KG = 75

/**
 * Standard MET energy estimate: MET × 3.5 × kilograms / 200 × minutes.
 * HealthKit weight is used when available; the conservative fallback keeps
 * history useful without pretending the number is a measurement.
 */
export function estimateStrengthCalories(
  durationMs: number,
  bodyWeightKg?: number | null
) {
  const minutes = Math.max(0, durationMs) / 60_000
  const kilograms =
    bodyWeightKg && bodyWeightKg >= 30 && bodyWeightKg <= 300
      ? bodyWeightKg
      : FALLBACK_BODY_WEIGHT_KG
  return Math.max(
    durationMs > 0 ? 1 : 0,
    Math.round((STRENGTH_TRAINING_MET * 3.5 * kilograms * minutes) / 200)
  )
}

export function isPastWorkout(workout: Workout, today = new Date()) {
  return workout.completion !== null || workout.date < toISODate(today)
}

export function isCompletedWorkout(workout: Workout) {
  return workout.completion !== null
}
