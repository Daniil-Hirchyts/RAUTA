import { EXERCISES_BY_ID } from "@/lib/exercises"
import { resolveExerciseMetadata, roundLoad } from "@/training"
import type { ExerciseMetadata, LoadGrid } from "@/training"
import type {
  PersistedCompletedSet,
  PersistedLoadConfiguration,
  PersistedResistance,
} from "@/training-persistence/schema"
import type { ExerciseSummary } from "@/types"

/**
 * What "80" means when someone logs it.
 *
 * The engine already refuses a naked number: a `ResistanceValue` says whether
 * a kilogram is load or assistance, and whether it is carried by one implement
 * or by the pair. This file is the application side of that contract — it
 * decides, from the exercise the person is actually performing, which of those
 * shapes the set editor should collect and in what steps.
 *
 * It states nothing the engine already states. Whether an exercise is loaded,
 * assisted, body weight or band is `ExerciseMetadata.tracking`, read straight
 * from the catalogue; only the parts the catalogue has no opinion on — the
 * plate/stack increments a gym actually stocks, and the wording — live here.
 */

export type ResistanceMode = PersistedResistance["type"]
export type SetSide = PersistedCompletedSet["side"]

/** Station and basis a set is measured against, plus the steps its load moves
 *  in. The engine compares kilograms only within one station and basis, so
 *  every logged set has to carry both. */
export type LoadContext = {
  stationId: string
  basis: "total" | "per_implement"
  grid: LoadGrid
}

/**
 * How the load on a piece of equipment is held and what it moves in.
 *
 * `per_implement` is the "each" case: a 30 kg dumbbell in each hand is not
 * 60 kg, and the engine must never add the two. The increments are what the
 * equipment physically offers — a pair of 1 kg plates on a barbell, the next
 * dumbbell on the rack, the next pin on a stack — so stepping the editor lands
 * on a load that exists rather than on an arithmetic one.
 */
const EQUIPMENT_LOAD: Record<
  string,
  { basis: "total" | "per_implement"; incrementKg: number }
> = {
  dumbbell: { basis: "per_implement", incrementKg: 2 },
  kettlebell: { basis: "per_implement", incrementKg: 4 },
  barbell: { basis: "total", incrementKg: 2.5 },
  "olympic barbell": { basis: "total", incrementKg: 2.5 },
  "ez barbell": { basis: "total", incrementKg: 2.5 },
  "trap bar": { basis: "total", incrementKg: 2.5 },
  "smith machine": { basis: "total", incrementKg: 2.5 },
  cable: { basis: "total", incrementKg: 5 },
  "leverage machine": { basis: "total", incrementKg: 5 },
  "sled machine": { basis: "total", incrementKg: 5 },
  "upper body ergometer": { basis: "total", incrementKg: 5 },
  assisted: { basis: "total", incrementKg: 5 },
  weighted: { basis: "total", incrementKg: 1.25 },
  "medicine ball": { basis: "total", incrementKg: 1 },
  "stability ball": { basis: "total", incrementKg: 1 },
  "bosu ball": { basis: "total", incrementKg: 1 },
  "wheel roller": { basis: "total", incrementKg: 1 },
  hammer: { basis: "total", incrementKg: 1 },
  tire: { basis: "total", incrementKg: 5 },
  rope: { basis: "total", incrementKg: 1 },
}

/** Equipment that carries no load of its own. Weight added to one of these —
 *  a belt on a dip, a vest on a push-up — is added load, not the station. */
const ADDED_LOAD_STATION = "added load"

/** Assistance is its own measurement, never a negative load. */
const ASSISTANCE_STATION = "assistance"

const DEFAULT_LOAD = { basis: "total", incrementKg: 2.5 } as const

export function equipmentLoadSpec(equipment: string) {
  const spec = EQUIPMENT_LOAD[equipment]
  return spec ? { ...spec } : null
}

const metadataCache = new Map<string, ExerciseMetadata>()

/** Catalogue metadata for one exercise, without paying for the whole engine
 *  index: the set editor only ever asks about the handful of exercises in the
 *  workout on screen. */
export function exerciseMetadata(exercise: ExerciseSummary): ExerciseMetadata {
  const cached = metadataCache.get(exercise.id)
  if (cached) return cached
  const resolved = resolveExerciseMetadata(exercise)
  metadataCache.set(exercise.id, resolved)
  return resolved
}

export function exerciseMetadataById(exerciseId: string) {
  const exercise = EXERCISES_BY_ID.get(exerciseId)
  return exercise ? exerciseMetadata(exercise) : null
}

/**
 * The resistance shapes this exercise can be logged in, best first.
 *
 * Most exercises have exactly one, and the editor then shows no choice at all.
 * The ones that have more are the body-weight movements: a pull-up is body
 * weight, a weighted pull-up is added load, and an assisted pull-up is
 * assistance — three different measurements of the same movement that
 * progression must never confuse for one another.
 */
