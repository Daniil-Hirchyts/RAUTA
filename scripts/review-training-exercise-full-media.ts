import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import exercises from "../src/data/exercises.generated.json"
import type { ExerciseSummary } from "../src/types"
import {
  compositeAnimationFrame,
  createAnimationCanvas,
  disposeAnimationFrame,
  flattenAnimationCanvas,
  parseAnimationInfo,
  type AnimationInfo,
  type Rgba,
} from "./webp-compositor"

const allExercises = [...(exercises as ExerciseSummary[])].sort((a, b) =>
  a.id.localeCompare(b.id)
)
const requested = new Set(process.argv.slice(2))
const data = requested.size
  ? allExercises.filter((exercise) => requested.has(exercise.id))
  : allExercises
if (data.length !== (requested.size || allExercises.length))
  throw new Error("One or more requested exercise IDs do not exist")

const root = "docs/training-engine/media-review/full-sequences"
const sheetRoot = join(root, "sheets")
const boardRoot = join(root, "boards")
const pageSize = 8
const boardColumns = 2
const cardWidth = 960
const cardHeight = 680

rmSync(root, { recursive: true, force: true })
mkdirSync(sheetRoot, { recursive: true })
mkdirSync(boardRoot, { recursive: true })

function run(command: string[]): string {
  const result = Bun.spawnSync(command, { stdout: "pipe", stderr: "pipe" })
  if (result.exitCode !== 0)
    throw new Error(
      `${command[0]} failed: ${result.stderr.toString().trim() || result.stdout.toString().trim()}`
    )
  return result.stdout.toString()
}

function animationInfo(mediaPath: string): AnimationInfo {
  return parseAnimationInfo(run(["webpmux", "-info", mediaPath]), mediaPath)
}

function readPam(path: string): { width: number; height: number; pixels: Uint8Array } {
  const input = readFileSync(path)
  const marker = Buffer.from("ENDHDR\n")
  const headerEnd = input.indexOf(marker)
  if (headerEnd < 0) throw new Error(`Invalid PAM header: ${path}`)
  const header = input.subarray(0, headerEnd + marker.length).toString("ascii")
  const width = Number(header.match(/^WIDTH\s+(\d+)$/m)?.[1])
  const height = Number(header.match(/^HEIGHT\s+(\d+)$/m)?.[1])
  const depth = Number(header.match(/^DEPTH\s+(\d+)$/m)?.[1])
  if (!width || !height || ![3, 4].includes(depth)) throw new Error(`Unsupported PAM: ${path}`)
  const source = input.subarray(headerEnd + marker.length)
  if (source.length !== width * height * depth) throw new Error(`Invalid PAM payload: ${path}`)
  const pixels = new Uint8Array(width * height * 4)
  for (let sourceOffset = 0, targetOffset = 0; sourceOffset < source.length; sourceOffset += depth, targetOffset += 4) {
    pixels[targetOffset] = source[sourceOffset]
    pixels[targetOffset + 1] = source[sourceOffset + 1]
    pixels[targetOffset + 2] = source[sourceOffset + 2]
    pixels[targetOffset + 3] = depth === 4 ? source[sourceOffset + 3] : 255
  }
  return { width, height, pixels }
}

function writePpm(
  path: string,
  canvas: Uint8Array,
  width: number,
  height: number,
  background: Rgba
) {
  const rgb = flattenAnimationCanvas(canvas, background)
  writeFileSync(
    path,
    Buffer.concat([
      Buffer.from(`P6\n${width} ${height}\n255\n`),
      Buffer.from(rgb),
    ])
  )
}

