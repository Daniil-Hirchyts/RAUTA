import { EXERCISES_BY_ID } from "@/lib/exercises"
import { buildTrainingEngineInputs } from "@/lib/training-engine-adapter"
import { buildTrainingRequest, trainingIndex } from "@/lib/training-workflow"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts } from "@/store/use-workouts"
import { ENGINE_VERSION } from "@/training"
import type {
  MuscleId,
  PlannedExercise,
  PlannedSession,
  TrainingProgram,
} from "@/training"
import { estimateSessionDuration } from "@/training/planning/duration"
import { preparation } from "@/training/planning/generate"
import { prescribeExercise } from "@/training/planning/prescribe"
import { rankExerciseCandidates } from "@/training/planning/rank"
import { orderExercises, scoreWeek } from "@/training/scoring/scores"
import { sessionViews } from "@/lib/training-plan"

const mondayFor = (date: string) => {
  const monday = new Date(`${date}T00:00:00.000Z`)
  monday.setUTCDate(monday.getUTCDate() - ((monday.getUTCDay() + 6) % 7))
  return monday.toISOString()
}

const focusFor = (exerciseIds: readonly string[], requested?: readonly MuscleId[]) =>
  requested?.length
    ? [...new Set(requested)]
    : [...new Set(exerciseIds.flatMap((id) => EXERCISES_BY_ID.get(id)?.muscles ?? []))]

/** Builds one prescribed session with the same ranking, progression and
 * duration rules used by the weekly planner. */
export function buildEngineWorkoutProgram(input: {
  date: string
  exerciseIds?: readonly string[]
  focusMuscles?: readonly MuscleId[]
  now?: string
}): TrainingProgram {
  const now = input.now ?? new Date().toISOString()
  const request = buildTrainingRequest(buildTrainingEngineInputs(), now)
  request.schedule = {
    weekStart: mondayFor(input.date),
    days: [0],
    durationWeeks: 1,
  }
  const optimization = preparation(request, undefined, trainingIndex())
  const focus = focusFor(input.exerciseIds ?? [], input.focusMuscles)
  const ranked = rankExerciseCandidates(request, { focus })
  const ranking = new Map(ranked.map((candidate) => [candidate.exerciseId, candidate.score]))
  let exerciseIds = [...new Set(input.exerciseIds ?? [])].filter((id) =>
    optimization.index.byId.has(id)
  )
  if (!exerciseIds.length) {
    const requested = new Set(focus)
    exerciseIds = ranked
      .filter(({ exerciseId }) =>
        optimization.index.byId
          .get(exerciseId)!
          .metadata.setRoles.some(
            (role) => role.role === "direct" && requested.has(role.muscleId)
          )
      )
      .slice(0, optimization.policy.maxExercisesPerSession)
      .map(({ exerciseId }) => exerciseId)
  }
  if (!exerciseIds.length)
    throw new Error("No exercise matches those muscles and your saved equipment.")

  const programId = `program-workout-${crypto.randomUUID()}`
  const weekId = `${programId}/week-0`
  const sessionId = `${weekId}/session-0`
  const exercises: PlannedExercise[] = exerciseIds.map((exerciseId) =>
    prescribeExercise(
      optimization.index.byId.get(exerciseId)!,
      3,
      sessionId,
      ranking.get(exerciseId) ?? { total: 0, contributions: [] },
      optimization
    )
  )
  const session: PlannedSession = {
    id: sessionId,
    scheduledAt: `${input.date}T00:00:00.000Z`,
    focus,
    exercises: orderExercises(exercises, optimization),
    duration: estimateSessionDuration(
      { exercises: orderExercises(exercises, optimization) },
      optimization.index,
      optimization.policy
    ),
  }
  const week = {
    id: weekId,
    start: mondayFor(input.date),
    phase: "base" as const,
    sessions: [session],
    targets: optimization.targets,
  }
  return {
    id: programId,
    engineVersion: ENGINE_VERSION,
    policyVersion: optimization.policy.version,
    policy: optimization.policy,
    datasetFingerprint: optimization.index.fingerprint,
    generatedAt: now,
    goal: request.preferences.goal,
    durationWeeks: 1,
    weeks: [week],
    diagnostics: {
      splits: [{ name: "single_session", score: scoreWeek(week, optimization).total, valid: true }],
      candidateCount: ranked.length,
      optimizerIterations: 0,
      selectedSplit: "single_session",
      score: scoreWeek(week, optimization),
      warnings: [],
    },
  }
}

export function createEngineWorkout(input: {
  date: string
  name?: string
  exerciseIds?: readonly string[]
  focusMuscles?: readonly MuscleId[]
  workoutId?: string
  now?: string
}) {
  const program = buildEngineWorkoutProgram(input)
  useTrainingRecords.getState().saveProgram(program, {
    activate: false,
    kind: "workout",
  })
  const view = sessionViews(program)[0]
  const workoutId = input.workoutId
  if (workoutId) {
    useWorkouts.getState().updateWorkout(workoutId, {
      name: input.name?.trim() || view.title,
      date: input.date,
      exerciseIds: view.exerciseIds,
      planned: { programId: program.id, sessionId: view.sessionId },
    })
    return workoutId
  }
  return useWorkouts.getState().createWorkout({
    name: input.name?.trim() || view.title,
    date: input.date,
    exerciseIds: view.exerciseIds,
    planned: { programId: program.id, sessionId: view.sessionId },
  })
}

export function duplicateWorkoutWithEngine(workoutId: string, date: string) {
  const source = useWorkouts.getState().workouts.find((item) => item.id === workoutId)
  if (!source) throw new Error("Workout not found.")
  return createEngineWorkout({
    date,
    name: `${source.name} copy`,
    exerciseIds: source.exerciseIds,
  })
}

/** Migrates a legacy unfinished workout when it next becomes relevant. */
export function ensureEngineWorkout(workoutId: string) {
  const workout = useWorkouts.getState().workouts.find((item) => item.id === workoutId)
  if (
    !workout ||
    workout.planned ||
    workout.completion ||
    !workout.exerciseIds.length ||
    useTrainingRecords.getState().data.activeWorkout?.sourceWorkoutId === workoutId
  )
    return workoutId
  return createEngineWorkout({
    workoutId,
    date: workout.date,
    name: workout.name,
    exerciseIds: workout.exerciseIds,
  })
}
