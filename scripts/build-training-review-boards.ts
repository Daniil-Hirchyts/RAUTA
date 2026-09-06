import { existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import exercises from "../src/data/exercises.generated.json"
import type { ExerciseSummary } from "../src/types"

const data = [...(exercises as ExerciseSummary[])].sort((a, b) =>
  a.id.localeCompare(b.id)
)
const reviewRoot = "docs/training-engine/media-review"
const boardRoot = join(reviewRoot, "boards")
const pageSize = 16
const columns = 4
const cardWidth = 500
const cardHeight = 420
const manifest: { page: number; exercises: { id: string; name: string }[] }[] = []
rmSync(boardRoot, { recursive: true, force: true })
mkdirSync(boardRoot, { recursive: true })

function run(command: string[]): void {
  const result = Bun.spawnSync(command, { stdout: "pipe", stderr: "pipe" })
  if (result.exitCode !== 0)
    throw new Error(
      `${command[0]} failed: ${result.stderr.toString().trim() || result.stdout.toString().trim()}`
    )
}

for (let offset = 0; offset < data.length; offset += pageSize) {
  const page = data.slice(offset, offset + pageSize)
  const inputs = page.flatMap((exercise) => {
    const contactSheet = join(reviewRoot, exercise.id, "contact-sheet.png")
    if (!existsSync(contactSheet))
      throw new Error(`Missing contact sheet: ${contactSheet}`)
    return ["-i", contactSheet]
  })
  const filters = page.map(
    (_, index) =>
      `[${index}:v]scale=${cardWidth}:${cardHeight}:force_original_aspect_ratio=decrease,pad=${cardWidth}:${cardHeight}:(ow-iw)/2:(oh-ih)/2:black[v${index}]`
  )
  const layout = page
    .map(
      (_, index) =>
        `${(index % columns) * cardWidth}_${Math.floor(index / columns) * cardHeight}`
    )
    .join("|")
  const pageNumber = String(offset / pageSize + 1).padStart(3, "0")
  manifest.push({
    page: offset / pageSize + 1,
    exercises: page.map(({ id, name }) => ({ id, name })),
  })
  const output = join(boardRoot, `page-${pageNumber}.jpg`)
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
    output,
  ])
}

writeFileSync(
  join(boardRoot, "manifest.json"),
  JSON.stringify(manifest, null, 2) + "\n"
)

console.log(
  JSON.stringify({ exercises: data.length, pages: Math.ceil(data.length / pageSize), boardRoot })
)
