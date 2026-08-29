import generatedExercises from "@/data/exercises.generated.json"
import type { ExerciseSummary, MuscleId } from "@/types"

export const EXERCISES = generatedExercises as ExerciseSummary[]

export const EQUIPMENT_OPTIONS = [
  ...new Set(EXERCISES.map((exercise) => exercise.equipment)),
].sort((left, right) => left.localeCompare(right))

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
