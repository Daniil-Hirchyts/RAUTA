import generatedExercises from "@/data/exercises.generated.json"
import type { ExerciseSummary, MuscleId } from "@/types"

export const EXERCISES = generatedExercises as ExerciseSummary[]

// Any grid/list of exercises can realistically be asked to show hundreds
// at once (broad muscle selections, a bulk-added workout) — each card
// stacks a CSS filter chain and a blended image, expensive enough at scale
// to crash mobile Safari's renderer. Every such list renders in bounded
// batches of this size instead (see useLoadMoreOnScroll).
export const EXERCISE_PAGE_SIZE = 40

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

export function musclesForExerciseIds(ids: string[]) {
  const muscles: MuscleId[] = []

  ids.forEach((id) => {
    const exercise = EXERCISES_BY_ID.get(id)
    if (!exercise) return

    exercise.muscles.forEach((muscle) => {
      if (!muscles.includes(muscle)) muscles.push(muscle)
    })
  })

  return muscles
}

const EQUIPMENT_RANK = new Map<string, number>(
  EQUIPMENT_POPULARITY.map((equipment, index) => [equipment, index])
)

// A stretch that isolates one muscle perfectly scores like the best possible
// match, which is not what someone browsing a gym library is after. Stretches
// and exotic equipment are nudged down rather than filtered out: the nudge is
// small enough that it only ever reorders exercises that already match about
// as well as each other.
const STRETCH_PENALTY = 0.75
const EQUIPMENT_SPREAD = 0.1

function presentationQuality(exercise: ExerciseSummary) {
  const rank = EQUIPMENT_RANK.get(exercise.equipment) ?? EQUIPMENT_RANK.size
  const familiarity = 1 - rank / EQUIPMENT_RANK.size

  return (
    (1 - EQUIPMENT_SPREAD + EQUIPMENT_SPREAD * familiarity) *
    (/\bstretch(es|ing)?\b/i.test(exercise.name) ? STRETCH_PENALTY : 1)
  )
}

// How well an exercise answers a muscle selection, as the product of two
// questions the user is really asking at once:
//
//   reach — how much of the picked muscles does this train? (sums involvement,
//           so a push-day selection rewards an exercise that hits all three)
//   focus — how much of the exercise lands on the picked muscles rather than
//           elsewhere? (a triceps pick puts dips above the bench press)
//
// Focus only ever halves the reach, so an exercise built around a picked
// muscle always outranks one that merely assists it.
const MIN_FOCUS = 0.5

export function relevance(
  exercise: ExerciseSummary,
  selectedMuscles: Set<MuscleId>
) {
  let reach = 0
  let effort = 0

  exercise.muscleWeights.forEach((weight, index) => {
    effort += weight
    if (selectedMuscles.has(exercise.muscles[index])) reach += weight
  })

  if (reach === 0) return 0
  return (
    reach *
    (MIN_FOCUS + (1 - MIN_FOCUS) * (reach / effort)) *
    presentationQuality(exercise)
  )
}

// Where a relevance-sorted list stops being about the selection and starts
// being exercises that merely touch it. Relevance splits cleanly in two: an
// exercise built around a picked muscle lands above FOCUSED_RELEVANCE, one
// that assists it lands well below, and nothing lands in between. The relative
// clause covers selections the library has no exercise built around — picking
// obliques tops out at ~0.4 — where an absolute bar would wrongly bury the
// entire list under a "supporting" heading.
const FOCUSED_RELEVANCE = 0.5
const FOCUSED_OF_BEST = 0.9

export function supportingFromIndex(
  relevanceSorted: ExerciseSummary[],
  selectedMuscles: MuscleId[]
) {
  if (relevanceSorted.length === 0) return -1

  const muscles = new Set(selectedMuscles)
  const cutoff = Math.min(
    FOCUSED_RELEVANCE,
    relevance(relevanceSorted[0], muscles) * FOCUSED_OF_BEST
  )
  const index = relevanceSorted.findIndex(
    (exercise) => relevance(exercise, muscles) < cutoff
  )

  return index <= 0 ? -1 : index
}

export function filterExercises(
  exercises: ExerciseSummary[],
  selectedMuscles: MuscleId[],
  selectedEquipment: string[]
) {
  if (selectedMuscles.length === 0 || selectedEquipment.length === 0) return []

  const muscles = new Set(selectedMuscles)
  const equipment = new Set(selectedEquipment)

  return exercises
    .filter((exercise) => equipment.has(exercise.equipment))
    .map((exercise) => ({ exercise, score: relevance(exercise, muscles) }))
    .filter(({ score }) => score > 0)
    .sort(
      (left, right) =>
        right.score - left.score ||
        left.exercise.name.localeCompare(right.exercise.name)
    )
    .map(({ exercise }) => exercise)
}
