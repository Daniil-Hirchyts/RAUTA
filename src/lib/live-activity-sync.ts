import {
  currentExercise,
  elapsedMs,
  sessionProgress,
  type ActiveWorkoutSession,
} from "@/lib/active-workout"
import { formatDateLong } from "@/lib/date"
import {
  liveActivity,
  type LiveActivityContent,
  type LiveActivityPayload,
} from "@/lib/live-activity"
import { muscleMapKey, muscleMapPng } from "@/lib/muscle-map-image"
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
    workoutName: session.workoutName,
    workoutDate: formatDateLong(session.workoutDate),
    exerciseId: exercise?.id ?? "",
    exerciseName: exercise ? titleCase(exercise.name) : "All exercises done",
    muscleMapKey: exercise ? muscleMapKey(exercise.muscles) : "",
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
    muscleMapKey: "",
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
  let lastExerciseId: string | null = null
  let frameIndex = 0

  const render = (session: ActiveWorkoutSession) => {
    const content = liveActivityContent(session)
    const exercise = currentExercise(session)
    // Rasterizing a muscle map is asynchronous, so the first frame of a new
    // exercise goes out without one and the map arrives with the next — which
    // this schedules itself, since nothing else about the session will have
    // changed by then.
    const map = exercise
      ? muscleMapPng(exercise.muscles, () => {
          const current = useActiveWorkout.getState().session
          if (current) render(current)
        })
      : null

    const frame = JSON.stringify({ ...content, hasMap: map !== null })
    if (frame === lastFrame) return

    // The first frame of a session starts the activity — which on the native
    // side adopts a card that outlived the last launch, so a session restored
    // from storage reconnects instead of orphaning it. Switching to a different
    // workout also starts: the card's workout name lives in ActivityKit
    // attributes, which are fixed for the life of an activity.
    const needsStart = lastWorkoutId !== content.workoutId
    lastFrame = frame
    lastWorkoutId = content.workoutId

    // Every update steps the demonstration one still further through the
    // movement, and a new exercise starts its own at the beginning. It is the
    // only motion a Live Activity can be given: the card is redrawn when the
    // content state changes and at no other time.
    frameIndex = content.exerciseId === lastExerciseId ? frameIndex + 1 : 0
    lastExerciseId = content.exerciseId

    const payload: LiveActivityPayload = {
      ...content,
      frameIndex,
      muscleMapPng: map ?? "",
    }
    void (needsStart
      ? liveActivity.start(payload)
      : liveActivity.update(payload))
  }

  const stop = (session: ActiveWorkoutSession, dismissImmediately: boolean) => {
    if (lastFrame === null) return
    lastFrame = null
    lastWorkoutId = null
    lastExerciseId = null
    frameIndex = 0
    void liveActivity.end({
      ...endContent(session),
      frameIndex: 0,
      muscleMapPng: "",
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
