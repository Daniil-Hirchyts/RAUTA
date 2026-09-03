import {
  currentExercise,
  elapsedMs,
  sessionProgress,
  type ActiveWorkoutSession,
} from "@/lib/active-workout"
import { formatDateLong } from "@/lib/date"
import { liveActivity, type LiveActivityContent } from "@/lib/live-activity"
import { titleCase } from "@/lib/text"
import { useActiveWorkout } from "@/store/use-active-workout"

/** The Live Activity frame for a session. Pure: same session, same frame. */
export function liveActivityContent(
  session: ActiveWorkoutSession
): LiveActivityContent {
  const exercise = currentExercise(session)
  const { completed, total } = sessionProgress(session)
  const isPaused = session.runningSince === null

  return {
    workoutId: session.workoutId,
    workoutDate: formatDateLong(session.workoutDate),
    exerciseName: exercise ? titleCase(exercise.name) : "All exercises done",
    completedCount: completed,
    totalCount: total,
    timerStartEpochMs: isPaused
      ? 0
      : (session.runningSince ?? 0) - session.accumulatedMs,
    elapsedMs: isPaused ? session.accumulatedMs : 0,
    isPaused,
  }
}

/** The closing frame: the timer stops and the progress reads as final. */
function endContent(session: ActiveWorkoutSession): LiveActivityContent {
  return {
    ...liveActivityContent(session),
    exerciseName: "Workout complete",
    timerStartEpochMs: 0,
    elapsedMs: elapsedMs(session),
    isPaused: true,
  }
}

/**
 * Mirrors the workout store onto the native ActivityKit lifecycle: one start
 * when a workout begins, an update whenever a frame would actually differ,
 * and one end when it stops. Returns the unsubscribe function.
 */
export function startLiveActivitySync() {
  let lastFrame: string | null = null
  let lastWorkoutId: string | null = null

  const render = (session: ActiveWorkoutSession) => {
    const content = liveActivityContent(session)
    const frame = JSON.stringify(content)
    if (frame === lastFrame) return

    // The first frame of a session starts the activity — which on the native
    // side adopts a card that outlived the last launch, so a session restored
    // from storage reconnects instead of orphaning it. Switching to a different
    // workout also starts: the card's workout name lives in ActivityKit
    // attributes, which are fixed for the life of an activity.
    const needsStart = lastWorkoutId !== content.workoutId
    lastFrame = frame
    lastWorkoutId = content.workoutId

    void (needsStart
      ? liveActivity.start(content)
      : liveActivity.update(content))
  }

  const stop = (session: ActiveWorkoutSession, dismissImmediately: boolean) => {
    if (lastFrame === null) return
    lastFrame = null
    lastWorkoutId = null
    void liveActivity.end({
      ...endContent(session),
      dismissImmediately,
    })
  }

  const initial = useActiveWorkout.getState().session
  if (initial) render(initial)

  return useActiveWorkout.subscribe((state, previous) => {
    if (state.session === previous.session) return

    if (state.session) render(state.session)
    else if (previous.session) {
      stop(previous.session, state.lastOutcome !== "finished")
    }
  })
}
