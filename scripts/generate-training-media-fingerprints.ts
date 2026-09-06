import { createHash } from "node:crypto"
import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs"
import exercises from "../src/data/exercises.generated.json"
import committedFingerprints from "../src/training/data/exercise-media-fingerprints.json"
import type { ExerciseSummary } from "../src/types"

const data = exercises as ExerciseSummary[]
const mediaRoot = "public/assets/exercises/webp"
const outputPath = "src/training/data/exercise-media-fingerprints.json"
const checkOnly = process.argv.includes("--check")
const sourceIds = new Set(data.map((exercise) => exercise.id))
const mediaIds = new Set(
  readdirSync(mediaRoot)
    .filter((file) => file.endsWith(".webp"))
    .map((file) => file.slice(0, -".webp".length))
)
const committed = committedFingerprints as Record<string, string>
const sourceMediaMissing = data
  .filter((exercise) => !existsSync(`${mediaRoot}/${exercise.id}.webp`))
  .map((exercise) => exercise.id)
const missingFingerprints = data
  .filter((exercise) => !committed[exercise.id])
  .map((exercise) => exercise.id)
const unexpectedFingerprints = Object.keys(committed).filter(
  (exerciseId) => !sourceIds.has(exerciseId)
)
const unexpectedMediaFiles = [...mediaIds].filter(
  (exerciseId) => !sourceIds.has(exerciseId)
)
const fingerprints = Object.fromEntries(
  data.flatMap((exercise) => {
    const mediaPath = `${mediaRoot}/${exercise.id}.webp`
    if (!existsSync(mediaPath)) return []
    const bytes = readFileSync(mediaPath)
    return [[exercise.id, createHash("sha256").update(bytes).digest("hex")]]
  })
)
const changedFingerprints = data
  .filter(
    (exercise) =>
      committed[exercise.id] &&
      fingerprints[exercise.id] !== committed[exercise.id]
  )
  .map((exercise) => exercise.id)
const result = {
  exercises: data.length,
  mediaFiles: mediaIds.size,
  fingerprints: Object.keys(committed).length,
  sourceMediaMissing,
  missingFingerprints,
  unexpectedFingerprints,
  unexpectedMediaFiles,
  changedFingerprints,
}

if (checkOnly) {
  console.log(JSON.stringify(result))
  if (
    sourceMediaMissing.length ||
    missingFingerprints.length ||
    unexpectedFingerprints.length ||
    unexpectedMediaFiles.length ||
    changedFingerprints.length
  )
    process.exitCode = 1
} else {
  if (sourceMediaMissing.length || unexpectedMediaFiles.length)
    throw new Error(`Media/source mismatch: ${JSON.stringify(result)}`)
  writeFileSync(outputPath, JSON.stringify(fingerprints, null, 2) + "\n")
  console.log(JSON.stringify({ exercises: data.length, outputPath }))
}
