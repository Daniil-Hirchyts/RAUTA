import { EXERCISES, EXERCISES_BY_ID, EQUIPMENT_OPTIONS } from "@/lib/exercises"
import {
  activeConfigurationFor,
  loadContextFor,
  resistanceModes,
  resolveLoadContext,
  type ResistanceMode,
  type LoadContext,
} from "@/lib/resistance"
import { buildTrainingEngineInputs } from "@/lib/training-engine-adapter"
import { useFilters } from "@/store/use-filters"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts, type Workout } from "@/store/use-workouts"
import { toTrainingHistory } from "@/training-persistence/history"
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

export type TrainingAdaptationMode = "remaining_week" | "next_week"

/** The source week's own untouched future slots, shared by eligibility and
 * the engine request. Even a set-less application completion reserves its slot. */
export function remainingTrainingSlots(
  source: PersistedProgramRecord,
  now: string,
  data: PersistedTrainingStateLatest = useTrainingRecords.getState().data,
  workouts: readonly Workout[] = useWorkouts.getState().workouts
) {
  const remaining = (
    week: PersistedProgramRecord["snapshot"]["weeks"][number]
  ) =>
    week.sessions.filter(
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
    )
  const week = source.snapshot.weeks.find((week) => remaining(week).length > 0)
  const sessions = week ? remaining(week) : []

  return { week, sessions }
}

/**
 * Where every kilogram the engine may prescribe would be measured.
 *
 * The same resolution the set editor uses, asked of the whole catalogue: the
 * station and grid a set of this exercise would be logged against today. Two
 * layers, in this order — the station the person named for the exercise, and
 * otherwise the equipment family with whatever load step their gym actually
 * offers. Without this the engine has no grid to round to and prescribes
 * "calibrate" forever, however much real history exists.
 *
 * It states no load. It only says what a load would mean, which is the
 * condition the engine sets before it will name one.
 */
export function engineLoadPreferences(
  settings: PersistedTrainingStateLatest["settings"] = useTrainingRecords.getState()
    .data.settings,
  increments: Record<string, number> = useFilters.getState()
    .equipmentLoadIncrements
): Pick<PlanningPreferences, "loadContexts" | "loadGrids"> {
  const loadContexts: NonNullable<PlanningPreferences["loadContexts"]> = {}
  const loadGrids: NonNullable<PlanningPreferences["loadGrids"]> = {}
  const index = trainingIndex()
  for (const mode of ["external_load", "assistance"] as const)
    for (const indexed of index.byTracking.get(mode) ?? []) {
      const { exercise } = indexed
      const context = resolveLoadContext(
        exercise,
        mode,
        settings,
        increments[exercise.equipment]
      )
      loadContexts[exercise.id] = {
        stationId: context.stationId,
        basis: context.basis,
      }
      loadGrids[exercise.id] = structuredClone(context.grid)
    }
  return { loadContexts, loadGrids }
}

