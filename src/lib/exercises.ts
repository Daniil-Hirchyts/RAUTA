import generatedExercises from "@/data/exercises.generated.json"
import type { ExerciseSummary, MuscleId } from "@/types"

export const EXERCISES = generatedExercises as ExerciseSummary[]

export const EXERCISES_BY_ID = new Map(
  EXERCISES.map((exercise) => [exercise.id, exercise])
)

export const EQUIPMENT_OPTIONS = [
  ...new Set(EXERCISES.map((exercise) => exercise.equipment)),
].sort((left, right) => left.localeCompare(right))

export function orderedMuscles(exercise: ExerciseSummary) {
  const muscles: MuscleId[] = []
  if (exercise.primaryMuscle) muscles.push(exercise.primaryMuscle)
  exercise.muscles.forEach((muscle) => {
    if (!muscles.includes(muscle)) muscles.push(muscle)
  })
  return muscles
}

export function filterExercises(
  exercises: ExerciseSummary[],
  selectedMuscles: MuscleId[],
  selectedEquipment: string[]
) {
  if (selectedMuscles.length === 0 || selectedEquipment.length === 0) return []

  const muscles = new Set(selectedMuscles)
  const equipment = new Set(selectedEquipment)

  return exercises.filter(
    (exercise) =>
      equipment.has(exercise.equipment) &&
      exercise.muscles.some((muscle) => muscles.has(muscle))
  )
}
