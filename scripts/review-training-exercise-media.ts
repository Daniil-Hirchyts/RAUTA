import { createHash } from "node:crypto"
import {
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs"
import { join } from "node:path"
import exercises from "../src/data/exercises.generated.json"
import { resolveExerciseMetadata } from "../src/training/data/exercises"
import { getCuratedExerciseReview } from "../src/training/data/curated-exercises"
import { sourceExerciseFingerprint } from "../src/training/data/curated-exercises"
import type { ExerciseSummary } from "../src/training"

const data = exercises as ExerciseSummary[]
const requestedIds = process.argv.slice(2)
if (!requestedIds.length)
  throw new Error(
    "Pass one or more exercise IDs, for example: bun scripts/review-training-exercise-media.ts 0088 1371"
  )

const outputRoot = "docs/training-engine/media-review"
mkdirSync(outputRoot, { recursive: true })
const requestedFrameCount = 10

function run(command: string[]): string {
  const result = Bun.spawnSync(command, { stdout: "pipe", stderr: "pipe" })
  if (result.exitCode !== 0)
    throw new Error(
      `${command[0]} failed: ${result.stderr.toString().trim() || result.stdout.toString().trim()}`
    )
  return result.stdout.toString()
}

const extracted = requestedIds.map((exerciseId) => {
  const exercise = data.find((candidate) => candidate.id === exerciseId)
  if (!exercise) throw new Error(`Unknown exercise ID: ${exerciseId}`)
  const mediaPath = `public/assets/exercises/webp/${exerciseId}.webp`
  if (!existsSync(mediaPath)) throw new Error(`Missing media: ${mediaPath}`)

  const info = run(["webpinfo", mediaPath])
  const frameCount = Math.max(1, (info.match(/\bANMF\b/g) ?? []).length)
  const sampleCount = Math.min(requestedFrameCount, frameCount)
  const frameNumbers = Array.from({ length: sampleCount }, (_, index) =>
    sampleCount === 1
      ? 1
      : Math.round(1 + (index * (frameCount - 1)) / (sampleCount - 1))
  ).filter((frame, index, values) => values.indexOf(frame) === index)
  const exerciseDir = join(outputRoot, exerciseId)
  rmSync(exerciseDir, { recursive: true, force: true })
  mkdirSync(exerciseDir, { recursive: true })

  const width = String(frameCount).length
  const frames = frameNumbers.map((frame, sampleIndex) => {
    const stem = `sample-${String(sampleIndex + 1).padStart(2, "0")}-frame-${String(frame).padStart(width, "0")}`
    const temporaryWebp = join(exerciseDir, `${stem}.webp`)
    const png = join(exerciseDir, `${stem}.png`)
    run(["webpmux", "-get", "frame", String(frame), mediaPath, "-o", temporaryWebp])
    run(["dwebp", temporaryWebp, "-o", png])
    rmSync(temporaryWebp, { force: true })
    return png
  })
  const contactSheet = join(exerciseDir, "contact-sheet.png")
  const columns = Math.min(5, frames.length)
  const rows = Math.ceil(frames.length / columns)
  run([
    "ffmpeg",
    "-hide_banner",
    "-loglevel",
    "error",
    "-framerate",
    "1",
    "-pattern_type",
    "glob",
    "-i",
    join(exerciseDir, "sample-*.png"),
    "-vf",
    `scale=320:-1,tile=${columns}x${rows}:padding=4:margin=4`,
    "-frames:v",
    "1",
    "-y",
    contactSheet,
  ])
  const currentReview = getCuratedExerciseReview(exerciseId)
  const sourceFingerprint = sourceExerciseFingerprint(exercise)
  const mediaFingerprint = createHash("sha256")
    .update(readFileSync(mediaPath))
    .digest("hex")

  return {
    exerciseId,
    name: exercise.name,
    instructions: exercise.instructions,
    sourceMuscles: exercise.muscles,
    primaryMuscle: exercise.primaryMuscle,
    equipment: exercise.equipment,
    mediaPath,
    frameCount,
    sampledFrameNumbers: frameNumbers,
    sourceExerciseFingerprint: sourceFingerprint,
    mediaFingerprint,
    frameFiles: frames,
    contactSheet,
    inferredMetadata: resolveExerciseMetadata(exercise),
    currentReview: currentReview ?? null,
    reviewTemplate: {
      exerciseId,
      reviewedFrom: [],
      reviewedFields: [],
      sourceExerciseFingerprint: sourceFingerprint,
      mediaFingerprint,
      reviewedFrameNumbers: frameNumbers,
      metadata: {},
    },
    reviewStatus: "package_generated_not_reviewed" as const,
  }
})

const manifestPath = join(outputRoot, "extraction-manifest.json")
writeFileSync(manifestPath, JSON.stringify(extracted, null, 2) + "\n")
console.log(JSON.stringify({ manifestPath, extracted: extracted.length }))
