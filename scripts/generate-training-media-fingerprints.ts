import { createHash } from "node:crypto"
import { readFileSync, writeFileSync } from "node:fs"
import exercises from "../src/data/exercises.generated.json"
import type { ExerciseSummary } from "../src/types"

const data = exercises as ExerciseSummary[]
const fingerprints = Object.fromEntries(
  data.map((exercise) => {
    const bytes = readFileSync(
      `public/assets/exercises/webp/${exercise.id}.webp`
    )
    return [exercise.id, createHash("sha256").update(bytes).digest("hex")]
  })
)

writeFileSync(
  "src/training/data/exercise-media-fingerprints.json",
  JSON.stringify(fingerprints, null, 2) + "\n"
)
console.log(JSON.stringify({ exercises: data.length }))
