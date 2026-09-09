import { musclesForExerciseIds } from "@/lib/exercises"
import { formatKg } from "@/lib/resistance"
import { buildTrainingEngineInputs } from "@/lib/training-engine-adapter"
import {
  buildTrainingRequest,
  DEFAULT_TRAINING_DAYS,
  planTrainingWeek,
} from "@/lib/training-workflow"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts, type Workout } from "@/store/use-workouts"
import {
  isSupersededPlannedSession,
  toEngineProgramSnapshot,
} from "@/training-persistence/program"
import type {
  PersistedProgramRecord,
  PersistedTrainingStateLatest,
} from "@/training-persistence/schema"
import { generateTrainingProgram, SPLIT_MUSCLE_GROUPS } from "@/training"
import { namespaceProgramIds } from "@/training/planning/generate"
import type {
  PlannedSession,
  PlanningIssue,
  ProgramGenerationResult,
  TrainingProgram,
} from "@/training"
import type { MuscleId } from "@/types"

/**
 * Planned sessions, as the application sees them.
 *
 * The deterministic engine decides what to prescribe and the immutable program
 * snapshot keeps that decision. Nothing here re-decides any of it: every value
 * below is read back out of the stored snapshot each time it is asked for, so
 * there is one prescription and it is the one that was saved.
 *
 * The one thing this file does create is a *projection* — an ordinary
 * application workout carrying a `planned` reference back to the program and
 * session it stands for. That is what lets a generated session travel through
 * the workout list, the workout detail page, the countdown, the timer and the
 * set log without a second workout system existing anywhere.
 */

export { DEFAULT_TRAINING_DAYS }

/** Offsets into the planned week, which the engine always starts on a Monday. */
export const WEEK_DAYS = [
  { offset: 0, short: "Mon", long: "Monday" },
  { offset: 1, short: "Tue", long: "Tuesday" },
  { offset: 2, short: "Wed", long: "Wednesday" },
  { offset: 3, short: "Thu", long: "Thursday" },
  { offset: 4, short: "Fri", long: "Friday" },
  { offset: 5, short: "Sat", long: "Saturday" },
  { offset: 6, short: "Sun", long: "Sunday" },
] as const

export type PlannedExercisePrescription = {
  exerciseId: string
  /** Working sets only; warm-ups are prescribed too but are not the target. */
  sets: number
  reps: { min: number; max: number }
  rir: number
  /** Present only where the engine could name a load from real history. */
  loadKg: number | null
  /** How that load is carried. A dumbbell prescription of 30 kg is 30 in each
   *  hand, and a plan that failed to say so would be read as half the work. */
  loadBasis: "total" | "per_implement" | null
  restSeconds: number
}

export type PlannedSessionView = {
  programId: string
  sessionId: string
  /** Local calendar day, taken from the schedule rather than converted through
   *  a local clock, so the day a plan names is the day it shows. */
  date: string
  title: string
  exerciseIds: string[]
  focus: MuscleId[]
  workingSets: number
  minutes: number
  prescription: PlannedExercisePrescription[]
}

/** The existing profile page that owns the answer a refusal is about. */
export type PlanBlockPage =
  | "profile-basics"
  | "profile-training"
  | "profile-health"
  | "profile-equipment"
  | "profile-priorities"

/** Why a week could not be built, in the words of the screen that has to say
 *  it and the page that can fix it. */
export type PlanBlock = {
  reason:
    "days" | "health" | "goal" | "equipment" | "duration" | "volume" | "input"
  message: string
  page: PlanBlockPage | null
  issues: PlanningIssue[]
}

export type TrainingWeekOutcome =
  | {
      status: "created"
      programId: string
      sessions: PlannedSessionView[]
      issues: PlanningIssue[]
    }
  | ({ status: "blocked" } & PlanBlock)

const UPPER = new Set<string>(SPLIT_MUSCLE_GROUPS.upper)
const PUSH = new Set<string>(SPLIT_MUSCLE_GROUPS.push)
const PULL = new Set<string>(SPLIT_MUSCLE_GROUPS.pull)

