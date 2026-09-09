import { toISODate } from "@/lib/date"
import { buildTrainingEngineInputs } from "@/lib/training-engine-adapter"
import { sessionViews } from "@/lib/training-plan"
import {
  buildTrainingRequest,
  replacementIds,
  trainingIndex,
} from "@/lib/training-workflow"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts } from "@/store/use-workouts"
import {
  isStartablePlannedSession,
  isSupersededPlannedSession,
  toEngineProgramSnapshot,
} from "@/training-persistence/program"
import { preparation } from "@/training/planning/generate"
import { prescribeExercise } from "@/training/planning/prescribe"
import { estimateSessionDuration } from "@/training/planning/duration"
import { createEngineWorkout } from "@/lib/engine-workout"
import type { PlannedSession, TrainingProgram } from "@/training"

/** A calendar edit or substitution creates a revision. Completed prescriptions
 * stay in their original snapshot; every unfinished workout keeps its UI id. */
function editPlannedWorkout(
  workoutId: string,
  edit: (session: PlannedSession, program: TrainingProgram) => void | false
) {
  const records = useTrainingRecords.getState()
  const previous = useWorkouts.getState().workouts
  const workout = previous.find((item) => item.id === workoutId)
  if (!workout?.planned || workout.completion)
    throw new Error("This workout cannot be edited.")
  if (records.data.activeWorkout || useActiveWorkout.getState().session)
    throw new Error(
      "Finish or end your current workout before editing the plan."
    )
  const { programId, sessionId } = workout.planned
  if (!isStartablePlannedSession(records.data, programId, sessionId))
    throw new Error("This planned session is no longer available.")
  const source = records.data.programs.find((item) => item.id === programId)!
  const program = toEngineProgramSnapshot(source.snapshot)
  const pending = program.weeks
    .flatMap((week) => week.sessions)
    .filter(
      (session) =>
        !isSupersededPlannedSession(records.data, source.id, session.id) &&
        !records.data.sessions.some(
          (actual) => actual.plannedSessionId === session.id
        ) &&
        !previous.some(
          (item) => item.planned?.sessionId === session.id && item.completion
        )
    )
  const target = pending.find((session) => session.id === sessionId)
  if (!target) throw new Error("This session has already been recorded.")
  const keepTarget = edit(target, program) !== false
  program.id = `program-${crypto.randomUUID()}`
  program.generatedAt = new Date().toISOString()
  delete program.adaptation
  const replacedSessionIds = pending.map((session) => session.id)
  const newSessionIds = new Map<string, string>()
  const weeks = new Map<string, (typeof program.weeks)[number]>()
  for (const session of pending.filter((item) => keepTarget || item !== target).sort((a, b) =>
    a.scheduledAt.localeCompare(b.scheduledAt)
  )) {
    const monday = new Date(session.scheduledAt)
    monday.setUTCHours(0, 0, 0, 0)
    monday.setUTCDate(monday.getUTCDate() - ((monday.getUTCDay() + 6) % 7))
    const start = monday.toISOString()
    let week = weeks.get(start)
    if (!week) {
      week = {
        ...structuredClone(program.weeks[0]),
        id: `${program.id}/week-${weeks.size}`,
        start,
        sessions: [],
      }
      weeks.set(start, week)
    }
    const newId = `${week.id}/session-${week.sessions.length}`
    newSessionIds.set(session.id, newId)
    session.id = newId
    session.exercises.forEach((exercise) => {
      for (const [kind, sets] of [
        ["work", exercise.workingSets],
        ["warm", exercise.warmupSets],
      ] as const)
        sets.forEach((set, index) => {
          set.id = `${newId}/${exercise.exerciseId}/${kind}/${index}`
        })
    })
    week.sessions.push(session)
  }
  if (!weeks.size) {
    const start = structuredClone(program.weeks[0])
    start.id = `${program.id}/week-0`
    start.sessions = []
    weeks.set(start.start, start)
  }
  program.weeks = [...weeks.values()]
  program.durationWeeks = program.weeks.length
  const views = sessionViews(program)
  const byId = new Map(views.map((view) => [view.sessionId, view]))
  const pendingIds = new Set(replacedSessionIds)
  const projected = previous.flatMap((item) => {
    const wasPending =
      item.planned?.programId === programId &&
      pendingIds.has(item.planned.sessionId)
    const id =
      item.planned?.programId === programId
        ? newSessionIds.get(item.planned.sessionId)
        : undefined
    const view = id ? byId.get(id) : undefined
    return view
      ? [{
          ...item,
          date: view.date,
          exerciseIds: view.exerciseIds,
          updatedAt: program.generatedAt,
          planned: { programId: program.id, sessionId: view.sessionId },
        }]
      : wasPending
        ? []
        : [item]
  })
  for (const view of views) {
    if (!projected.some((item) => item.planned?.sessionId === view.sessionId))
      projected.push({
        id: `planned-${view.sessionId}`,
        name: view.title,
        date: view.date,
        exerciseIds: view.exerciseIds,
        planned: { programId: program.id, sessionId: view.sessionId },
        completion: null,
        createdAt: program.generatedAt,
        updatedAt: program.generatedAt,
      })
  }
  try {
    useWorkouts.setState({ workouts: projected })
    records.saveProgram(program, {
      activate: source.kind === "workout" ? false : undefined,
      kind: source.kind,
      manualSourceProgramId: programId,
      replacedSessionIds,
    })
  } catch (error) {
    try {
      useWorkouts.setState({ workouts: previous })
    } catch {
      /* Memory restored. */
    }
    throw error
  }
}

