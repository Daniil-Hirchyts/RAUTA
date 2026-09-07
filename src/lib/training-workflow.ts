import { EXERCISES, EQUIPMENT_OPTIONS } from "@/lib/exercises"
import { buildTrainingEngineInputs } from "@/lib/training-engine-adapter"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts, type Workout } from "@/store/use-workouts"
import { toEngineLoadPreferences } from "@/training-persistence/history"
import {
  isSupersededPlannedSession,
  toEngineProgramSnapshot,
} from "@/training-persistence/program"
import {
  adaptTrainingProgram,
  createExerciseIndex,
  findExerciseSubstitutions,
  generateTrainingProgram,
  recommendProgression,
  DEFAULT_POLICY,
} from "@/training"
import type {
  PlanningPreferences,
  ProgramGenerationRequest,
  UserTrainingProfile,
} from "@/training"
import type {
  PersistedActiveExerciseDraft,
  PersistedProgramRecord,
  PersistedTrainingStateLatest,
} from "@/training-persistence/schema"

let index: ReturnType<typeof createExerciseIndex> | undefined
export const trainingIndex = () => (index ??= createExerciseIndex(EXERCISES))
export const planningEquipment = [
  ...EQUIPMENT_OPTIONS,
  "bench",
  "rack",
  "pull-up bar",
  "low bar",
  "chair",
  "step",
  "band anchor",
  "towel",
  "suspension straps",
]
/** Engine input, already translated. Callers get it from the saved profile
 *  through `buildTrainingEngineInputs`; nothing here re-asks the user. */
export type PlanSetup = {
  profile: UserTrainingProfile
  preferences: PlanningPreferences
}

/** Mon–Sun as offsets from the week the engine is asked to plan. The only
 *  genuinely week-specific answer the profile cannot already give. */
export const DEFAULT_TRAINING_DAYS: readonly number[] = [0, 2, 4]

/** The source week's own untouched future slots, shared by eligibility and
 * the engine request. Even a set-less application completion reserves its slot. */
export function remainingTrainingSlots(
  source: PersistedProgramRecord,
  now: string,
  data: PersistedTrainingStateLatest = useTrainingRecords.getState().data,
  workouts: readonly Workout[] = useWorkouts.getState().workouts
) {
  const week = source.snapshot.weeks.find(
    (item) => Date.parse(now) < Date.parse(item.start) + 7 * 86400000
  )
  const sessions =
    week?.sessions.filter(
      (session) =>
        Date.parse(session.scheduledAt) > Date.parse(now) &&
        !isSupersededPlannedSession(data, source.id, session.id) &&
        !data.sessions.some(
          (actual) => actual.plannedSessionId === session.id
        ) &&
        !workouts.some(
          (workout) =>
            workout.completion &&
            workout.planned?.programId === source.id &&
            workout.planned.sessionId === session.id
        )
    ) ?? []
  return { week, sessions }
}

export function buildTrainingRequest(
  setup: PlanSetup,
  now: string,
  source?: PersistedProgramRecord,
  /** Which days of the coming week can be trained. Ignored when revising an
   *  existing week: that week's own remaining slots decide. */
  availableDays: readonly number[] = DEFAULT_TRAINING_DAYS
): ProgramGenerationRequest {
  const store = useTrainingRecords.getState()
  const monday = new Date(now)
  monday.setUTCHours(0, 0, 0, 0)
  monday.setUTCDate(monday.getUTCDate() + ((8 - monday.getUTCDay()) % 7))
  // A new plan starts on the next Monday, including today when generated before its slots.
  if (monday.getTime() <= Date.parse(now))
    monday.setUTCDate(monday.getUTCDate() + 7)
  const remaining = source ? remainingTrainingSlots(source, now) : undefined
  const sourceWeek = remaining?.week
  const selectedContexts = store.data.settings.loadConfigurations.filter(
    (c, _, all) =>
      all.filter((other) => other.exerciseId === c.exerciseId).length === 1
  )
  return {
    profile: setup.profile,
    preferences: {
      ...setup.preferences,
      ...toEngineLoadPreferences(
        store.data.settings,
        selectedContexts.map((c) => c.id)
      ),
    },
    schedule: {
      weekStart: sourceWeek?.start ?? monday.toISOString(),
      days: source
        ? [
            ...new Set(
              (remaining?.sessions ?? []).map((s) =>
                Math.floor(
                  (Date.parse(s.scheduledAt) - Date.parse(sourceWeek!.start)) /
                    86400000
                )
              )
            ),
          ].sort((a, b) => a - b)
        : [...new Set(availableDays)].sort((a, b) => a - b),
      durationWeeks: 1,
    },
    history: store.getTrainingHistory(),
    exercises: EXERCISES,
    now,
    ...(source
      ? { policy: toEngineProgramSnapshot(source.snapshot).policy }
      : {}),
  }
}