/**
 * What to call a session, decided from the split the engine chose and the
 * muscles it gave that session. Both come out of the snapshot, so the name a
 * session carries cannot drift from the plan it belongs to.
 */
export function plannedSessionTitle(
  split: string,
  focus: readonly MuscleId[]
): string {
  if (focus.length === 0) return "Session"
  const every = (group: Set<string>) => focus.every((id) => group.has(id))
  if (split === "upper_lower") return every(UPPER) ? "Upper" : "Lower"
  if (split === "push_pull_legs")
    return every(PUSH) ? "Push" : every(PULL) ? "Pull" : "Legs"
  return "Full body"
}

function prescriptionOf(
  session: PlannedSession
): PlannedExercisePrescription[] {
  return [...session.exercises]
    .sort((left, right) => left.order - right.order)
    .map((exercise) => {
      const first = exercise.workingSets[0]
      const resistance = first?.resistance
      return {
        exerciseId: exercise.exerciseId,
        sets: exercise.workingSets.length,
        reps: first ? { ...first.targetReps } : { min: 0, max: 0 },
        rir: first?.targetRir ?? 0,
        loadKg: resistance && "kg" in resistance ? resistance.kg : null,
        loadBasis:
          resistance && "basis" in resistance ? resistance.basis : null,
        restSeconds: exercise.restSeconds,
      }
    })
}

function toView(
  program: TrainingProgram,
  session: PlannedSession
): PlannedSessionView {
  const prescription = prescriptionOf(session)
  return {
    programId: program.id,
    sessionId: session.id,
    date: session.scheduledAt.slice(0, 10),
    title: plannedSessionTitle(
      program.diagnostics.selectedSplit,
      session.focus
    ),
    exerciseIds: prescription.map((item) => item.exerciseId),
    focus: [...session.focus],
    workingSets: prescription.reduce((total, item) => total + item.sets, 0),
    minutes: Math.round(session.duration.totalSeconds / 60),
    prescription,
  }
}

export function sessionViews(program: TrainingProgram): PlannedSessionView[] {
  return program.weeks
    .flatMap((week) => week.sessions)
    .sort((left, right) => left.scheduledAt.localeCompare(right.scheduledAt))
    .map((session) => toView(program, session))
}

const currentState = () => useTrainingRecords.getState().data

export function activeProgramRecord(
  data: PersistedTrainingStateLatest = currentState()
): PersistedProgramRecord | null {
  if (!data.activeProgramId) return null
  return (
    data.programs.find((program) => program.id === data.activeProgramId) ?? null
  )
}

/** Every planned session of the active program, oldest first. */
export function activePlannedSessions(
  data: PersistedTrainingStateLatest = currentState()
): PlannedSessionView[] {
  const record = activeProgramRecord(data)
  return record
    ? sessionViews(toEngineProgramSnapshot(record.snapshot)).filter(
        (session) =>
          !isSupersededPlannedSession(data, record.id, session.sessionId)
      )
    : []
}

/** One planned session, read straight back out of its own program snapshot. */
export function plannedSessionView(
  programId: string,
  sessionId: string,
  data: PersistedTrainingStateLatest = currentState()
): PlannedSessionView | null {
  const record = data.programs.find((program) => program.id === programId)
  if (!record) return null
  const program = toEngineProgramSnapshot(record.snapshot)
  const session = program.weeks
    .flatMap((week) => week.sessions)
    .find((item) => item.id === sessionId)
  return session ? toView(program, session) : null
}

/** Whether the structured history already holds this planned session. */
export function isPlannedSessionRecorded(
  sessionId: string,
  data: PersistedTrainingStateLatest = currentState()
) {
  return data.sessions.some((session) => session.plannedSessionId === sessionId)
}

export function plannedWorkoutFor(
  view: Pick<PlannedSessionView, "programId" | "sessionId">,
  workouts: readonly Workout[] = useWorkouts.getState().workouts
): Workout | undefined {
  return workouts.find(
    (workout) =>
      workout.planned?.programId === view.programId &&
      workout.planned.sessionId === view.sessionId
  )
}

