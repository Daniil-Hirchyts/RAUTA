import { EXERCISES } from "@/lib/exercises"
import { loadContextFor, resistanceModes } from "@/lib/resistance"
import { useFilters } from "@/store/use-filters"
import { useSettings } from "@/store/use-settings"
import { useTrainingRecords } from "@/store/use-training-records"
import {
  useTrainingProfile,
  type TrainingProfile,
} from "@/store/use-training-profile"
import type { PlanningPreferences, UserTrainingProfile } from "@/training"
import type { PersistedLoadConfiguration } from "@/training-persistence/schema"

/**
 * The one boundary between RAUTA and the deterministic training engine.
 *
 * Everything above it is application state a person edits — a profile, an
 * equipment selection, an Apple Health reading. Everything below it is the
 * engine's canonical request vocabulary. The dependency only ever points this
 * way: nothing in `src/training` knows this file exists.
 */

/**
 * Catalogue accessories are the fixtures equipment stands on rather than
 * things worth asking about: curated metadata pairs "bench" with dumbbells,
 * "rack" with barbells, "band anchor" with bands. The profile keeps asking one
 * question — which equipment do you have — and the adapter grants the fixtures
 * that equipment implies.
 *
 * Derived from `requiredEquipment` across the frozen catalogue, then narrowed
 * by hand: a pairing is listed only where having the equipment without the
 * fixture would be unusual. Accessories nobody can assume — a pull-up bar for
 * someone training with body weight alone, rings, a partner — are deliberately
 * absent, so those exercises stay out of an automatic plan rather than being
 * prescribed to a room that cannot run them.
 */
const IMPLIED_ACCESSORIES: Record<string, readonly string[]> = {
  assisted: ["dip station", "pull-up bar", "band anchor", "towel"],
  band: ["band anchor", "bench", "chair", "step"],
  barbell: ["bench", "rack", "step"],
  "body weight": ["chair", "wall", "step", "towel", "support"],
  "bosu ball": ["chair"],
  cable: [
    "bench",
    "rope attachment",
    "straight-bar attachment",
    "v-bar attachment",
    "arm blaster",
  ],
  dumbbell: ["bench", "step", "arm blaster", "support"],
  "ez barbell": ["bench", "arm blaster"],
  kettlebell: ["bench", "step"],
  "leverage machine": [
    "bench",
    "dip station",
    "pull-up bar",
    "step",
    "v-bar attachment",
  ],
  "medicine ball": ["bench", "wall"],
  "olympic barbell": ["bench", "rack"],
  "resistance band": ["band anchor", "bench", "chair"],
  rope: ["step", "wall"],
  "sled machine": ["step"],
  "smith machine": ["bench", "rack", "step"],
  "stability ball": ["bench", "wall", "dip station"],
  "trap bar": ["rack"],
  weighted: ["bench", "pull-up bar", "dip station", "step", "wall"],
}

/** Nobody has to own their own body, and the engine already treats body weight
 *  as always available. It is what a profile with nothing selected falls back
 *  to, so a plan can still be asked for. */
const IMPLICIT_EQUIPMENT = "body weight"

/** The profile stores what a session should aim for; the engine also wants the
 *  ceiling it must not cross. A little slack keeps a plan feasible when the
 *  conservative duration estimate lands just over the target. */
export const SESSION_DURATION_HEADROOM_MINUTES = 10

/** Application equipment ids, plus the fixtures they stand on. */
export function toEngineEquipment(equipment: readonly string[]) {
  const selection = equipment.length ? equipment : [IMPLICIT_EQUIPMENT]
  return [
    ...new Set(
      selection.flatMap((item) => [item, ...(IMPLIED_ACCESSORIES[item] ?? [])])
    ),
  ]
}

/**
 * What a kilogram means on each piece of equipment the person can reach.
 *
 * Availability decides which exercises are feasible; this decides how the load
 * on them is measured. They are different questions and the engine asks both:
 * it compares kilograms only within one station and one basis, so a
 * prescription of 30 kg for a dumbbell press has to be per-implement — 30 in
 * each hand — and a prescription of 30 kg for a barbell press has to be total.
 * Without the context the two are the same number and the engine has no way to
 * tell them apart, which is exactly how "30 kg each" becomes "30 kg between
 * the pair" one week later.
 *
 * Nothing new is asked of anybody. The station, basis and increments come from
 * the same catalogue metadata and equipment table the set editor already uses
 * when a set is logged, so a planned load and a performed one are stated in
 * the same terms. An explicit load configuration the person has saved wins over
 * the table, which is what makes it worth saving.
 *
 * Scoped to the equipment actually selected: an exercise the planner cannot
 * prescribe needs no loading rule, and the map stays small.
 */
