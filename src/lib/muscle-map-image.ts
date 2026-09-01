import bodyPathData from "@/data/body-paths.generated.json"
import { isMuscleId } from "@/lib/muscles"
import { isNative } from "@/lib/native"
import type { MuscleId } from "@/types"

type BodyPart = { slug: string; paths: string[] }
type BodyView = { viewBox: string; parts: BodyPart[] }
type Side = "front" | "back"

const body = bodyPathData as Record<Side, BodyView>

/**
 * The map's own palette. It is not the app's: on screen the figures sit on a
 * lit card, on the Lock Screen they sit on near-black, and the greys the app
 * uses disappear there. Everything is lifted far enough to read against the
 * card's own background at a glance, with the worked muscles on the brand
 * orange so they are the only thing the eye has to find.
 */
const SILHOUETTE = "#33333a"
const MUSCLE = "#4b4b56"
const WORKED = "#ff6633"
const OUTLINE = "#101014"

// One figure is 727 × 1280 in the generated path data.
const FIGURE_WIDTH = 727
const FIGURE_HEIGHT = 1280
// Comfortably over the ~150px the tallest slot needs on a 3x screen.
const CANVAS_WIDTH = 300
const CANVAS_HEIGHT = Math.round((CANVAS_WIDTH / FIGURE_WIDTH) * FIGURE_HEIGHT)

const MUSCLES_BY_SIDE: Record<Side, Set<MuscleId>> = {
  back: sideMuscles("back"),
  front: sideMuscles("front"),
}

function sideMuscles(side: Side) {
  return new Set(
    body[side].parts.flatMap((part) =>
      isMuscleId(part.slug) ? [part.slug] : []
    )
  )
}

/**
 * Which way the figure faces.
 *
 * The card has room for one body, not two: a pair of figures shrunk to fit
 * beside the timer is a smudge rather than a diagram. So the map shows the
 * side the exercise is actually about — muscles are ranked strongest-first, so
 * the leading ones decide it, and a tie stays on the front.
 */
export function preferredSide(muscles: MuscleId[]): Side {
  let front = 0
  let back = 0

  muscles.forEach((muscle, index) => {
    const weight = 1 / (index + 1)
    if (MUSCLES_BY_SIDE.front.has(muscle)) front += weight
    if (MUSCLES_BY_SIDE.back.has(muscle)) back += weight
  })

  return back > front ? "back" : "front"
}

/** Identifies one rendering: the same muscles always produce the same map, so
 *  the file it is written to can be named after them and the side they face. */
export function muscleMapKey(muscles: MuscleId[]) {
  const worked = [...new Set(muscles)]
  if (worked.length === 0) return ""

  return `${preferredSide(muscles)}-${[...worked].sort().join("-")}`
}

// A prepared map is a few kilobytes and there are only so many muscle
// combinations in a workout, so both the successes and the failures are worth
// keeping for the life of the web view — a failure caches as "" so a browser
// that cannot rasterize is not asked twice per exercise.
const rendered = new Map<string, string>()
const inFlight = new Set<string>()

/**
 * The base64 PNG for `muscles` if it is already prepared, and `null` if it is
 * not — in which case the rendering starts and `onReady` is called once the
 * next request will succeed. Rasterizing is asynchronous but the Live Activity
 * sync is not, so the map arrives with the following frame rather than holding
 * the current one back.
 */
export function muscleMapPng(muscles: MuscleId[], onReady?: () => void) {
  const key = muscleMapKey(muscles)
  if (!key || !isNative()) return null

  const prepared = rendered.get(key)
  if (prepared !== undefined) return prepared || null
  if (inFlight.has(key)) return null

  inFlight.add(key)
  void renderMuscleMapPng(muscles)
    .catch(() => null)
    .then((png) => {
      rendered.set(key, png ?? "")
      inFlight.delete(key)
      if (png) onReady?.()
    })

  return null
}

/** Test seam: forgets everything prepared so far. */
export function resetMuscleMapCache() {
  rendered.clear()
  inFlight.clear()
}

async function renderMuscleMapPng(muscles: MuscleId[]) {
  const canvas = document.createElement("canvas")
  canvas.width = CANVAS_WIDTH
  canvas.height = CANVAS_HEIGHT
  const context = canvas.getContext("2d")
  if (!context) return null

  const image = await loadImage(muscleMapSvg(muscles))
  context.drawImage(image, 0, 0, CANVAS_WIDTH, CANVAS_HEIGHT)

  return canvas.toDataURL("image/png").split(",")[1] ?? null
}

function loadImage(svg: string) {
  return new Promise<HTMLImageElement>((resolve, reject) => {
    const image = new Image()
    image.onload = () => resolve(image)
    image.onerror = () => reject(new Error("Could not rasterize muscle map"))
    // A data URL keeps the drawing same-origin, so the canvas stays untainted
    // and `toDataURL` is allowed to read it back.
    image.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`
  })
}

/**
 * One figure, facing the way {@link preferredSide} chose, with the exercise's
 * muscles picked out. Width and height are spelled out on the root because
 * Safari refuses to draw an SVG image that only carries a viewBox.
 */
export function muscleMapSvg(muscles: MuscleId[]) {
  const view = body[preferredSide(muscles)]
  const [minX, minY] = view.viewBox.split(" ").map(Number)
  const worked = new Set(muscles)

  const parts = view.parts
    .map((part) => {
      const muscle = isMuscleId(part.slug) ? part.slug : null
      const fill = !muscle ? SILHOUETTE : worked.has(muscle) ? WORKED : MUSCLE
      const paths = part.paths.map((path) => `<path d="${path}"/>`).join("")

      return `<g fill="${fill}">${paths}</g>`
    })
    .join("")

  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${CANVAS_WIDTH}" height="${CANVAS_HEIGHT}" viewBox="0 0 ${FIGURE_WIDTH} ${FIGURE_HEIGHT}">`,
    `<g transform="translate(${-minX} ${-minY})" stroke="${OUTLINE}" stroke-width="3">${parts}</g>`,
    `</svg>`,
  ].join("")
}