/**
 * The application workout a planned session is performed through, created if
 * it is not there yet.
 *
 * The projection holds only what the existing screens need to route and draw:
 * a date, a name and the exercises in order. It is derived and replaceable —
 * the prescription itself stays in the snapshot, and starting the workout
 * reads the sets, reps, RIR and load from there.
 */
export function ensurePlannedWorkout(view: PlannedSessionView): string {
  const existing = plannedWorkoutFor(view)
  if (existing) return existing.id
  return useWorkouts.getState().createWorkout({
    name: view.title,
    date: view.date,
    exerciseIds: view.exerciseIds,
    planned: { programId: view.programId, sessionId: view.sessionId },
  })
}

/** Projects every session of a program in one pass, so a freshly created week
 *  is on the workout list before anybody taps anything. */
export function projectPlannedWorkouts(views: readonly PlannedSessionView[]) {
  return views.map(ensurePlannedWorkout)
}

type PlanRefusal = Exclude<ProgramGenerationResult, { program: unknown }>

const ISSUE_BLOCKS: Record<string, Omit<PlanBlock, "issues">> = {
  UNSUPPORTED_POPULATION: {
    reason: "health",
    message:
      "Your health answers mean I do not program automatically. Update them, or build the workout yourself.",
    page: "profile-health",
  },
  UNSUPPORTED_GOAL: {
    reason: "goal",
    message: "I cannot plan for that training goal. Pick another one.",
    page: "profile-training",
  },
  NO_VALID_EXERCISES: {
    reason: "equipment",
    message:
      "Your plan needs an equipment update before I can build it. Nothing saved covers a full session.",
    page: "profile-equipment",
  },
  UNAVAILABLE_EQUIPMENT: {
    reason: "equipment",
    message: "Your plan needs an equipment update before I can build it.",
    page: "profile-equipment",
  },
  SESSION_DURATION_INFEASIBLE: {
    reason: "duration",
    message:
      "There is not enough time in a session for this week. Allow more minutes, or fewer days.",
    page: "profile-training",
  },
  VOLUME_LIMIT: {
    reason: "volume",
    message:
      "The volume this asks for leaves no room for a week that works. Ease your priorities and ask again.",
    page: "profile-priorities",
  },
}

/**
 * Turns the engine's own refusal into one thing to say and one place to fix
 * it. Nothing is guessed and no weaker plan is offered in its place: a code
 * this does not recognise stays a plain refusal.
 */
export function toPlanBlock(result: PlanRefusal): PlanBlock {
  for (const issue of result.issues) {
    const known = ISSUE_BLOCKS[issue.code]
    if (known) return { ...known, issues: result.issues }
  }
  return {
    reason: "input",
    message:
      "I could not build a week from what I know. Check your training profile and try again.",
    page: "profile-training",
    issues: result.issues,
  }
}

/**
 * Creates a training week from everything already saved plus the one answer
 * only this week can give: which days are free.
 *
 * The profile, the equipment, the priorities and the structured history reach
 * the engine through the existing adapter; this adds no inputs of its own and
 * invents nothing to make a request pass.
 */
export function createTrainingWeek(input: {
  days: readonly number[]
  now?: string
}): TrainingWeekOutcome {
  const days = [...new Set(input.days)]
    .filter((day) => Number.isInteger(day) && day >= 0 && day <= 6)
    .sort((left, right) => left - right)
  if (days.length === 0)
    return {
      status: "blocked",
      reason: "days",
      message: "Pick at least one day you can train.",
      page: null,
      issues: [],
    }

  const { result } = planTrainingWeek(
    undefined,
    input.now ?? new Date().toISOString(),
    undefined,
    days
  )
  if (!("program" in result))
    return { status: "blocked", ...toPlanBlock(result) }

  useTrainingRecords.getState().saveProgram(result.program)
  const sessions = sessionViews(result.program)
  projectPlannedWorkouts(sessions)
  return {
    status: "created",
    programId: result.program.id,
    sessions,
    issues: result.issues,
  }
}

