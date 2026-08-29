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

export function normalizeMuscle(value: unknown): MuscleId | null {
  const key = String(value ?? "")
    .trim()
    .toLowerCase()
  return MUSCLE_ALIASES[key] ?? null
}

export function normalizeExerciseMuscles(values: {
  target?: unknown
  muscleGroup?: unknown
  secondaryMuscles?: unknown[] | null
}) {
  const normalized = [
    normalizeMuscle(values.target),
    normalizeMuscle(values.muscleGroup),
    ...(values.secondaryMuscles ?? []).map(normalizeMuscle),
  ].filter((muscle): muscle is MuscleId => muscle !== null)

  return {
    primaryMuscle:
      normalizeMuscle(values.target) ?? normalizeMuscle(values.muscleGroup),
    muscles: [...new Set(normalized)],
  }
}

export function isMuscleId(value: string): value is MuscleId {
  return (MUSCLE_IDS as readonly string[]).includes(value)
}
