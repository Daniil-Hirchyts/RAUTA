import { useFilters } from "@/store/use-filters"
import { useSettings } from "@/store/use-settings"
import {
  useTrainingProfile,
  type TrainingProfile,
} from "@/store/use-training-profile"
import type { PlanningPreferences, UserTrainingProfile } from "@/training"

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
  overrides: Partial<PlanningPreferences> = {}
): PlanningPreferences {
  const preferred = profile.preferredSessionDurationMinutes
  return {
    goal: profile.goal,
    availableEquipment: toEngineEquipment(equipment),
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
  const { gymEquipment } = useFilters.getState()

  return {
    profile: buildTrainingEngineProfile(profile, {
      bodyWeightKg: appleHealthEnabled ? healthBodyWeightKg : null,
    }),
    preferences: buildTrainingPlanningPreferences(
      profile,
      gymEquipment,
      overrides
    ),
  }
}
