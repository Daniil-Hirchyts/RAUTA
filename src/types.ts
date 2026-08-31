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
  // Muscles ordered strongest-involvement first, with `muscleWeights[i]`
  // holding how much of the exercise's effort lands on `muscles[i]`
  // (1 = the muscle the movement is built around).
  muscles: MuscleId[]
  muscleWeights: number[]
  instructions: string[]
}
