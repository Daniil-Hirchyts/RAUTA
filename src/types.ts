export const MUSCLE_IDS = [
  "trapezius",
  "deltoids",
  "chest",
  "upper-back",
  "serratus",
  "biceps",
  "triceps",
  "forearm",
  "abs",
  "obliques",
  "lower-back",
  "gluteal",
  "quadriceps",
  "hamstring",
  "adductors",
  "hip-flexors",
  "calves",
  "tibialis",
] as const

export type MuscleId = (typeof MUSCLE_IDS)[number]

export type ExerciseSummary = {
  id: string
  name: string
  equipment: string
  primaryMuscle: MuscleId | null
  muscles: MuscleId[]
}