export function buildTrainingRequest(
  setup: PlanSetup,
  now: string,
  source?: PersistedProgramRecord,
  /** Which days of the coming week can be trained. A remaining-week revision
   *  keeps the source week's slots; next-week adaptation uses this selection. */
  availableDays: readonly number[] = DEFAULT_TRAINING_DAYS,
  adaptationMode: TrainingAdaptationMode = "remaining_week"
): ProgramGenerationRequest {
  const store = useTrainingRecords.getState()
  const monday = new Date(now)
  monday.setUTCHours(0, 0, 0, 0)
  monday.setUTCDate(monday.getUTCDate() + ((8 - monday.getUTCDay()) % 7))
  // A new plan starts on the next Monday, including today when generated before its slots.
  if (monday.getTime() <= Date.parse(now))
    monday.setUTCDate(monday.getUTCDate() + 7)
  const remaining =
    source && adaptationMode === "remaining_week"
      ? remainingTrainingSlots(source, now)
      : undefined
  const sourceWeek = remaining?.week
  return {
    profile: setup.profile,
    preferences: {
      ...setup.preferences,
      ...engineLoadPreferences(store.data.settings),
    },
    schedule: {
      weekStart: sourceWeek?.start ?? monday.toISOString(),
      days:
        source && adaptationMode === "remaining_week"
          ? [
              ...new Set(
                (remaining?.sessions ?? []).map((s) =>
                  Math.floor(
                    (Date.parse(s.scheduledAt) -
                      Date.parse(sourceWeek!.start)) /
                      86400000
                  )
                )
              ),
            ].sort((a, b) => a - b)
          : [...new Set(availableDays)].sort((a, b) => a - b),
      ...(remaining?.sessions.length &&
      new Set(remaining.sessions.map((s) => s.scheduledAt)).size !==
        remaining.sessions.length
        ? {
            sessionDays: remaining.sessions
              .map((s) =>
                Math.floor(
                  (Date.parse(s.scheduledAt) - Date.parse(sourceWeek!.start)) /
                    86400000
                )
              )
              .sort((a, b) => a - b),
          }
        : {}),
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
  availableDays: readonly number[] = DEFAULT_TRAINING_DAYS,
  adaptationMode: TrainingAdaptationMode = "remaining_week"
) {
  const request = buildTrainingRequest(
    setup,
    now,
    source,
    availableDays,
    adaptationMode
  )
  if (!request.schedule.days.length)
    throw new Error(
      "There are no future sessions left in this period. Create a new training plan instead."
    )
  const result = source
    ? adaptTrainingProgram({
        previousProgram: toEngineProgramSnapshot(source.snapshot),
        request,
        mode: adaptationMode,
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

export function replacementIds(
  exerciseId: string,
  workoutId?: string
): string[] {
  const records = useTrainingRecords.getState()
  const workout = useWorkouts
    .getState()
    .workouts.find((item) =>
      workoutId
        ? item.id === workoutId
        : item.id === records.data.activeWorkout?.sourceWorkoutId
    )
  const activeExercise = records.data.activeWorkout?.exercises.find(
    (item) => item.exerciseId === exerciseId
  )
  const sourceExerciseId = activeExercise?.plannedExerciseId ?? exerciseId
  const sourceProgram = workout?.planned
    ? records.data.programs.find(
        (item) => item.id === workout.planned?.programId
      )
    : undefined
  const request = buildTrainingRequest(
    buildTrainingEngineInputs(
      sourceProgram ? { goal: sourceProgram.snapshot.goal } : {}
    ),
    new Date().toISOString()
  )
  return [
    ...(sourceExerciseId !== exerciseId ? [sourceExerciseId] : []),
    ...findExerciseSubstitutions(sourceExerciseId, request, 100, {
      index: trainingIndex(),
      selectedExerciseIds: workout?.exerciseIds,
    }).map((item) => item.exerciseId),
  ]
}

export function nextPerformance(
  exercise: PersistedActiveExerciseDraft,
  now = new Date().toISOString(),
  /** The records to read. Passed explicitly by React callers so a memo can
   *  name every input it depends on; the live store otherwise. */
  data: PersistedTrainingStateLatest = useTrainingRecords.getState().data,
  increments: Record<string, number> = useFilters.getState()
    .equipmentLoadIncrements,
  /** The measurement being logged, when the editor is open on one. A set
   *  logged as assistance must not be answered with a recommendation about
   *  load, and the wording on screen has to match the dial under it. */
  loggedMode?: ResistanceMode,
  loggedContext?: LoadContext
) {
  const indexed = trainingIndex().byId.get(exercise.exerciseId)
  const catalogueExercise = EXERCISES_BY_ID.get(exercise.exerciseId)
  if (!indexed || !catalogueExercise) return null
  const target = exercise.sets.find((s) => s.setType === "working")?.target
  const mode =
    loggedMode ??
    target?.resistance.type ??
    resistanceModes(catalogueExercise)[0]
  // Legacy workouts are read live: they carry no sets, so they can move a
  // recommendation's staleness but never its load.
  const history = toTrainingHistory(data, useWorkouts.getState().workouts)
  const measured = mode === "external_load" || mode === "assistance"
  // The station this exercise is being trained at now, not the one the last
  // set happened to be logged at: a person who moved machines must be told the
  // history no longer compares, and only asking forward can say that.
  const context = measured
    ? (loggedContext ??
      loadContextFor(
        catalogueExercise,
        mode,
        activeConfigurationFor(exercise.exerciseId, mode, data.settings) ??
          undefined,
        increments[catalogueExercise.equipment]
      ))
    : undefined
  return recommendProgression({
    exercise: indexed,
    history,
    now,
    reps: target?.reps ?? { min: 8, max: 12 },
    rir: target?.rir ?? 2,
    requiredSets: Math.max(
      1,
      exercise.sets.filter((s) => s.setType === "working").length
    ),
    policy: DEFAULT_POLICY,
    loadGrid: context?.grid,
    loadContext: context
      ? { stationId: context.stationId, basis: context.basis }
      : undefined,
  })
}
