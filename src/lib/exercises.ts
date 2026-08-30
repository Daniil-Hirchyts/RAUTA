import generatedExercises from "@/data/exercises.generated.json"
import type { ExerciseSummary, MuscleId } from "@/types"

export const EXERCISES = generatedExercises as ExerciseSummary[]

export const EXERCISES_BY_ID = new Map(
  EXERCISES.map((exercise) => [exercise.id, exercise])
)

// A deliberately editorial popularity order for a general gym audience.
// This is product logic, not analytics: common, versatile equipment appears
// first and specialist/cardio accessories progressively follow.
const EQUIPMENT_POPULARITY = [
  "body weight",
  "dumbbell",
  "barbell",
  "cable",
  "kettlebell",
  "resistance band",
  "band",
  "smith machine",
  "leverage machine",
  "assisted",
  "stability ball",
  "medicine ball",
  "ez barbell",
  "olympic barbell",
  "weighted",
  "rope",
  "sled machine",
  "stationary bike",
  "elliptical machine",
  "stepmill machine",
  "skierg machine",
  "trap bar",
  "bosu ball",
  "roller",
  "wheel roller",
  "tire",
  "hammer",
  "upper body ergometer",
] as const

const availableEquipment = new Set(
  EXERCISES.map((exercise) => exercise.equipment)
)

export const EQUIPMENT_OPTIONS = [
  ...EQUIPMENT_POPULARITY.filter((equipment) =>
    availableEquipment.delete(equipment)
  ),
  ...[...availableEquipment].sort((left, right) => left.localeCompare(right)),
]

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
