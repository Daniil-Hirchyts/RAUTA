import { beforeEach, describe, expect, it, vi } from "vitest"

import { elapsedMs } from "@/lib/active-workout"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useWorkouts, type Workout } from "@/store/use-workouts"

const workout: Workout = {
  id: "workout-1",
  name: "Push day",
  date: "2026-09-01",
  exerciseIds: ["0001", "0002", "0003"],
  completion: null,
  createdAt: "2026-09-01T08:00:00.000Z",
  updatedAt: "2026-09-01T08:00:00.000Z",
}

function state() {
  return useActiveWorkout.getState()
}

function session() {
  const { session } = state()
  if (!session) throw new Error("expected a running session")
  return session
}

describe("useActiveWorkout", () => {
  beforeEach(() => {
    localStorage.clear()
    useWorkouts.setState({ workouts: [] })
    useActiveWorkout.setState({ session: null, lastOutcome: null })
  })

  it("starts on the first exercise with the clock running", () => {
    state().start(workout)

    expect(session()).toMatchObject({
      workoutId: "workout-1",
      workoutName: "Push day",
      exerciseIds: ["0001", "0002", "0003"],
      completedIds: [],
      currentExerciseId: "0001",
      accumulatedMs: 0,
    })
    expect(session().runningSince).not.toBeNull()
  })

  it("refuses to start a workout with nothing to perform", () => {
    state().start({ ...workout, exerciseIds: ["not-an-exercise"] })
    expect(state().session).toBeNull()
  })

  it("refuses to start a workout whose date has already passed", () => {
    state().start({ ...workout, date: "2026-08-31" })
    expect(state().session).toBeNull()
  })

  it("refuses to restart a completed workout", () => {
    state().start({
      ...workout,
      completion: {
        activeCalories: 80,
        completedAt: "2026-09-01T09:30:00.000Z",
        completedExerciseIds: ["0001"],
        durationMs: 30 * 60_000,
        healthSyncStatus: "not-requested",
        startedAt: "2026-09-01T09:00:00.000Z",
      },
    })
    expect(state().session).toBeNull()
  })

  it("advances to the next exercise as each one is completed", () => {
    state().start(workout)

    state().completeCurrent()
    expect(session()).toMatchObject({
      completedIds: ["0001"],
      currentExerciseId: "0002",
    })

    state().completeCurrent()
    state().completeCurrent()
    expect(session()).toMatchObject({
      completedIds: ["0001", "0002", "0003"],
      currentExerciseId: null,
    })
  })

  it("checks an exercise off from the list without losing the current one", () => {
    state().start(workout)

    state().toggleComplete("0003")
    expect(session()).toMatchObject({
      completedIds: ["0003"],
      currentExerciseId: "0001",
    })

    state().toggleComplete("0003")
    expect(session().completedIds).toEqual([])
  })

  it("makes an exercise current again when it is unchecked with none active", () => {
    state().start(workout)
    state().completeCurrent()
    state().completeCurrent()
    state().completeCurrent()

    state().toggleComplete("0002")
    expect(session()).toMatchObject({
      completedIds: ["0001", "0003"],
      currentExerciseId: "0002",
    })
  })

  it("treats re-selecting a finished exercise as doing it again", () => {
    state().start(workout)
    state().completeCurrent()

    state().setCurrentExercise("0001")
    expect(session()).toMatchObject({
      completedIds: [],
      currentExerciseId: "0001",
    })
  })

  it("banks elapsed time on pause and keeps counting on resume", () => {
    vi.useFakeTimers()
    try {
      vi.setSystemTime(new Date("2026-09-01T08:00:00.000Z"))
      state().start(workout)

      vi.advanceTimersByTime(30_000)
      state().pause()
      expect(session()).toMatchObject({
        accumulatedMs: 30_000,
        runningSince: null,
      })

      vi.advanceTimersByTime(5 * 60_000)
      expect(elapsedMs(session())).toBe(30_000)

      state().resume()
      vi.advanceTimersByTime(10_000)
      expect(elapsedMs(session())).toBe(40_000)
    } finally {
      vi.useRealTimers()
    }
  })

  it("ignores a second pause or resume", () => {
    state().start(workout)
    state().pause()
    const paused = session()

    state().pause()
    expect(state().session).toBe(paused)

    state().resume()
    const resumed = session()
    state().resume()
    expect(state().session).toBe(resumed)
  })

  it("records why the session stopped", () => {
    state().start(workout)
    state().finish()
    expect(state()).toMatchObject({ session: null, lastOutcome: "finished" })

    state().start(workout)
    expect(state().lastOutcome).toBeNull()

    state().cancel()
    expect(state()).toMatchObject({ session: null, lastOutcome: "cancelled" })
  })

  it("follows edits made to the workout it is running", () => {
    state().start(workout)
    state().completeCurrent()

    state().syncExercises(["0002", "0010"])
    expect(session()).toMatchObject({
      exerciseIds: ["0002", "0010"],
      completedIds: [],
      currentExerciseId: "0002",
    })
  })

  it("picks a new current exercise when the running one is removed", () => {
    state().start(workout)
    state().toggleComplete("0002")

    state().syncExercises(["0002", "0003"])
    expect(session()).toMatchObject({
      completedIds: ["0002"],
      currentExerciseId: "0003",
    })
  })

  it("ends the session when the workout is emptied out", () => {
    state().start(workout)
    state().syncExercises([])
    expect(state()).toMatchObject({ session: null, lastOutcome: "cancelled" })
  })

  it("does nothing when there is no session to act on", () => {
    state().pause()
    state().resume()
    state().completeCurrent()
    state().toggleComplete("0001")
    state().setCurrentExercise("0001")
    state().syncExercises(["0001"])
    expect(state().session).toBeNull()
  })

  it("drops a stored session whose exercises no longer exist", () => {
    localStorage.setItem(
      "gym-lib-active-workout",
      JSON.stringify({
        state: { session: { workoutId: "w", exerciseIds: ["nope"] } },
        version: 1,
      })
    )

    useActiveWorkout.persist.rehydrate()
    expect(state().session).toBeNull()
  })

  it("repairs a stored session with a stale current exercise", () => {
    localStorage.setItem(
      "gym-lib-active-workout",
      JSON.stringify({
        state: {
          session: {
            workoutId: "workout-1",
            workoutName: "  ",
            workoutDate: "2026-09-01",
            exerciseIds: ["0001", "0002", "nope"],
            completedIds: ["0001", "0099"],
            currentExerciseId: "nope",
            runningSince: -1,
            accumulatedMs: Number.NaN,
            startedAt: 1_000_000,
          },
        },
        version: 1,
      })
    )

    useActiveWorkout.persist.rehydrate()
    expect(session()).toMatchObject({
      workoutName: "Workout",
      exerciseIds: ["0001", "0002"],
      completedIds: ["0001"],
      currentExerciseId: null,
      runningSince: null,
      accumulatedMs: 0,
    })
  })

  it("ends a session whose workout is deleted from anywhere in the app", () => {
    const workoutId = useWorkouts.getState().createWorkout({
      name: "Push day",
      date: "2026-09-01",
      exerciseIds: ["0001", "0002"],
    })
    state().start({ ...workout, id: workoutId })

    useWorkouts.getState().deleteWorkout(workoutId)
    expect(state()).toMatchObject({ session: null, lastOutcome: "cancelled" })
  })

  it("follows the workout to another date while it is being performed", () => {
    const workoutId = useWorkouts.getState().createWorkout({
      name: "Push day",
      date: "2026-09-01",
      exerciseIds: ["0001", "0002"],
    })
    state().start({ ...workout, id: workoutId })

    useWorkouts.getState().updateWorkout(workoutId, { date: "2026-09-04" })
    expect(session().workoutDate).toBe("2026-09-04")
  })

  it("picks up an exercise added to the workout from elsewhere", () => {
    const workoutId = useWorkouts.getState().createWorkout({
      name: "Push day",
      date: "2026-09-01",
      exerciseIds: ["0001"],
    })
    state().start({ ...workout, id: workoutId, exerciseIds: ["0001"] })

    useWorkouts
      .getState()
      .updateWorkout(workoutId, { exerciseIds: ["0001", "0002"] })
    expect(session()).toMatchObject({
      exerciseIds: ["0001", "0002"],
      currentExerciseId: "0001",
    })
  })

  it("leaves the session alone when a different workout is deleted", () => {
    const running = useWorkouts.getState().createWorkout({
      name: "Push day",
      date: "2026-09-01",
      exerciseIds: ["0001"],
    })
    const other = useWorkouts.getState().createWorkout({
      name: "Pull day",
      date: "2026-09-02",
      exerciseIds: ["0002"],
    })
    state().start({ ...workout, id: running })

    useWorkouts.getState().deleteWorkout(other)
    expect(state().session?.workoutId).toBe(running)
  })
})
