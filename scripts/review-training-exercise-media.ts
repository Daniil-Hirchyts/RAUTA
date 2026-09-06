import { existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import exercises from "../src/data/exercises.generated.json"
import type { ExerciseSummary } from "../src/training"

const data = exercises as ExerciseSummary[]
const requestedIds = process.argv.slice(2)
if (!requestedIds.length)
  throw new Error(
    "Pass one or more exercise IDs, for example: bun scripts/review-training-exercise-media.ts 0088 1371"
  )

const outputRoot = "docs/training-engine/media-review"
mkdirSync(outputRoot, { recursive: true })

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
  const frameNumbers = [1, Math.ceil(frameCount / 2), frameCount].filter(
    (frame, index, values) => values.indexOf(frame) === index
  )
  const exerciseDir = join(outputRoot, exerciseId)
  mkdirSync(exerciseDir, { recursive: true })

  const frames = frameNumbers.map((frame) => {
    const temporaryWebp = join(exerciseDir, `frame-${frame}.webp`)
    const png = join(exerciseDir, `frame-${frame}.png`)
    run(["webpmux", "-get", "frame", String(frame), mediaPath, "-o", temporaryWebp])
    run(["dwebp", temporaryWebp, "-o", png])
    rmSync(temporaryWebp, { force: true })
    return png
  })

  return {
    exerciseId,
    name: exercise.name,
    mediaPath,
    frameCount,
    extractedFrames: frameNumbers,
    frameFiles: frames,
    reviewStatus: "frames_extracted_not_reviewed" as const,
  }
})

const manifestPath = join(outputRoot, "extraction-manifest.json")
writeFileSync(manifestPath, JSON.stringify(extracted, null, 2) + "\n")
console.log(JSON.stringify({ manifestPath, extracted: extracted.length }))
