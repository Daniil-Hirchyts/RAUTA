import {
  activeProgramRecord,
  sessionViews,
  toPlanBlock,
  type PlanBlock,
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

const NEXT_WEEK_MESSAGES = {
  source: "Your current plan is unavailable. I couldn't plan next week.",
  future: "This week still has a session you can train.",
  active: "Finish or end your current workout before planning next week.",
  already_planned: "Your next week is already planned.",
  stale_source: "Your training plan changed. Open next-week planning again.",
  days: "Pick at least one day you can train next week.",
  engine: "I couldn't build next week from these settings.",
  persistence:
    "I couldn't save next week. Your current plan is unchanged. Please try again.",
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

type NextWeekBlockReason = keyof typeof NEXT_WEEK_MESSAGES
export type NextWeekBlock = {
  status: "blocked"
  reason: NextWeekBlockReason
  message: string
  page: PlanBlock["page"]
  issues: PlanBlock["issues"]
}

const nextBlocked = (
  reason: NextWeekBlockReason,
  detail: Pick<PlanBlock, "page" | "issues"> = { page: null, issues: [] }
): NextWeekBlock => ({
  status: "blocked",
  reason,
  message: NEXT_WEEK_MESSAGES[reason],
  ...detail,
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

/** A next-week revision becomes available once this program has no usable
 * session left on or after today, or once its week has ended. The decision is
 * derived from persisted program/history state so reloads cannot reopen a
 * source that has already produced a next-week child. */
export function nextWeekEligibility(
  data: PersistedTrainingStateLatest = useTrainingRecords.getState().data,
  now = new Date().toISOString(),
  workouts: readonly Workout[] = useWorkouts.getState().workouts
) {
  const source = activeProgramRecord(data)
  if (!source || source.lifecycle !== "active") return nextBlocked("source")
  if (data.activeWorkout) return nextBlocked("active")
  if (
    data.programs.some(
      (program) =>
        program.revision?.sourceProgramId === source.id &&
        program.revision.reason === "next_week"
    )
  )
    return nextBlocked("already_planned")

  const week = source.snapshot.weeks.at(-1)
  if (!week) return nextBlocked("source")
  const today = now.slice(0, 10)
  const weekEnded = Date.parse(now) >= Date.parse(week.start) + 7 * 86400000
  const usableSessions = week.sessions.filter(
    (session) =>
      session.scheduledAt.slice(0, 10) >= today &&
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
  if (!weekEnded && usableSessions.length) return nextBlocked("future")

  return {
    status: "eligible" as const,
    source,
    week,
    observationIds: data.sessions
      .filter(
        (session) =>
          session.plannedProgramId === source.id &&
          (session.status === "completed" || session.status === "partial") &&
          Date.parse(session.completedAt) <= Date.parse(now)
      )
      .map((session) => session.id),
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

export type NextWeekOutcome =
  | NextWeekBlock
  | {
      status: "created"
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

/** Builds one immutable next-week revision from the active program and actual
 * history. Projections are staged first and restored if the program commit
 * fails; the source snapshot and completed history are never rewritten. */
export function createNextTrainingWeek(input: {
  days: readonly number[]
  sourceProgramId: string
  now?: string
}): NextWeekOutcome {
  const now = input.now ?? new Date().toISOString()
  const days = [...new Set(input.days)]
    .filter((day) => Number.isInteger(day) && day >= 0 && day <= 6)
    .sort((left, right) => left - right)
  if (!days.length) return nextBlocked("days")

  const initialData = useTrainingRecords.getState().data
  const existingChild = initialData.programs.find(
    (program) =>
      program.revision?.sourceProgramId === input.sourceProgramId &&
      program.revision.reason === "next_week"
  )
  if (existingChild) return nextBlocked("already_planned")
  if (initialData.activeProgramId !== input.sourceProgramId)
    return nextBlocked("stale_source")

  const eligibility = nextWeekEligibility(initialData, now)
  if (eligibility.status === "blocked") return eligibility
  if (eligibility.source.id !== input.sourceProgramId)
    return nextBlocked("stale_source")
  if (useActiveWorkout.getState().session) return nextBlocked("active")

  const source = eligibility.source
  const sourceBytes = JSON.stringify(source.snapshot)
  let planned
  try {
    planned = planTrainingWeek(undefined, now, source, days, "next_week")
  } catch {
    return nextBlocked("engine")
  }
  if (!("program" in planned.result)) {
    const detail = toPlanBlock(planned.result)
    return nextBlocked("engine", { page: detail.page, issues: detail.issues })
  }

  const program = planned.result.program
  const sessions = sessionViews(program)
  const sourceSessionIds = new Set(
    source.snapshot.weeks.flatMap((week) =>
      week.sessions.map((session) => session.id)
    )
  )
  const sourceSetIds = new Set(
    source.snapshot.weeks.flatMap((week) =>
      week.sessions.flatMap((session) =>
        session.exercises.flatMap((exercise) =>
          [...exercise.workingSets, ...exercise.warmupSets].map((set) => set.id)
        )
      )
    )
  )
  const expectedDates = planned.request.schedule.days
    .map((day) =>
      new Date(
        Date.parse(planned.request.schedule.weekStart) + day * 86400000
      )
        .toISOString()
        .slice(0, 10)
    )
    .sort()
  const generatedSetIds = program.weeks.flatMap((week) =>
    week.sessions.flatMap((session) =>
      session.exercises.flatMap((exercise) =>
        [...exercise.workingSets, ...exercise.warmupSets].map((set) => set.id)
      )
    )
  )
  if (
    program.id === source.id ||
    program.adaptation?.sourceProgramId !== source.id ||
    program.adaptation.mode !== "next_week" ||
    sessions.some((session) => sourceSessionIds.has(session.sessionId)) ||
    generatedSetIds.some((id) => sourceSetIds.has(id)) ||
    JSON.stringify(sessions.map((session) => session.date).sort()) !==
      JSON.stringify(expectedDates)
  )
    return nextBlocked("engine")

  const currentSource = useTrainingRecords
    .getState()
    .data.programs.find((item) => item.id === source.id)
  if (!currentSource || JSON.stringify(currentSource.snapshot) !== sourceBytes)
    return nextBlocked("stale_source")

  const previous = useWorkouts.getState().workouts
  const data = useTrainingRecords.getState().data
  const retained = previous.filter(
    (workout) => !isObsoleteProjection(workout, data)
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
    })
  } catch {
    try {
      useWorkouts.setState({ workouts: previous })
    } catch {
      // The workout store restores memory before attempting its storage write.
    }
    return nextBlocked("persistence")
  }

  return {
    status: "created",
    programId: program.id,
    sessions,
    message: "Your next week is ready.",
  }
}
