import { describe, expect, it } from "vitest"

import {
  elapsedMs,
  exerciseStatus,
  formatDuration,
  nextPendingExerciseId,
  sessionProgress,
  timerStartEpochMs,
  type ActiveWorkoutSession,
} from "@/lib/active-workout"

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

describe("formatDuration", () => {
  it("stays at minutes and seconds below an hour", () => {
    expect(formatDuration(0)).toBe("00:00")
    expect(formatDuration(9_400)).toBe("00:09")
    expect(formatDuration(61_000)).toBe("01:01")
    expect(formatDuration(59 * 60_000 + 59_000)).toBe("59:59")
  })

  it("widens to hours only once the workout passes one", () => {
    expect(formatDuration(3_600_000)).toBe("1:00:00")
    expect(formatDuration(3_600_000 + 125_000)).toBe("1:02:05")
  })

  it("never renders a negative clock", () => {
    expect(formatDuration(-5_000)).toBe("00:00")
  })
})

describe("elapsedMs", () => {
  it("counts the running stretch on top of banked time", () => {
    const running = session({ runningSince: 1_000_000, accumulatedMs: 30_000 })
    expect(elapsedMs(running, 1_005_000)).toBe(35_000)
  })

  it("freezes at the banked time while paused", () => {
    const paused = session({ runningSince: null, accumulatedMs: 42_000 })
    expect(elapsedMs(paused, 9_999_999)).toBe(42_000)
  })

  it("reports the instant a stopwatch would have had to start", () => {
    const running = session({ runningSince: 1_000_000, accumulatedMs: 30_000 })
    // A pause banked 30s, so "now" must read 35s after five more seconds.
    expect(timerStartEpochMs(running, 1_005_000)).toBe(970_000)
  })
})

describe("exerciseStatus", () => {
  it("separates the current exercise from done and not-yet", () => {
    const current = session({ completedIds: ["0002"] })

    expect(exerciseStatus(current, "0001")).toBe("active")
    expect(exerciseStatus(current, "0002")).toBe("completed")
    expect(exerciseStatus(current, "0003")).toBe("pending")
  })
})

describe("sessionProgress", () => {
  it("counts only completions still in the workout", () => {
    const current = session({ completedIds: ["0002", "0099"] })
    expect(sessionProgress(current)).toEqual({
      completed: 1,
      total: 3,
      isComplete: false,
    })
  })

  it("is complete once every exercise is checked off", () => {
    const done = session({ completedIds: ["0001", "0002", "0003"] })
    expect(sessionProgress(done).isComplete).toBe(true)
  })

  it("is never complete without exercises", () => {
    const empty = session({ exerciseIds: [], completedIds: [] })
    expect(sessionProgress(empty).isComplete).toBe(false)
  })
})

describe("nextPendingExerciseId", () => {
  it("moves to the next exercise still to be done", () => {
    expect(nextPendingExerciseId(session(), "0001")).toBe("0002")
  })

  it("steps over exercises already completed", () => {
    const current = session({ completedIds: ["0002"] })
    expect(nextPendingExerciseId(current, "0001")).toBe("0003")
  })

  it("wraps around to pick up an exercise that was skipped", () => {
    const current = session({ currentExerciseId: "0003" })
    expect(nextPendingExerciseId(current, "0003")).toBe("0001")
  })

  it("returns nothing when the workout is finished", () => {
    const done = session({ completedIds: ["0001", "0002", "0003"] })
    expect(nextPendingExerciseId(done, "0003")).toBeNull()
  })
})
