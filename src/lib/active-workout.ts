import { EXERCISES_BY_ID } from "@/lib/exercises"

/**
 * A workout being performed right now. The timer is stored as a running
 * stretch plus banked time rather than a tick count, so it survives a reload,
 * a backgrounded app, and a suspended web view without drifting — and so the
 * native Live Activity can be handed a single start instant and left to count
 * on its own (see {@link timerStartEpochMs}).
 */
export type ActiveWorkoutSession = {
  workoutId: string
  workoutDate: string
  exerciseIds: string[]
  completedIds: string[]
  currentExerciseId: string | null
  /** Epoch ms the current running stretch began; null while paused. */
  runningSince: number | null
  /** Elapsed time banked by every stretch before the current one. */
  accumulatedMs: number
  startedAt: number
}

export type ExerciseStatus = "pending" | "active" | "completed"

export function elapsedMs(session: ActiveWorkoutSession, now = Date.now()) {
  const running = session.runningSince ? now - session.runningSince : 0
  return Math.max(0, session.accumulatedMs + running)
}

/**
 * The instant a stopwatch would have to have been started for it to read
 * {@link elapsedMs} right now. ActivityKit's `Text(timerInterval:)` counts
 * from a date entirely on its own, so shifting that date is how a paused and
 * resumed workout stays correct without pushing an update every second.
 */
export function timerStartEpochMs(
  session: ActiveWorkoutSession,
  now = Date.now()
) {
  return now - elapsedMs(session, now)
}

/** "MM:SS", widening to "H:MM:SS" only once the workout passes an hour. */
export function formatDuration(ms: number) {
  const totalSeconds = Math.max(0, Math.floor(ms / 1000))
  const seconds = totalSeconds % 60
  const minutes = Math.floor(totalSeconds / 60) % 60
  const hours = Math.floor(totalSeconds / 3600)
  const pad = (value: number) => String(value).padStart(2, "0")

  return hours > 0
    ? `${hours}:${pad(minutes)}:${pad(seconds)}`
    : `${pad(minutes)}:${pad(seconds)}`
}

export function exerciseStatus(
  session: ActiveWorkoutSession,
  exerciseId: string
): ExerciseStatus {
  if (session.completedIds.includes(exerciseId)) return "completed"
  return session.currentExerciseId === exerciseId ? "active" : "pending"
}

export function sessionProgress(session: ActiveWorkoutSession) {
  const completed = session.exerciseIds.filter((id) =>
    session.completedIds.includes(id)
  ).length

  return {
    completed,
    total: session.exerciseIds.length,
    isComplete:
      session.exerciseIds.length > 0 &&
      completed === session.exerciseIds.length,
  }
}

/**
 * The exercise to move to after `fromId` is done: the next one still pending
 * in list order, wrapping past the end so an exercise skipped earlier is
 * picked up rather than stranded. Null once nothing is left.
 */
export function nextPendingExerciseId(
  session: ActiveWorkoutSession,
  fromId: string | null = session.currentExerciseId
) {
  const { exerciseIds, completedIds } = session
  const start = fromId ? exerciseIds.indexOf(fromId) : -1

  for (let step = 1; step <= exerciseIds.length; step += 1) {
    const id =
      exerciseIds[(start + step + exerciseIds.length) % exerciseIds.length]
    if (id && id !== fromId && !completedIds.includes(id)) return id
  }

  return null
}

export function currentExercise(session: ActiveWorkoutSession) {
  return session.currentExerciseId
    ? (EXERCISES_BY_ID.get(session.currentExerciseId) ?? null)
    : null
}