const reviewed = data.map((exercise) => {
  const mediaPath = `public/assets/exercises/webp/${exercise.id}.webp`
  if (!existsSync(mediaPath)) throw new Error(`Missing media: ${mediaPath}`)
  const info = animationInfo(mediaPath)
  const frameCount = info.frames.length
  const exerciseRoot = join(root, exercise.id)
  mkdirSync(exerciseRoot, { recursive: true })
  const width = String(frameCount).length
  const canvas = createAnimationCanvas(info.width, info.height, info.background)
  for (let index = 0; index < frameCount; index++) {
    const frameNumber = index + 1
    const frame = info.frames[index]
    const stem = `frame-${String(frameNumber).padStart(width, "0")}`
    const temporaryWebp = join(exerciseRoot, `${stem}.webp`)
    const temporaryPam = join(exerciseRoot, `${stem}.pam`)
    const ppm = join(exerciseRoot, `${stem}.ppm`)
    run(["webpmux", "-get", "frame", String(frameNumber), mediaPath, "-o", temporaryWebp])
    run(["dwebp", temporaryWebp, "-pam", "-o", temporaryPam])
    const decoded = readPam(temporaryPam)
    if (decoded.width !== frame.width || decoded.height !== frame.height)
      throw new Error(`Frame geometry mismatch: ${exercise.id} frame ${frameNumber}`)
    compositeAnimationFrame(
      canvas,
      info.width,
      info.height,
      frame,
      decoded.pixels
    )
    writePpm(ppm, canvas, info.width, info.height, info.background)
    disposeAnimationFrame(canvas, info.width, frame, info.background)
    rmSync(temporaryWebp, { force: true })
    rmSync(temporaryPam, { force: true })
  }
  const columns = Math.min(9, frameCount)
  const rows = Math.ceil(frameCount / columns)
  const sheet = join(sheetRoot, `${exercise.id}.png`)
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
    join(exerciseRoot, "frame-*.ppm"),
    "-vf",
    `scale=240:-1,tile=${columns}x${rows}:padding=3:margin=3`,
    "-frames:v",
    "1",
    "-y",
    sheet,
  ])
  rmSync(exerciseRoot, { recursive: true, force: true })
  return {
    id: exercise.id,
    name: exercise.name,
    frameCount,
    reviewedFrameNumbers: Array.from({ length: frameCount }, (_, index) => index + 1),
    sheet,
  }
})

const pages: { page: number; exercises: typeof reviewed }[] = []
for (let offset = 0; offset < reviewed.length; offset += pageSize) {
  const page = reviewed.slice(offset, offset + pageSize)
  const inputs = page.flatMap((exercise) => ["-i", exercise.sheet])
  const filters = page.map(
    (_, index) =>
      `[${index}:v]scale=${cardWidth}:${cardHeight}:force_original_aspect_ratio=decrease,pad=${cardWidth}:${cardHeight}:(ow-iw)/2:(oh-ih)/2:black[v${index}]`
  )
  const layout = page
    .map(
      (_, index) =>
        `${(index % boardColumns) * cardWidth}_${Math.floor(index / boardColumns) * cardHeight}`
    )
    .join("|")
  const pageNumber = String(offset / pageSize + 1).padStart(3, "0")
  if (page.length === 1) {
    run([
      "ffmpeg",
      "-hide_banner",
      "-loglevel",
      "error",
      "-i",
      page[0].sheet,
      "-vf",
      `scale=${cardWidth}:${cardHeight}:force_original_aspect_ratio=decrease,pad=${cardWidth}:${cardHeight}:(ow-iw)/2:(oh-ih)/2:black`,
      "-q:v",
      "2",
      "-frames:v",
      "1",
      "-y",
      join(boardRoot, `page-${pageNumber}.jpg`),
    ])
    pages.push({ page: offset / pageSize + 1, exercises: page })
    continue
  }
  run([
    "ffmpeg",
    "-hide_banner",
    "-loglevel",
    "error",
    ...inputs,
    "-filter_complex",
    `${filters.join(";")};${page.map((_, index) => `[v${index}]`).join("")}xstack=inputs=${page.length}:layout=${layout}:fill=black[out]`,
    "-map",
    "[out]",
    "-q:v",
    "2",
    "-frames:v",
    "1",
    "-y",
    join(boardRoot, `page-${pageNumber}.jpg`),
  ])
  pages.push({ page: offset / pageSize + 1, exercises: page })
}

writeFileSync(join(root, "manifest.json"), JSON.stringify(reviewed, null, 2) + "\n")
writeFileSync(join(boardRoot, "manifest.json"), JSON.stringify(pages, null, 2) + "\n")
console.log(JSON.stringify({ exercises: reviewed.length, pages: pages.length, root }))
