import { readFileSync, writeFileSync } from "node:fs"
import { resolve } from "node:path"

const [, , frontArg, backArg, outputArg] = process.argv

if (!frontArg || !backArg || !outputArg) {
  throw new Error(
    "Usage: bun scripts/generate-body-paths.mjs MALE_FRONT_SWIFT MALE_BACK_SWIFT OUTPUT_JSON"
  )
}

const included = new Set([
  "trapezius",
  "deltoids",
  "chest",
  "upper-back",
  "serratus",
  "biceps",
  "triceps",
  "forearm",
  "abs",
  "obliques",
  "lower-back",
  "gluteal",
  "quadriceps",
  "hamstring",
  "adductors",
  "hip-flexors",
  "calves",
  "tibialis",
  "head",
  "hair",
  "neck",
  "hands",
  "feet",
  "knees",
  "ankles",
])

const slugMap = {
  lowerBack: "lower-back",
  upperBack: "upper-back",
  hipFlexors: "hip-flexors",
}

function parse(sourcePath) {
  const parts = []
  let current = null
  let section = null

  for (const line of readFileSync(resolve(sourcePath), "utf8").split("\n")) {
    if (line.includes("BodyPartPathData(")) {
      current = { slug: "", paths: [] }
      section = null
      continue
    }

    if (!current) continue

    const slugMatch = line.match(/slug: \.([A-Za-z]+)/)
    if (slugMatch) {
      current.slug = slugMap[slugMatch[1]] ?? slugMatch[1]
      continue
    }

    const sectionMatch = line.match(/^\s*(common|left|right): \[/)
    if (sectionMatch) {
      section = sectionMatch[1]
      continue
    }

    if (section && /^\s*\],?$/.test(line)) {
      section = null
      continue
    }

    if (section) {
      const pathMatch = line.trim().match(/^(".*")[,]?$/)
      if (pathMatch) current.paths.push(JSON.parse(pathMatch[1]))
      continue
    }

    if (/^\s*\),?$/.test(line)) {
      if (included.has(current.slug)) parts.push(current)
      current = null
    }
  }

  return parts
}

const output = {
  front: { viewBox: "0 95 727 1280", parts: parse(frontArg) },
  back: { viewBox: "718 95 727 1280", parts: parse(backArg) },
}

writeFileSync(resolve(outputArg), JSON.stringify(output))
console.log(
  `Generated ${output.front.parts.length} front and ${output.back.parts.length} back regions.`
)
