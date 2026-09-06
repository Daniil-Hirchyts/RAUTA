import { EXERCISES, EQUIPMENT_OPTIONS } from "@/lib/exercises"
import { useTrainingRecords } from "@/store/use-training-records"
import { toEngineLoadPreferences } from "@/training-persistence/history"
import { toEngineProgramSnapshot } from "@/training-persistence/program"
import {
  adaptTrainingProgram,
  createExerciseIndex,
  findExerciseSubstitutions,
  generateTrainingProgram,
  recommendProgression,
  DEFAULT_POLICY,
} from "@/training"
import type {
  ProgramGenerationRequest,
  TrainingGoal,
  UserTrainingProfile,
} from "@/training"
import type {
  PersistedActiveExerciseDraft,
  PersistedProgramRecord,
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
export type PlanSetup = {
  age: number
  experience: UserTrainingProfile["trainingExperience"]
  goal: TrainingGoal
  equipment: string[]
}

export function buildTrainingRequest(
  setup: PlanSetup,
  now: string,
  source?: PersistedProgramRecord
): ProgramGenerationRequest {
  const store = useTrainingRecords.getState()
  const monday = new Date(now)
  monday.setUTCHours(0, 0, 0, 0)
  monday.setUTCDate(monday.getUTCDate() + ((8 - monday.getUTCDay()) % 7))
  // A new plan starts on the next Monday, including today when generated before its slots.
  if (monday.getTime() <= Date.parse(now))
    monday.setUTCDate(monday.getUTCDate() + 7)
  const sourceWeek =
    source?.snapshot.weeks.find(
      (w) =>
        Date.parse(w.start) <= Date.parse(now) &&
        Date.parse(now) < Date.parse(w.start) + 7 * 86400000
    ) ?? source?.snapshot.weeks[0]
  const selectedContexts = store.data.settings.loadConfigurations.filter(
    (c, _, all) =>
      all.filter((other) => other.exerciseId === c.exerciseId).length === 1
  )
  return {
    profile: {
      age: setup.age,
      trainingExperience: setup.experience,
      health: { status: "healthy" },
    },
    preferences: {
      goal: setup.goal,
      availableEquipment: setup.equipment,
      maxSessionDurationMinutes: 60,
      ...toEngineLoadPreferences(
        store.data.settings,
        selectedContexts.map((c) => c.id)
      ),
    },
    schedule: {
      weekStart: sourceWeek?.start ?? monday.toISOString(),
      days: sourceWeek
        ? [
            ...new Set(
              sourceWeek.sessions
                .filter(
                  (s) =>
                    Date.parse(s.scheduledAt) > Date.parse(now) &&
                    !store.data.sessions.some(
                      (actual) => actual.plannedSessionId === s.id
                    )
                )
                .map((s) =>
                  Math.floor(
                    (Date.parse(s.scheduledAt) - Date.parse(sourceWeek.start)) /
                      86400000
                  )
                )
            ),
          ].sort((a, b) => a - b)
        : [0, 2, 4],
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

export function generateAndSavePlan(
  setup: PlanSetup,
  now = new Date().toISOString(),
  source?: PersistedProgramRecord
) {
  const request = buildTrainingRequest(setup, now, source)
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
    {
      age: 30,
      experience: "beginner",
      goal: source?.snapshot.goal ?? "general_fitness",
      equipment: availableEquipment,
    },
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
