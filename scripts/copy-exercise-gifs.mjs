import { copyFileSync, mkdirSync, readFileSync, readdirSync } from "node:fs"
import { resolve, join, dirname } from "node:path"

const [, , sourceDatasetDirArg, outputDirArg] = process.argv

if (!sourceDatasetDirArg || !outputDirArg) {
  throw new Error(
    "Usage: bun scripts/copy-exercise-gifs.mjs SOURCE_DATASET_DIR OUTPUT_DIR\n" +
      "SOURCE_DATASET_DIR is a local checkout of hasaneyldrm/exercises-dataset " +
      "(must contain data/exercises.json and videos/)."
  )
}

const sourceDatasetDir = resolve(sourceDatasetDirArg)
const outputDir = resolve(outputDirArg)

const source = JSON.parse(
  readFileSync(join(sourceDatasetDir, "data/exercises.json"), "utf8")
)

mkdirSync(outputDir, { recursive: true })

let copied = 0
let skipped = 0

for (const exercise of source) {
  if (!exercise.gif_url) {
    skipped++
    continue
  }

  const from = join(sourceDatasetDir, exercise.gif_url)
  const to = join(outputDir, `${exercise.id}.gif`)
  mkdirSync(dirname(to), { recursive: true })
  copyFileSync(from, to)
  copied++
}

console.log(
  `Copied ${copied} exercise GIFs to ${outputDir} (${skipped} skipped, no gif_url).`
)
console.log(`Output now contains ${readdirSync(outputDir).length} files.`)
