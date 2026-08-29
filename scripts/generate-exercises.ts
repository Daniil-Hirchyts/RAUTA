import { readFileSync, writeFileSync } from "node:fs"
import { resolve } from "node:path"

import { normalizeExerciseMuscles } from "../src/lib/muscles"
import type { ExerciseSummary } from "../src/types"

type SourceExercise = {
  id: string
  name: string
  equipment: string
  target?: string
  muscle_group?: string
  secondary_muscles?: string[]
  instruction_steps?: { en?: string[] }
}

const [, , inputArg, outputArg] = process.argv

if (!inputArg || !outputArg) {
  throw new Error(
    "Usage: bun scripts/generate-exercises.ts SOURCE_JSON OUTPUT_JSON"
  )
}

const source = JSON.parse(
  readFileSync(resolve(inputArg), "utf8")
) as SourceExercise[]

const compact: ExerciseSummary[] = source
  .map((exercise) => ({
    id: exercise.id,
    name: exercise.name,
    equipment: exercise.equipment,
    ...normalizeExerciseMuscles({
      target: exercise.target,
      muscleGroup: exercise.muscle_group,
      secondaryMuscles: exercise.secondary_muscles,
    }),
    instructions: exercise.instruction_steps?.en ?? [],
  }))
  .sort(
    (left, right) =>
      left.name.localeCompare(right.name) || left.id.localeCompare(right.id)
  )

writeFileSync(resolve(outputArg), JSON.stringify(compact))
console.log(`Generated ${compact.length} exercises.`)