/**
 * Asks the engine for a week and hands back exactly what it said, refusals
 * included. Nothing is persisted here: a caller that wants to show the
 * engine's own diagnostics needs the structured result, not an exception.
 */
export function planTrainingWeek(
  setup: PlanSetup = buildTrainingEngineInputs(),
  now = new Date().toISOString(),
  source?: PersistedProgramRecord,
  availableDays: readonly number[] = DEFAULT_TRAINING_DAYS
) {
  const request = buildTrainingRequest(setup, now, source, availableDays)
  if (!request.schedule.days.length)
    throw new Error(
      "There are no future sessions left in this week. Create a new training week instead."
    )
  const result = source
    ? adaptTrainingProgram({
        previousProgram: toEngineProgramSnapshot(source.snapshot),
        request,
        mode: "remaining_week",
      })
    : generateTrainingProgram(request)
  return { request, result }
}

export function generateAndSavePlan(
  setup: PlanSetup = buildTrainingEngineInputs(),
  now = new Date().toISOString(),
  source?: PersistedProgramRecord,
  availableDays: readonly number[] = DEFAULT_TRAINING_DAYS
) {
  const { request, result } = planTrainingWeek(
    setup,
    now,
    source,
    availableDays
  )
  if (!("program" in result))
    throw new Error(
      `No plan could be created (${result.status}). Check available equipment and future training days.`
    )
  useTrainingRecords.getState().saveProgram(result.program)
  return { result, request }
}

export function replacementIds(exerciseId: string): string[] {
  const store = useTrainingRecords.getState()
  const activeProgramId = store.data.activeWorkout?.plannedProgramId
  const source = activeProgramId
    ? store.data.programs.find((program) => program.id === activeProgramId)
    : undefined
  const availableEquipment = source
    ? [
        ...new Set([
          "body weight",
          ...source.snapshot.weeks.flatMap((week) =>
            week.sessions.flatMap((session) =>
              session.exercises.flatMap(
                (planned) =>
                  trainingIndex().byId.get(planned.exerciseId)?.metadata
                    .requiredEquipment ?? []
              )
            )
          ),
        ]),
      ]
    : planningEquipment
  const request = buildTrainingRequest(
    buildTrainingEngineInputs({
      availableEquipment,
      // A swap stays inside the plan it belongs to; the profile's current goal
      // must not quietly re-rank alternatives for an older program.
      ...(source ? { goal: source.snapshot.goal } : {}),
    }),
    new Date().toISOString(),
    source
  )
  return findExerciseSubstitutions(exerciseId, request, 100, {
    index: trainingIndex(),
  }).map((item) => item.exerciseId)
}

export function nextPerformance(
  exercise: PersistedActiveExerciseDraft,
  now = new Date().toISOString()
) {
  const store = useTrainingRecords.getState()
  const indexed = trainingIndex().byId.get(exercise.exerciseId)
  if (!indexed) return null
  const target = exercise.sets.find((s) => s.setType === "working")?.target
  const latest = store
    .getTrainingHistory()
    .sessions.toReversed()
    .flatMap((s) => s.exercises)
    .find((e) => e.exerciseId === exercise.exerciseId)
    ?.sets.at(-1)?.resistance
  const config = store.data.settings.loadConfigurations.find(
    (c) =>
      c.exerciseId === exercise.exerciseId &&
      latest &&
      "stationId" in latest &&
      c.stationId === latest.stationId &&
      c.basis === latest.basis
  )
  return recommendProgression({
    exercise: indexed,
    history: store.getTrainingHistory(),
    now,
    reps: target?.reps ?? { min: 8, max: 12 },
    rir: target?.rir ?? 2,
    requiredSets: Math.max(
      1,
      exercise.sets.filter((s) => s.setType === "working").length
    ),
    policy: DEFAULT_POLICY,
    loadGrid: config?.grid,
    loadContext: config
      ? { stationId: config.stationId, basis: config.basis }
      : undefined,
  })
}