/** Creates one plan from exact calendar dates. Dates may span several weeks;
 * each week is solved by the engine, then stored as one immutable plan. */
export function createTrainingPlanForDates(input: {
  dates: readonly string[]
  now?: string
  sourceProgramId?: string
}): TrainingWeekOutcome {
  const now = input.now ?? new Date().toISOString()
  const today = now.slice(0, 10)
  const dates = [...new Set(input.dates)]
    .filter(
      (date) =>
        /^\d{4}-\d{2}-\d{2}$/.test(date) &&
        new Date(`${date}T00:00:00.000Z`).toISOString().slice(0, 10) === date &&
        date >= today
    )
    .sort()
  if (!dates.length)
    return {
      status: "blocked",
      reason: "days",
      message: "Pick at least one training date.",
      page: null,
      issues: [],
    }

  const groups = new Map<string, string[]>()
  for (const date of dates) {
    const day = new Date(`${date}T00:00:00.000Z`)
    day.setUTCDate(day.getUTCDate() - ((day.getUTCDay() + 6) % 7))
    const monday = day.toISOString()
    groups.set(monday, [...(groups.get(monday) ?? []), date])
  }
  const programs: TrainingProgram[] = []
  const issues: PlanningIssue[] = []
  for (const [weekStart, weekDates] of groups) {
    const request = buildTrainingRequest(
      buildTrainingEngineInputs(),
      now,
      undefined,
      weekDates.map((date) =>
        Math.round(
          (Date.parse(`${date}T00:00:00.000Z`) - Date.parse(weekStart)) /
            86_400_000
        )
      )
    )
    request.schedule.weekStart = weekStart
    const result = generateTrainingProgram(request)
    if (!("program" in result)) return { status: "blocked", ...toPlanBlock(result) }
    programs.push(result.program)
    issues.push(...result.issues)
  }

  const program = structuredClone(programs[0])
  program.id = `program-${crypto.randomUUID()}`
  program.generatedAt = now
  program.weeks = programs.map((item, index) => {
    const week = structuredClone(item.weeks[0])
    const oldWeekId = week.id
    week.id = `week-${index}`
    for (const [sessionIndex, session] of week.sessions.entries()) {
      const oldSessionId = session.id
      session.id = `${week.id}/session-${sessionIndex}`
      for (const exercise of session.exercises)
        for (const set of [...exercise.workingSets, ...exercise.warmupSets])
          set.id = set.id.replace(oldSessionId, session.id).replace(oldWeekId, week.id)
    }
    return week
  })
  program.durationWeeks = program.weeks.length
  namespaceProgramIds(program, program.id)
  const source = input.sourceProgramId
    ? useTrainingRecords.getState().data.programs.find(
        (item) => item.id === input.sourceProgramId
      )
    : undefined
  useTrainingRecords.getState().saveProgram(program, {
    manualSourceProgramId: source?.id,
  })
  const sessions = sessionViews(program)
  projectPlannedWorkouts(sessions)
  return {
    status: "created",
    programId: program.id,
    sessions,
    issues,
  }
}

/** A compact reading of one prescribed exercise: `3 × 8–12 · RIR 2 · 80 kg`. */
export function formatPrescription(item: PlannedExercisePrescription) {
  const reps =
    item.reps.min === item.reps.max
      ? `${item.reps.max}`
      : `${item.reps.min}–${item.reps.max}`
  return [
    `${item.sets} × ${reps}`,
    `RIR ${item.rir}`,
    ...(item.loadKg === null
      ? []
      : [
          `${formatKg(item.loadKg)} kg${item.loadBasis === "per_implement" ? " each" : ""}`,
        ]),
    `${Math.round(item.restSeconds)}s rest`,
  ].join(" · ")
}

/** The muscles a planned session loads, for the body preview the workout list
 *  already draws beside every other row. */
export function plannedSessionMuscles(view: PlannedSessionView): MuscleId[] {
  return musclesForExerciseIds(view.exerciseIds)
}