export function buildTrainingLoadPreferences(
  equipment: readonly string[],
  configurations: readonly PersistedLoadConfiguration[] = [],
  equipmentLoadIncrements: Readonly<Record<string, number>> = {}
): Pick<PlanningPreferences, "loadContexts" | "loadGrids"> {
  const available = new Set(toEngineEquipment(equipment))
  const loadContexts: NonNullable<PlanningPreferences["loadContexts"]> = {}
  const loadGrids: NonNullable<PlanningPreferences["loadGrids"]> = {}

  for (const exercise of EXERCISES) {
    if (!available.has(exercise.equipment)) continue
    // The shape the exercise is naturally logged in. Body weight and band
    // resistance carry no kilogram claim, so they get no station.
    const [mode] = resistanceModes(exercise)
    if (mode !== "external_load" && mode !== "assistance") continue
    const saved = configurations.find((item) => item.exerciseId === exercise.id)
    const context = loadContextFor(
      exercise,
      mode,
      saved,
      equipmentLoadIncrements[exercise.equipment]
    )
    loadContexts[exercise.id] = {
      stationId: context.stationId,
      basis: context.basis,
    }
    loadGrids[exercise.id] = context.grid
  }
  return { loadContexts, loadGrids }
}

export function buildTrainingEngineProfile(
  profile: TrainingProfile,
  options: { bodyWeightKg?: number | null } = {}
): UserTrainingProfile {
  return {
    age: profile.age,
    trainingExperience: profile.trainingExperience,
    health:
      profile.health.status === "healthy"
        ? { status: "healthy" }
        : { status: "unsupported", reasons: [...profile.health.reasons] },
    // Apple Health is the only source of body weight the app has, and it is
    // optional in both directions: absent here means the engine estimates.
    ...(typeof options.bodyWeightKg === "number"
      ? { bodyWeightKg: options.bodyWeightKg }
      : {}),
  }
}

export function buildTrainingPlanningPreferences(
  profile: TrainingProfile,
  equipment: readonly string[],
  overrides: Partial<PlanningPreferences> = {},
  configurations: readonly PersistedLoadConfiguration[] = [],
  equipmentLoadIncrements: Readonly<Record<string, number>> = {}
): PlanningPreferences {
  const preferred = profile.preferredSessionDurationMinutes
  return {
    goal: profile.goal,
    availableEquipment: toEngineEquipment(equipment),
    ...buildTrainingLoadPreferences(
      equipment,
      configurations,
      equipmentLoadIncrements
    ),
    preferredSessionDurationMinutes: preferred,
    maxSessionDurationMinutes: preferred + SESSION_DURATION_HEADROOM_MINUTES,
    ...(profile.priorityMuscles.length
      ? {
          priorityMuscles: profile.priorityMuscles.map((entry) => ({
            ...entry,
          })),
        }
      : {}),
    ...overrides,
  }
}

/**
 * The saved profile as engine input. Reading the stores happens here and only
 * here, so a planning caller never has to know which store holds what — and so
 * generating a week never has to ask for an age, a goal or an equipment list
 * that has already been answered.
 */
export function buildTrainingEngineInputs(
  overrides: Partial<PlanningPreferences> = {}
): { profile: UserTrainingProfile; preferences: PlanningPreferences } {
  const { profile } = useTrainingProfile.getState()
  const { appleHealthEnabled, healthBodyWeightKg } = useSettings.getState()
  const { gymEquipment, equipmentLoadIncrements } = useFilters.getState()
  const { loadConfigurations } = useTrainingRecords.getState().data.settings

  return {
    profile: buildTrainingEngineProfile(profile, {
      bodyWeightKg: appleHealthEnabled ? healthBodyWeightKg : null,
    }),
    preferences: buildTrainingPlanningPreferences(
      profile,
      gymEquipment,
      overrides,
      loadConfigurations,
      equipmentLoadIncrements
    ),
  }
}