export function resistanceModes(exercise: ExerciseSummary): ResistanceMode[] {
  const { tracking } = exerciseMetadata(exercise)
  if (tracking === "assistance")
    return ["assistance", "bodyweight", "external_load"]
  if (tracking === "bodyweight")
    return ["bodyweight", "external_load", "assistance"]
  if (tracking === "band_resistance") return ["band_resistance"]
  if (tracking === "external_load") return ["external_load"]
  // repetition_only, timed, distance and unknown carry no load claim of their
  // own, so the equipment decides: a dumbbell exercise is loaded whatever the
  // catalogue failed to say about it.
  if (exercise.equipment === "band" || exercise.equipment === "resistance band")
    return ["band_resistance"]
  return EQUIPMENT_LOAD[exercise.equipment]
    ? ["external_load"]
    : ["bodyweight", "external_load"]
}

/** Whether a mode carries kilograms at all. Body weight and bands do not: the
 *  app has no scale for a band, and inventing one would be fabricated
 *  evidence. */
export function isMeasuredInKg(mode: ResistanceMode) {
  return mode === "external_load" || mode === "assistance"
}

/**
 * Where the kilograms are measured and in what steps.
 *
 * A saved load configuration wins whenever the person has made one: it names a
 * real station in a real gym, which is exactly the comparability the engine
 * asks for. Without one, the equipment family stands in — stable for the same
 * exercise across sessions, and never shared between a dumbbell press and a
 * machine press.
 */
export function loadContextFor(
  exercise: ExerciseSummary,
  mode: ResistanceMode,
  configuration?: PersistedLoadConfiguration,
  equipmentIncrementKg?: number
): LoadContext {
  const equipment = EQUIPMENT_LOAD[exercise.equipment] ?? DEFAULT_LOAD
  const incrementKg =
    typeof equipmentIncrementKg === "number" &&
    Number.isFinite(equipmentIncrementKg) &&
    equipmentIncrementKg > 0
      ? equipmentIncrementKg
      : equipment.incrementKg
  if (configuration && mode === "external_load")
    return {
      stationId: configuration.stationId,
      basis: configuration.basis,
      grid: structuredClone(configuration.grid),
    }
  if (mode === "assistance")
    return {
      stationId:
        exercise.equipment === "assisted"
          ? exercise.equipment
          : ASSISTANCE_STATION,
      basis: "total",
      grid: {
        incrementKg:
          exercise.equipment === "assisted"
            ? incrementKg
            : EQUIPMENT_LOAD.assisted.incrementKg,
        minimumKg: 0,
      },
    }
  return {
    stationId: EQUIPMENT_LOAD[exercise.equipment]
      ? exercise.equipment
      : ADDED_LOAD_STATION,
    basis: equipment.basis,
    grid: { incrementKg, minimumKg: 0 },
  }
}

/** One step up or down the loads the station actually offers. */
export function stepLoad(kg: number, direction: 1 | -1, grid: LoadGrid) {
  const target =
    "availableLoadsKg" in grid
      ? kg + direction * 0.001
      : kg + direction * grid.incrementKg
  const snapped = roundLoad(
    Math.max(0, target),
    grid,
    direction === 1 ? "up" : "down"
  )
  return Math.max(0, snapped ?? kg)
}

export function makeResistance(
  mode: ResistanceMode,
  kg: number,
  context: LoadContext
): PersistedResistance {
  if (mode === "external_load" || mode === "assistance")
    return {
      type: mode,
      kg,
      basis: context.basis,
      stationId: context.stationId,
    }
  return { type: mode }
}

/** Kilograms as a gym writes them: 80, 82.5, 1.25 — never 82.50. */
export function formatKg(kg: number) {
  return Number(kg.toFixed(2)).toString()
}

const MODE_LABELS: Record<ResistanceMode, string> = {
  external_load: "Load",
  assistance: "Assist",
  bodyweight: "Body weight",
  band_resistance: "Band",
  unknown: "Unrecorded",
}

export function resistanceModeLabel(mode: ResistanceMode) {
  return MODE_LABELS[mode]
}

/** The one-line reading of a performed set's resistance. "each" is load-bearing
 *  wording, not decoration: it is the difference between two 30 kg dumbbells
 *  and a 30 kg bar. */
export function formatResistance(resistance: PersistedResistance) {
  if (resistance.type === "external_load" || resistance.type === "assistance") {
    const value = `${formatKg(resistance.kg)} kg`
    if (resistance.type === "assistance") return `${value} assist`
    return resistance.basis === "per_implement" ? `${value} each` : value
  }
  if (resistance.type === "bodyweight") return "Body weight"
  if (resistance.type === "band_resistance") return "Band"
  return "—"
}

/** Sides worth offering. Paired limbs stay `both` — the engine counts three
 *  sets each side as three records — so only a genuinely one-sided movement
 *  needs the choice. */
export function sideOptions(exercise: ExerciseSummary): SetSide[] {
  const { laterality } = exerciseMetadata(exercise)
  return laterality === "unilateral" ? ["both", "left", "right"] : ["both"]
}
