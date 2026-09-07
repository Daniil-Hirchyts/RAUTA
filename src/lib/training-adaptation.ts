import {
  activeProgramRecord,
  sessionViews,
  type PlannedSessionView,
} from "@/lib/training-plan"
import {
  planTrainingWeek,
  remainingTrainingSlots,
} from "@/lib/training-workflow"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts, type Workout } from "@/store/use-workouts"
import { isSupersededPlannedSession } from "@/training-persistence/program"
import type { PersistedTrainingStateLatest } from "@/training-persistence/schema"

const MESSAGES = {
  source: "Your source plan is unavailable. I could not adjust this week.",
  future: "There are no future sessions left in this week to adjust.",
  empty: "Log performed sets in a planned session before I adjust the week.",
  incorporated:
    "Your logged sessions have already been incorporated into the plan.",
  active: "Finish or end your current workout before adjusting the week.",
  engine:
    "I could not adjust the remaining week with your saved preferences. Review My preferences and try again.",
  persistence:
    "I could not save the adjustment. Your plan is unchanged. Please try again.",
} as const

type BlockReason = keyof typeof MESSAGES
type AdaptationBlock = {
  status: "blocked"
  reason: BlockReason
  message: string
}
const blocked = (reason: BlockReason): AdaptationBlock => ({
  status: "blocked",
  reason,
  message: MESSAGES[reason],
})

/** Persisted evidence, not an in-memory 'already tapped' flag, decides whether
 * this source can be revised. React and the command use the same decision. */
export function remainingWeekEligibility(
  data: PersistedTrainingStateLatest = useTrainingRecords.getState().data,
  now = new Date().toISOString(),
  workouts: readonly Workout[] = useWorkouts.getState().workouts
) {
  const source = activeProgramRecord(data)
  if (!source || source.lifecycle !== "active") return blocked("source")
  if (data.activeWorkout) return blocked("active")
  const { week, sessions } = remainingTrainingSlots(source, now, data, workouts)
  if (!sessions.length || !week) return blocked("future")
  const incorporated = new Set(
    data.programs.flatMap(
      (program) => program.revision?.incorporatedSessionIds ?? []
    )
  )
  const observations = data.sessions.filter(
    (session) =>
      session.plannedProgramId === source.id &&
      week.sessions.some(
        (planned) => planned.id === session.plannedSessionId
      ) &&
      Date.parse(session.completedAt) <= Date.parse(now) &&
      (session.status === "completed" || session.status === "partial") &&
      session.exercises.some((exercise) =>
        exercise.sets.some((set) => set.completed)
      )
  )
  const fresh = observations.filter(
    (session) =>
      !incorporated.has(session.id) &&
      !data.programs.some(
        (program) =>
          program.revision?.sourceProgramId === source.id &&
          program.revision.reason === "remaining_week" &&
          !program.revision.incorporatedSessionIds &&
          session.completedAt <= program.revision.asOf
      )
  )
  if (!fresh.length)
    return blocked(
      observations.length || source.revision?.reason === "remaining_week"
        ? "incorporated"
        : "empty"
    )
  return {
    status: "eligible" as const,
    source,
    sessions,
    observationIds: fresh.map((session) => session.id),
  }
}

/** Hide orphaned staging rows after an interrupted write, and withdrawn
 * projections after restore. Real application/structured history stays visible. */
export function isObsoleteProjection(
  workout: Workout,
  data: PersistedTrainingStateLatest
) {
  const planned = workout.planned
  if (
    !planned ||
    workout.completion ||
    data.sessions.some(
      (session) =>
        session.sourceWorkoutId === workout.id ||
        session.plannedSessionId === planned.sessionId
    )
  )
    return false
  return (
    !data.programs.some((program) => program.id === planned.programId) ||
    isSupersededPlannedSession(data, planned.programId, planned.sessionId)
  )
}

function projection(view: PlannedSessionView, now: string): Workout {
  return {
    id: `planned-${view.sessionId}`,
    name: view.title,
    date: view.date,
    exerciseIds: [...view.exerciseIds],
    completion: null,
    createdAt: now,
    updatedAt: now,
    planned: { programId: view.programId, sessionId: view.sessionId },
  }
}

export type RemainingWeekOutcome =
  | AdaptationBlock
  | {
      status: "adjusted"
      programId: string
      sessions: PlannedSessionView[]
      message: string
    }

/** Thin application transaction around the existing deterministic engine.
 * Stage replaceable projections first; the training-record write is the commit
 * point. A failure restores projections, while the training store rolls back
 * its own failed write. If the process dies between writes, source slots still
 * resolve from the original snapshot and are projected again when opened;
 * orphan staging rows are neither visible nor startable.
 */
export function adjustRemainingWeek(
  now = new Date().toISOString()
): RemainingWeekOutcome {
  const eligibility = remainingWeekEligibility(undefined, now)
  if (eligibility.status === "blocked") return eligibility
  if (useActiveWorkout.getState().session) return blocked("active")
  const { source } = eligibility
  let planned
  try {
    planned = planTrainingWeek(undefined, now, source)
  } catch {
    return blocked("engine")
  }
  if (!("program" in planned.result)) return blocked("engine")
  const program = planned.result.program
  const sessions = sessionViews(program)
  // The engine must answer the source's exact remaining slots, never another week.
  if (
    sessions.length !== eligibility.sessions.length ||
    program.adaptation?.sourceProgramId !== source.id ||
    program.adaptation.mode !== "remaining_week" ||
    program.weeks
      .flatMap((week) => week.sessions)
      .some(
        (session) =>
          !eligibility.sessions.some(
            (slot) => slot.scheduledAt === session.scheduledAt
          )
      )
  )
    return blocked("engine")

  const previous = useWorkouts.getState().workouts
  const data = useTrainingRecords.getState().data
  const replacedSessionIds = eligibility.sessions.map((session) => session.id)
  const retained = previous.filter(
    (workout) =>
      !(
        workout.planned?.programId === source.id &&
        replacedSessionIds.includes(workout.planned.sessionId)
      ) &&
      !(workout.date > now.slice(0, 10) && isObsoleteProjection(workout, data))
  )
  try {
    useWorkouts.setState({
      workouts: [
        ...retained,
        ...sessions.map((session) => projection(session, now)),
      ],
    })
    useTrainingRecords.getState().saveProgram(program, {
      incorporatedSessionIds: eligibility.observationIds,
      replacedSessionIds,
    })
  } catch {
    try {
      useWorkouts.setState({ workouts: previous })
    } catch {
      // Zustand restores memory before attempting the storage write. On reload
      // missing source projections are recovered from the immutable snapshot.
    }
    return blocked("persistence")
  }
  return {
    status: "adjusted",
    programId: program.id,
    sessions,
    message: `I adjusted ${sessions.length} remaining session${sessions.length === 1 ? "" : "s"} from what you logged.`,
  }
}
