import type { ExerciseSummary, MuscleId } from "@/types"

const EXERCISE_VISUALS = {
  squat: "/assets/exercises/squat.jpg",
  deadlift: "/assets/exercises/deadlift.jpg",
  "bench-press": "/assets/exercises/bench-press.jpg",
  "overhead-press": "/assets/exercises/overhead-press.jpg",
  row: "/assets/exercises/row.jpg",
  "pull-up": "/assets/exercises/pull-up.jpg",
  "biceps-curl": "/assets/exercises/biceps-curl.jpg",
  "triceps-pushdown": "/assets/exercises/triceps-pushdown.jpg",
  lunge: "/assets/exercises/lunge.jpg",
  "calf-raise": "/assets/exercises/calf-raise.jpg",
  crunch: "/assets/exercises/crunch.jpg",
  plank: "/assets/exercises/plank.jpg",
} as const

type ExerciseVisual = keyof typeof EXERCISE_VISUALS

const MUSCLE_FALLBACK: Partial<Record<MuscleId, ExerciseVisual>> = {
  quadriceps: "squat",
  hamstring: "deadlift",
  gluteal: "deadlift",
  "lower-back": "deadlift",
  chest: "bench-press",
  serratus: "bench-press",
  deltoids: "overhead-press",
  trapezius: "row",
  "upper-back": "row",
  biceps: "biceps-curl",
  forearm: "biceps-curl",
  triceps: "triceps-pushdown",
  calves: "calf-raise",
  tibialis: "calf-raise",
  abs: "crunch",
  obliques: "plank",
  adductors: "lunge",
  "hip-flexors": "lunge",
}

export function equipmentImage(equipment: string) {
  return `/assets/equipment/${equipment.replaceAll(" ", "-")}.jpg`
}

export function exerciseImage(exercise: ExerciseSummary) {
  const name = exercise.name.toLowerCase()
  let visual: ExerciseVisual | undefined

  if (/plank|mountain climber|bear crawl/.test(name)) visual = "plank"
  else if (
    /crunch|sit[ -]?up|abdominal|leg raise|knee raise|russian twist|wood chop/.test(
      name
    )
  )
    visual = "crunch"
  else if (/calf|heel raise/.test(name)) visual = "calf-raise"
  else if (/lunge|split squat|step[ -]?up/.test(name)) visual = "lunge"
  else if (/triceps|pushdown|skull crusher|kickback/.test(name))
    visual = "triceps-pushdown"
  else if (/curl|preacher/.test(name)) visual = "biceps-curl"
  else if (/pull[ -]?up|chin[ -]?up|pulldown|lat pull/.test(name))
    visual = "pull-up"
  else if (/\brow\b|reverse fly|pullover/.test(name)) visual = "row"
  else if (
    /shoulder press|overhead press|military press|arnold|front raise|lateral raise|upright row|shrug/.test(
      name
    )
  )
    visual = "overhead-press"
  else if (
    /bench press|chest press|push[ -]?up|\bdip\b|\bfly\b|pec deck/.test(name)
  )
    visual = "bench-press"
  else if (
    /deadlift|good morning|hip thrust|pull through|hyperextension|back extension|romanian|stiff leg/.test(
      name
    )
  )
    visual = "deadlift"
  else if (/squat|thruster|leg press|hack/.test(name)) visual = "squat"

  visual ??= exercise.primaryMuscle
    ? MUSCLE_FALLBACK[exercise.primaryMuscle]
    : undefined

  return EXERCISE_VISUALS[visual ?? "squat"]
}
