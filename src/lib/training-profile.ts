import { DEFAULT_POLICY } from "@/training"
import type {
  Experience,
  PlanningPreferences,
  TrainingGoal,
  UserTrainingProfile,
} from "@/training"

/**
 * The vocabulary the profile screens speak, taken from the engine rather than
 * restated next to it: the domain decides which goals, experience levels,
 * priority levels and health limitations exist, and this file only says how
 * each one is worded for a person.
 */

/** `planningEligibility` refuses `power`, and the policy carries no volume or
 *  rep guidance for it, so it is not a goal the profile can hold. */
export type SupportedTrainingGoal = Exclude<TrainingGoal, "power">

export type MusclePriorityLevel = NonNullable<
  PlanningPreferences["priorityMuscles"]
>[number]["level"]

export type HealthLimitation = Extract<
  UserTrainingProfile["health"],
  { status: "unsupported" }
>["reasons"][number]

type Choice = { title: string; description: string }

/** Keying by the engine's own union is what keeps these exhaustive: a goal or
 *  a level added to the domain fails to compile until it is worded here. */
export const GOAL_CHOICES: Record<SupportedTrainingGoal, Choice> = {
  hypertrophy: {
    title: "Build muscle",
    description: "Moderate reps, more weekly volume",
  },
  strength: {
    title: "Get stronger",
    description: "Heavier sets, longer rests",
  },
  strength_hypertrophy: {
    title: "Strength & size",
    description: "A mix of both",
  },
  general_fitness: {
    title: "General fitness",
    description: "Balanced, easier to keep up",
  },
  fat_loss_support: {
    title: "Support fat loss",
    description: "Keep muscle while eating less",
  },
  muscular_endurance: {
    title: "Muscular endurance",
    description: "Higher reps, shorter rests",
  },
}

export const EXPERIENCE_CHOICES: Record<Experience, Choice> = {
  beginner: {
    title: "Beginner",
    description: "New to lifting, or back after a long break",
  },
  intermediate: {
    title: "Intermediate",
    description: "Training regularly for a year or so",
  },
  advanced: {
    title: "Advanced",
    description: "Years of consistent, structured training",
  },
}

export const HEALTH_LIMITATION_LABELS: Record<HealthLimitation, string> = {
  active_injury: "Injury I am training around",
  rehabilitation: "In rehabilitation",
  medical_condition: "A relevant medical condition",
  pregnancy: "Pregnant or postpartum",
  other: "Something else",
}

export const PRIORITY_LEVEL_LABELS: Record<MusclePriorityLevel, string> = {
  low: "Less",
  normal: "Normal",
  high: "More",
  specialization: "Focus",
}

/** Declaration order above is the presentation order; the policy decides which
 *  of those goals the planner can actually carry. */
export const SUPPORTED_GOALS = (
  Object.keys(GOAL_CHOICES) as SupportedTrainingGoal[]
).filter((goal) => goal in DEFAULT_POLICY.goals)

export const EXPERIENCE_LEVELS = Object.keys(EXPERIENCE_CHOICES) as Experience[]

export const HEALTH_LIMITATIONS = Object.keys(
  HEALTH_LIMITATION_LABELS
) as HealthLimitation[]

/** Ordered by how much weekly volume each level asks for, so the chips read
 *  left to right the way the engine weights them. */
export const PRIORITY_LEVELS = (
  Object.keys(DEFAULT_POLICY.priorityMultipliers) as MusclePriorityLevel[]
).sort(
  (left, right) =>
    DEFAULT_POLICY.priorityMultipliers[left] -
    DEFAULT_POLICY.priorityMultipliers[right]
)

/** `normal` is what an unlisted muscle already gets, so the picker only ever
 *  offers the levels that actually change something. */
export const SELECTABLE_PRIORITY_LEVELS = PRIORITY_LEVELS.filter(
  (level) => level !== "normal"
)

/** A prioritised muscle is worth singling out, so the first tap asks for more
 *  of it; tapping the same muscle again walks the rest of the scale and then
 *  hands it back to the engine's normal weighting. */
const PRIORITY_CYCLE: (MusclePriorityLevel | null)[] = [
  "high",
  "specialization",
  "low",
  null,
]

export function nextPriorityLevel(current: MusclePriorityLevel | null) {
  const index = PRIORITY_CYCLE.indexOf(current)
  return PRIORITY_CYCLE[(index + 1) % PRIORITY_CYCLE.length]
}

/** The palest a prioritised muscle is ever drawn. Below this the figure reads
 *  as unpainted rather than as trained less. */
const MIN_PAINT = 0.42

/** How strongly each level paints on the body map, spread across the engine's
 *  own multipliers so the map darkens in the same order the planner weights.
 *  The colour is the control's only readout, so it has to carry the level. */
export const PRIORITY_PAINT_WEIGHTS = Object.fromEntries(
  PRIORITY_LEVELS.map((level) => {
    const multipliers = PRIORITY_LEVELS.map(
      (item) => DEFAULT_POLICY.priorityMultipliers[item]
    )
    const lowest = Math.min(...multipliers)
    const spread = Math.max(...multipliers) - lowest || 1
    const share = (DEFAULT_POLICY.priorityMultipliers[level] - lowest) / spread
    return [level, Number((MIN_PAINT + (1 - MIN_PAINT) * share).toFixed(3))]
  })
) as Record<MusclePriorityLevel, number>

/** The dial starts where the planner does: `planningEligibility` refuses
 *  under-18s, and the request validator accepts an age up to 120. */
export const PROFILE_AGE = { min: 18, max: 75, step: 1 } as const
/** What the age dial paints, as opposed to what it accepts: a life read
 *  against a round scale, with the years the app will not train greyed out at
 *  either end rather than absent. */
export const PROFILE_AGE_SCALE = { min: 0, max: 100 } as const

/** Whole five-minute steps across the range a single session realistically
 *  runs; the engine validates 1–300 minutes. */
export const SESSION_DURATION = { min: 20, max: 120, step: 5 } as const
/** What the session dial paints: the quarter hour either side of what the
 *  app will plan, greyed out, so the two ends read as limits it has rather
 *  than as the scale simply stopping. */
export const SESSION_DURATION_SCALE = { min: 0, max: 140 } as const

const GOAL_SET = new Set<string>(SUPPORTED_GOALS)
const EXPERIENCE_SET = new Set<string>(EXPERIENCE_LEVELS)
const LIMITATION_SET = new Set<string>(HEALTH_LIMITATIONS)
const PRIORITY_SET = new Set<string>(PRIORITY_LEVELS)

export function isSupportedGoal(
  value: unknown
): value is SupportedTrainingGoal {
  return typeof value === "string" && GOAL_SET.has(value)
}

export function isExperience(value: unknown): value is Experience {
  return typeof value === "string" && EXPERIENCE_SET.has(value)
}

export function isHealthLimitation(value: unknown): value is HealthLimitation {
  return typeof value === "string" && LIMITATION_SET.has(value)
}

export function isPriorityLevel(value: unknown): value is MusclePriorityLevel {
  return typeof value === "string" && PRIORITY_SET.has(value)
}

export function goalLabel(goal: SupportedTrainingGoal) {
  return GOAL_CHOICES[goal].title
}

export function experienceLabel(experience: Experience) {
  return EXPERIENCE_CHOICES[experience].title
}