export function deleteScheduledWorkout(workoutId: string) {
  const workout = useWorkouts.getState().workouts.find((item) => item.id === workoutId)
  if (!workout || workout.completion)
    throw new Error("This workout cannot be deleted.")
  if (!workout.planned) {
    useWorkouts.getState().deleteWorkout(workoutId)
    return
  }
  const source = useTrainingRecords
    .getState()
    .data.programs.find((item) => item.id === workout.planned?.programId)
  if (source?.kind === "workout") {
    useWorkouts.getState().deleteWorkout(workoutId)
    return
  }
  editPlannedWorkout(workoutId, () => false)
}

export function updateScheduledWorkoutExercises(
  workoutId: string,
  exerciseIds: readonly string[],
  rePrescribe = false
) {
  const workout = useWorkouts.getState().workouts.find((item) => item.id === workoutId)
  if (!workout || workout.completion)
    throw new Error("This workout cannot be edited.")
  const unique = [...new Set(exerciseIds)]
  if (!workout.planned) {
    useWorkouts.getState().updateWorkout(workoutId, { exerciseIds: unique })
    return
  }
  editPlannedWorkout(workoutId, (session, program) => {
    const request = buildTrainingRequest(
      buildTrainingEngineInputs(),
      new Date().toISOString()
    )
    request.policy = program.policy
    const input = preparation(request, program, trainingIndex())
    const existing = new Map(session.exercises.map((item) => [item.exerciseId, item]))
    const exercises = unique.flatMap((exerciseId) => {
      const indexed = input.index.byId.get(exerciseId)
      if (!indexed) return []
      const previous = existing.get(exerciseId)
      return [
        previous && !rePrescribe
          ? previous
          :
          prescribeExercise(
            indexed,
            previous?.workingSets.length ?? 3,
            session.id,
            { total: 0, contributions: [] },
            input
          ),
      ]
    })
    session.exercises = exercises.map((exercise, order) => ({ ...exercise, order }))
    session.focus = [
      ...new Set(session.exercises.flatMap((exercise) => exercise.targetMuscles)),
    ]
    session.duration = estimateSessionDuration(session, input.index, input.policy)
  })
}

/** Recomputes every future prescription from the newly completed history.
 * Workout identities and dates stay stable, so open screens and calendar
 * entries continue to point at the refreshed plan revisions. */
export function refreshFutureWorkoutPrescriptions() {
  const today = toISODate(new Date())
  const ids = useWorkouts
    .getState()
    .workouts.filter((workout) => !workout.completion && workout.date >= today)
    .map((workout) => workout.id)
  for (const workoutId of ids) {
    const workout = useWorkouts.getState().workouts.find((item) => item.id === workoutId)
    if (!workout || workout.completion) continue
    if (workout.planned)
      updateScheduledWorkoutExercises(workoutId, workout.exerciseIds, true)
    else
      createEngineWorkout({
        workoutId,
        date: workout.date,
        name: workout.name,
        exerciseIds: workout.exerciseIds,
      })
  }
}

export function rescheduleWorkout(workoutId: string, date: string) {
  const workout = useWorkouts
    .getState()
    .workouts.find((item) => item.id === workoutId)
  if (!workout || workout.completion)
    throw new Error("This workout cannot be rescheduled.")
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(date) ||
    !Number.isFinite(Date.parse(`${date}T00:00:00.000Z`)) ||
    new Date(`${date}T00:00:00.000Z`).toISOString().slice(0, 10) !== date
  )
    throw new Error("Choose a valid workout date.")
  if (date < toISODate(new Date()))
    throw new Error("Choose today or a future date.")
  if (useActiveWorkout.getState().session?.workoutId === workoutId)
    throw new Error("A running workout stays on the day it started.")
  if (workout.date === date) return
  if (!workout.planned) {
    useWorkouts.getState().updateWorkout(workoutId, { date })
    return
  }
  editPlannedWorkout(workoutId, (session) => {
    session.scheduledAt = `${date}T00:00:00.000Z`
  })
}

export function substituteScheduledPlannedExercise(
  workoutId: string,
  exerciseId: string,
  replacementId: string
) {
  if (!replacementIds(exerciseId, workoutId).includes(replacementId))
    throw new Error(
      "That alternative no longer fits this workout and your equipment."
    )
  editPlannedWorkout(workoutId, (session, program) => {
    const position = session.exercises.findIndex(
      (item) => item.exerciseId === exerciseId
    )
    if (
      position < 0 ||
      session.exercises.some((item) => item.exerciseId === replacementId)
    )
      throw new Error("Choose an exercise that is not already in this session.")
    const request = buildTrainingRequest(
      buildTrainingEngineInputs(),
      new Date().toISOString()
    )
    request.policy = program.policy
    const input = preparation(request, program, trainingIndex())
    const original = session.exercises[position]
    session.exercises[position] = {
      ...prescribeExercise(
        input.index.byId.get(replacementId)!,
        original.workingSets.length,
        session.id,
        original.rationale,
        input
      ),
      order: original.order,
    }
    session.duration = estimateSessionDuration(
      session,
      input.index,
      input.policy
    )
  })
}
