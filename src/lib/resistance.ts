import { EXERCISES_BY_ID } from "@/lib/exercises"
import { titleCase } from "@/lib/text"
import { resolveExerciseMetadata, roundLoad } from "@/training"
import type { ExerciseMetadata, LoadGrid } from "@/training"
import type {
  PersistedCompletedSet,
  PersistedLoadConfiguration,
  PersistedResistance,
  PersistedTrainingSettings,
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
/** The modes that carry kilograms, and so a station and a grid. */
export type MeasuredMode = Extract<
  ResistanceMode,
  "external_load" | "assistance"
>
export type SetSide = PersistedCompletedSet["side"]

/** Station and basis a set is measured against, plus the steps its load moves
 *  in. The engine compares kilograms only within one station and basis, so
 *  every logged set has to carry both. */
export type LoadContext = {
  stationId: string
  basis: "total" | "per_implement"
  grid: LoadGrid
}

/** One station a set can be logged against, as the editor offers it. */
export type StationChoice = {
  /** The saved configuration, or null for the equipment default. */
  id: string | null
  label: string
  context: LoadContext
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

/** The measurement a saved station describes. A configuration written before
 *  assisted machines could be described is an external-load station, which is
 *  what every one of them was. */
export function configurationMode(
  configuration: PersistedLoadConfiguration
): ResistanceMode {
  return configuration.mode ?? "external_load"
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
  // A station describes one measurement. An assisted machine and a loaded bar
  // can both be saved against the same exercise, and neither may stand in for
  // the other: the configuration applies only to the mode it was made in.
  if (configuration && configurationMode(configuration) === mode)
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

/** The lightest load this station has: where a dial that has nothing to go on
 *  starts once somebody asks it for a number. */
export function firstLoad(grid: LoadGrid) {
  if ("availableLoadsKg" in grid)
    return Math.min(...grid.availableLoadsKg.filter(Number.isFinite))
  return Math.max(0, grid.minimumKg ?? 0)
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

/** Whether a station this app minted belongs to a piece of equipment. Ids from
 *  a backup, or written by hand, name themselves and are shown as written. */
function isDerivedStationId(stationId: string, defaultStationId: string) {
  const suffix = stationId.startsWith(`${defaultStationId}#`)
    ? stationId.slice(defaultStationId.length + 1)
    : stationId.startsWith(`${defaultStationId}-`)
      ? stationId.slice(defaultStationId.length + 1)
      : null
  return suffix !== null && suffix.length > 0
}

/**
 * What to call a station on screen.
 *
 * A number, not an identity. Kilograms are compared by `stationId`, which is
 * minted once and never reused; what a person reads is simply which of their
 * stations this is, counted in the order they described them. So deleting the
 * second of three renumbers what they see and changes nothing about what
 * compares to what.
 */
export function stationLabel(
  stationId: string,
  defaultStationId: string,
  /** Position among the exercise's stations, the default being the first. */
  ordinal?: number
) {
  if (stationId === defaultStationId) return titleCase(defaultStationId)
  if (!isDerivedStationId(stationId, defaultStationId))
    return titleCase(stationId)
  return ordinal === undefined
    ? // A station nothing describes any more: sets logged at it are still its
      // own, and must never read as one of the stations that still exist.
      `Earlier ${defaultStationId}`
    : `${titleCase(defaultStationId)} ${ordinal}`
}

/**
 * A station identity that will never be handed out twice.
 *
 * The number in a station's name is a label, and labels are reused the moment
 * one is deleted. Its identity cannot be: kilograms logged at a machine that no
 * longer exists must never turn out to be comparable with a different machine
 * described later, so what history is keyed by is minted once here and kept
 * apart from anything a person sees.
 */
export function newStationId(defaultStationId: string) {
  const unique =
    globalThis.crypto?.randomUUID?.().replace(/-/g, "").slice(0, 12) ??
    `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`
  return `${defaultStationId}#${unique}`
}

/**
 * The stations saved for one exercise in one measurement, plus the equipment
 * default they sit above.
 *
 * The default is always offered and always first: a person who has never named
 * a machine still logs against a stable station, and the ones they did name are
 * additions to that rather than a replacement vocabulary.
 */
export function stationChoicesFor(
  exercise: ExerciseSummary,
  mode: ResistanceMode,
  settings: Pick<PersistedTrainingSettings, "loadConfigurations">,
  equipmentIncrementKg?: number
): StationChoice[] {
  const fallback = loadContextFor(
    exercise,
    mode,
    undefined,
    equipmentIncrementKg
  )
  const choices: StationChoice[] = [
    { id: null, label: titleCase(fallback.stationId), context: fallback },
  ]
  for (const configuration of settings.loadConfigurations) {
    if (
      configuration.exerciseId !== exercise.id ||
      configurationMode(configuration) !== mode
    )
      continue
    const context = loadContextFor(
      exercise,
      mode,
      configuration,
      equipmentIncrementKg
    )
    // A configuration on the default station is that station described
    // properly — a stack that starts at 5 rather than 0 — not a second one.
    if (configuration.stationId === fallback.stationId)
      choices[0] = { ...choices[0], id: configuration.id, context }
    else
      choices.push({
        id: configuration.id,
        // Counted from where it sits in the list, so the names read 1, 2, 3
        // however many have come and gone.
        label: stationLabel(
          configuration.stationId,
          fallback.stationId,
          choices.length + 1
        ),
        context,
      })
  }
  return choices
}

/**
 * Where a set that has already been logged was measured.
 *
 * The observation itself names the station and the basis — that is the record —
 * and only the steps it moves in have to be looked up. A station nobody
 * describes any more still steps: it falls back to the equipment's own grid so
 * an old set can be read and corrected, rather than becoming uneditable
 * because its machine was deleted from the settings.
 */
export function recordedLoadContext(
  exercise: ExerciseSummary,
  resistance: PersistedResistance,
  settings: Pick<PersistedTrainingSettings, "loadConfigurations">,
  equipmentIncrementKg?: number
): LoadContext {
  const fallback = loadContextFor(
    exercise,
    resistance.type,
    undefined,
    equipmentIncrementKg
  )
  if (!("kg" in resistance)) return fallback
  const configuration = settings.loadConfigurations.find(
    (item) =>
      item.exerciseId === exercise.id &&
      configurationMode(item) === resistance.type &&
      item.stationId === resistance.stationId &&
      item.basis === resistance.basis
  )
  return {
    stationId: resistance.stationId,
    basis: resistance.basis,
    grid: configuration ? structuredClone(configuration.grid) : fallback.grid,
  }
}

/** Whether two measurements can be compared: the same machine, held the same
 *  way. Kilograms mean nothing across this line. */
export function sameLoadContext(
  left: Pick<LoadContext, "stationId" | "basis">,
  right: Pick<LoadContext, "stationId" | "basis">
) {
  return left.stationId === right.stationId && left.basis === right.basis
}

/**
 * The load to open the editor on, or null when there is nothing honest to
 * offer.
 *
 * A kilogram is only carried over when it was measured at the same station, in
 * the same basis, as the set about to be logged, and when it is a load this
 * station actually offers. Anything else — another machine, another
 * measurement, a grid that has changed — leaves the dial unset rather than
 * putting up a number nobody lifted.
 */
export function carryOverLoad(
  resistance: PersistedResistance | undefined,
  mode: ResistanceMode,
  context: LoadContext
): number | null {
  if (!resistance || resistance.type !== mode || !("kg" in resistance))
    return null
  if (!sameLoadContext(resistance, context)) return null
  const rounded = roundLoad(resistance.kg, context.grid)
  return rounded ?? null
}

/**
 * The station this exercise is currently trained at, or null for the equipment
 * default.
 *
 * A selection that no longer names a saved station in this measurement is not
 * an error and not a guess — it simply falls back to the default, which is what
 * every exercise nobody has configured uses anyway.
 */
export function activeConfigurationFor(
  exerciseId: string,
  mode: ResistanceMode,
  settings: Pick<
    PersistedTrainingSettings,
    "loadConfigurations" | "activeLoadConfigurations"
  >
): PersistedLoadConfiguration | null {
  const selectedId = settings.activeLoadConfigurations?.[exerciseId]
  const forExercise = settings.loadConfigurations.filter(
    (configuration) =>
      configuration.exerciseId === exerciseId &&
      configurationMode(configuration) === mode
  )
  // A selection names one station in one measurement. Anywhere it does not
  // apply — the other measurement, or a station since deleted — the rule is the
  // one that governs every exercise nobody has chosen for: a single saved
  // station is that exercise's station, and anything more waits to be told.
  const selected = selectedId
    ? forExercise.find((item) => item.id === selectedId)
    : undefined
  if (selected) return selected
  return forExercise.length === 1 ? forExercise[0] : null
}

/** The station and grid a set of this exercise is measured against right now. */
export function resolveLoadContext(
  exercise: ExerciseSummary,
  mode: ResistanceMode,
  settings: Pick<
    PersistedTrainingSettings,
    "loadConfigurations" | "activeLoadConfigurations"
  >,
  equipmentIncrementKg?: number
): LoadContext {
  return loadContextFor(
    exercise,
    mode,
    activeConfigurationFor(exercise.id, mode, settings) ?? undefined,
    equipmentIncrementKg
  )
}
