import { MUSCLE_IDS, type MuscleId } from "@/types"

export const MUSCLE_LABELS: Record<MuscleId, string> = {
  trapezius: "Traps",
  deltoids: "Shoulders",
  chest: "Chest",
  "upper-back": "Upper back",
  serratus: "Serratus",
  biceps: "Biceps",
  triceps: "Triceps",
  forearm: "Forearms",
  abs: "Abs",
  obliques: "Obliques",
  "lower-back": "Lower back",
  gluteal: "Glutes",
  quadriceps: "Quads",
  hamstring: "Hamstrings",
  adductors: "Adductors",
  "hip-flexors": "Hip flexors",
  calves: "Calves",
  tibialis: "Shins",
}

export const MUSCLE_ALIASES: Record<string, MuscleId | null> = {
  abs: "abs",
  abdominals: "abs",
  core: "abs",
  "lower abs": "abs",
  pectorals: "chest",
  chest: "chest",
  "upper chest": "chest",
  biceps: "biceps",
  brachialis: "biceps",
  glutes: "gluteal",
  abductors: "gluteal",
  delts: "deltoids",
  deltoids: "deltoids",
  shoulders: "deltoids",
  "rear deltoids": "deltoids",
  "rotator cuff": "deltoids",
  triceps: "triceps",
  "upper back": "upper-back",
  lats: "upper-back",
  back: "upper-back",
  rhomboids: "upper-back",
  "latissimus dorsi": "upper-back",
  calves: "calves",
  soleus: "calves",
  quads: "quadriceps",
  quadriceps: "quadriceps",
  forearms: "forearm",
  wrists: "forearm",
  "wrist flexors": "forearm",
  "wrist extensors": "forearm",
  "grip muscles": "forearm",
  hamstrings: "hamstring",
  spine: "lower-back",
  "lower back": "lower-back",
  traps: "trapezius",
  trapezius: "trapezius",
  "levator scapulae": "trapezius",
  adductors: "adductors",
  groin: "adductors",
  "inner thighs": "adductors",
  "serratus anterior": "serratus",
  obliques: "obliques",
  "hip flexors": "hip-flexors",
  shins: "tibialis",
  "cardiovascular system": null,
  ankles: null,
  "ankle stabilizers": null,
  feet: null,
  hands: null,
  sternocleidomastoid: null,
}

// Not every term in the source vocabulary describes a muscle that is actually
// being trained. "Core" or "grip muscles" name involvement that is real but
// incidental — the muscle holds a position rather than moving the weight — so
// those terms are damped and can never outrank a term that names the muscle
// doing the work.
const TERM_INTENSITY: Record<string, number> = {
  "grip muscles": 0.35,
  wrists: 0.35,
  "wrist flexors": 0.35,
  "wrist extensors": 0.35,
  core: 0.4,
  "rotator cuff": 0.4,
  "levator scapulae": 0.5,
  back: 0.8,
  brachialis: 0.8,
}

// The source lists assisting muscles strongest-first, and the drop-off is
// steep: by the third assist a muscle is closer to stabilising than to being
// trained. Involvement below MIN_INVOLVEMENT is discarded outright, which is
// what keeps "pick forearms" from returning every curl and deadlift in the
// library just because a hand was involved.
const ASSIST_INVOLVEMENT = 0.62
const ASSIST_DECAY = 0.68
const MIN_INVOLVEMENT = 0.15

export function normalizeMuscle(value: unknown): MuscleId | null {
  return MUSCLE_ALIASES[muscleKey(value)] ?? null
}

function muscleKey(value: unknown) {
  return String(value ?? "")
    .trim()
    .toLowerCase()
}

export function normalizeExerciseMuscles(values: {
  target?: unknown
  muscleGroup?: unknown
  secondaryMuscles?: unknown[] | null
}) {
  // `muscle_group` reads like a category but behaves like the first assisting
  // muscle ("biceps" curls are grouped under "forearms"), so it is ranked with
  // the assists — and only promoted to primary when the target is undrawable,
  // as it is for the cardio entries.
  const primaryMuscle =
    normalizeMuscle(values.target) ?? normalizeMuscle(values.muscleGroup)

  const involvement = new Map<MuscleId, number>()
  if (primaryMuscle) involvement.set(primaryMuscle, 1)

  let rank = 0
  for (const value of [
    values.muscleGroup,
    ...(values.secondaryMuscles ?? []),
  ]) {
    const muscle = normalizeMuscle(value)
    if (!muscle || involvement.has(muscle)) continue

    const weight =
      ASSIST_INVOLVEMENT *
      ASSIST_DECAY ** rank *
      (TERM_INTENSITY[muscleKey(value)] ?? 1)
    rank += 1

    if (weight >= MIN_INVOLVEMENT) involvement.set(muscle, round(weight))
  }

  const ranked = [...involvement].sort(([, left], [, right]) => right - left)

  return {
    primaryMuscle,
    muscles: ranked.map(([muscle]) => muscle),
    muscleWeights: ranked.map(([, weight]) => weight),
  }
}

function round(weight: number) {
  return Math.round(weight * 100) / 100
}

export function isMuscleId(value: string): value is MuscleId {
  return (MUSCLE_IDS as readonly string[]).includes(value)
}
