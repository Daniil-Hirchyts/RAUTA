import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import type { ActiveWorkoutSession } from "@/lib/active-workout"
import {
  liveActivityContent,
  startLiveActivitySync,
} from "@/lib/live-activity-sync"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useWorkouts, type Workout } from "@/store/use-workouts"

vi.mock("@/lib/live-activity", () => ({
  liveActivity: {
    isSupported: vi.fn(async () => true),
    start: vi.fn(async () => ({ activityId: "activity-1" })),
    update: vi.fn(async () => undefined),
    end: vi.fn(async () => undefined),
  },
}))

const { liveActivity } = await import("@/lib/live-activity")

const workout: Workout = {
  id: "workout-1",
  date: "2026-09-01",
  exerciseIds: ["0001", "0002", "0003"],
  completion: null,
  createdAt: "2026-09-01T08:00:00.000Z",
  updatedAt: "2026-09-01T08:00:00.000Z",
}

function session(patch: Partial<ActiveWorkoutSession> = {}) {
  return {
    workoutId: "workout-1",
    workoutDate: "2026-09-01",
    exerciseIds: ["0001", "0002", "0003"],
    completedIds: [],
    currentExerciseId: "0001",
    runningSince: 1_000_000,
    accumulatedMs: 0,
    startedAt: 1_000_000,
    ...patch,
  } satisfies ActiveWorkoutSession
}

let stop = () => {}

describe("liveActivityContent", () => {
  it("describes the exercise in progress without sending artwork", () => {
    expect(liveActivityContent(session())).toMatchObject({
      workoutId: "workout-1",
      workoutDate: "Tuesday, September 1",
      exerciseName: "3/4 Sit-Up",
      completedCount: 0,
      totalCount: 3,
      isPaused: false,
    })
  })

  it("hands ActivityKit an instant to count from, not a duration", () => {
    const content = liveActivityContent(
      session({ runningSince: 1_000_000, accumulatedMs: 30_000 })
    )

    expect(content.timerStartEpochMs).toBe(970_000)
    expect(content.elapsedMs).toBe(0)
  })

  it("sends a frozen elapsed time instead once paused", () => {
    const content = liveActivityContent(
      session({ runningSince: null, accumulatedMs: 42_000 })
    )

    expect(content).toMatchObject({
      isPaused: true,
      timerStartEpochMs: 0,
      elapsedMs: 42_000,
    })
  })

  it("is a pure function of the session, so identical frames compare equal", () => {
    const current = session()
    expect(liveActivityContent(current)).toEqual(liveActivityContent(current))
  })

  it("reports the finished state when nothing is left to do", () => {
    const done = session({
      completedIds: ["0001", "0002", "0003"],
      currentExerciseId: null,
    })

    expect(liveActivityContent(done)).toMatchObject({
      exerciseName: "All exercises done",
      completedCount: 3,
    })
  })
})

describe("startLiveActivitySync", () => {
  beforeEach(() => {
    localStorage.clear()
    // Finishing a workout writes its completion back to the workouts store,
    // and a session whose workout is missing from there is treated as orphaned
    // — so the workout being performed has to actually be saved.
    useWorkouts.setState({ workouts: [workout] })
    useActiveWorkout.setState({ session: null, lastOutcome: null })
    vi.mocked(liveActivity.start).mockClear()
    vi.mocked(liveActivity.update).mockClear()
    vi.mocked(liveActivity.end).mockClear()
    stop = startLiveActivitySync()
  })

  afterEach(() => stop())

  it("starts one activity when a workout begins", () => {
    useActiveWorkout.getState().start(workout)

    expect(liveActivity.start).toHaveBeenCalledOnce()
    expect(liveActivity.start).toHaveBeenCalledWith(
      expect.objectContaining({ exerciseName: "3/4 Sit-Up", completedCount: 0 })
    )
    expect(liveActivity.update).not.toHaveBeenCalled()
  })

  it("updates on every change the card would show", () => {
    useActiveWorkout.getState().start(workout)
    useActiveWorkout.getState().completeCurrent()
    useActiveWorkout.getState().pause()

    expect(liveActivity.update).toHaveBeenCalledTimes(2)
    expect(liveActivity.update).toHaveBeenLastCalledWith(
      expect.objectContaining({ isPaused: true, completedCount: 1 })
    )
  })

  it("sends no artwork fields while the workout changes", () => {
    useActiveWorkout.getState().start(workout)
    useActiveWorkout.getState().pause()
    useActiveWorkout.getState().completeCurrent()

    for (const [payload] of [
      ...vi.mocked(liveActivity.start).mock.calls,
      ...vi.mocked(liveActivity.update).mock.calls,
    ]) {
      expect(payload).not.toHaveProperty("exerciseId")
      expect(payload).not.toHaveProperty("frameIndex")
      expect(payload).not.toHaveProperty("muscleMapKey")
      expect(payload).not.toHaveProperty("muscleMapPng")
    }
  })

  it("skips a store change that would not alter the card", () => {
    useActiveWorkout.getState().start(workout)
    // Already the current exercise, and already not completed.
    useActiveWorkout.getState().setCurrentExercise("0001")

    expect(liveActivity.update).not.toHaveBeenCalled()
  })

  it("lets a finished workout linger on the Lock Screen", () => {
    useActiveWorkout.getState().start(workout)
    useActiveWorkout.getState().finish()

    expect(liveActivity.end).toHaveBeenCalledWith(
      expect.objectContaining({
        dismissImmediately: false,
        exerciseName: "Workout complete",
        isPaused: true,
      })
    )
  })

  it("dismisses a discarded workout at once", () => {
    useActiveWorkout.getState().start(workout)
    useActiveWorkout.getState().cancel()

    expect(liveActivity.end).toHaveBeenCalledWith(
      expect.objectContaining({ dismissImmediately: true })
    )
  })

  it("starts a new card when a different workout takes over", () => {
    useActiveWorkout.getState().start(workout)
    useActiveWorkout.getState().start({ ...workout, id: "workout-2" })

    expect(liveActivity.update).not.toHaveBeenCalled()
    expect(liveActivity.start).toHaveBeenCalledTimes(2)
    expect(liveActivity.start).toHaveBeenLastCalledWith(
      expect.objectContaining({
        workoutId: "workout-2",
      })
    )
  })

  it("adopts a session restored from storage", () => {
    stop()
    useActiveWorkout.setState({ session: session(), lastOutcome: null })

    stop = startLiveActivitySync()
    expect(liveActivity.start).toHaveBeenCalledOnce()
  })

  it("stops mirroring once unsubscribed", () => {
    stop()
    useActiveWorkout.getState().start(workout)

    expect(liveActivity.start).not.toHaveBeenCalled()
  })
})
