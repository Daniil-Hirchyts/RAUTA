import { beforeEach, describe, expect, it, vi } from "vitest"

import { saveCompletedWorkoutToHealth } from "@/lib/health"
import { startAppleHealthSync } from "@/lib/health-sync"
import { useActiveWorkout } from "@/store/use-active-workout"
import { DEFAULT_SETTINGS, useSettings } from "@/store/use-settings"
import { useWorkouts } from "@/store/use-workouts"

vi.mock("@/lib/health", () => ({
  saveCompletedWorkoutToHealth: vi.fn().mockResolvedValue(true),
}))

const session = {
  accumulatedMs: 15 * 60_000,
  completedIds: ["0001"],
  currentExerciseId: null,
  exerciseIds: ["0001"],
  runningSince: null,
  startedAt: new Date("2026-08-31T10:00:00Z").getTime(),
  workoutDate: "2026-08-31",
  workoutId: "workout-1",
}

describe("Apple Health sync", () => {
  beforeEach(() => {
    useWorkouts.setState({
      workouts: [
        {
          completion: null,
          createdAt: "2026-08-31T09:00:00.000Z",
          date: "2026-08-31",
          exerciseIds: ["0001"],
          id: "workout-1",
          updatedAt: "2026-08-31T09:00:00.000Z",
        },
      ],
    })
    useActiveWorkout.setState({ lastOutcome: null, session: null })
    useSettings.setState({
      ...DEFAULT_SETTINGS,
      appleHealthEnabled: true,
      autoSyncWorkouts: true,
    })
  })

  it("writes an intentionally finished workout with duration and calories", async () => {
    const stop = startAppleHealthSync()
    useActiveWorkout.setState({ lastOutcome: null, session })
    useActiveWorkout.getState().finish()

    await vi.waitFor(() => {
      expect(saveCompletedWorkoutToHealth).toHaveBeenCalledWith({
        activeCalories: 118,
        endDate: "2026-08-31T10:15:00.000Z",
        startDate: "2026-08-31T10:00:00.000Z",
        workoutId: "workout-1",
      })
    })
    expect(
      useWorkouts.getState().workouts[0].completion?.healthSyncStatus
    ).toBe("synced")
    stop()
  })

  it("does not sync a discarded session", async () => {
    const stop = startAppleHealthSync()
    useActiveWorkout.setState({ lastOutcome: null, session })
    useActiveWorkout.getState().cancel()
    await Promise.resolve()

    expect(saveCompletedWorkoutToHealth).not.toHaveBeenCalled()
    stop()
  })
})
