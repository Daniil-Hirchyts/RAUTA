import { beforeEach, describe, expect, it } from "vitest"

import { toISODate } from "@/lib/date"
import { useWorkouts } from "@/store/use-workouts"

describe("workouts store", () => {
  beforeEach(() => {
    localStorage.clear()
    useWorkouts.setState({ workouts: [] })
  })

  it("creates a workout", () => {
    const id = useWorkouts.getState().createWorkout({
      date: "2026-09-01",
      exerciseIds: ["0001", "0002", "0001"],
    })

    const workout = useWorkouts.getState().workouts.find((w) => w.id === id)
    expect(workout).toMatchObject({
      date: "2026-09-01",
      exerciseIds: ["0001", "0002"],
    })
  })

  it("updates a workout", () => {
    const id = useWorkouts.getState().createWorkout({
      date: "2026-09-01",
      exerciseIds: ["0001"],
    })

    useWorkouts.getState().updateWorkout(id, { date: "2026-09-05" })

    const workout = useWorkouts.getState().workouts.find((w) => w.id === id)
    expect(workout?.date).toBe("2026-09-05")
  })

  it("deletes a workout", () => {
    const id = useWorkouts.getState().createWorkout({
      date: "2026-09-01",
      exerciseIds: ["0001"],
    })

    useWorkouts.getState().deleteWorkout(id)
    expect(useWorkouts.getState().workouts).toEqual([])
  })

  it("duplicates a workout as a new copy", () => {
    const id = useWorkouts.getState().createWorkout({
      date: "2026-09-01",
      exerciseIds: ["0001", "0002"],
    })

    const copyId = useWorkouts.getState().duplicateWorkout(id)
    expect(copyId).not.toBe(id)
    expect(useWorkouts.getState().workouts).toHaveLength(2)

    const copy = useWorkouts.getState().workouts.find((w) => w.id === copyId)
    expect(copy?.exerciseIds).toEqual(["0001", "0002"])
    expect(copy?.date).toBe(toISODate(new Date()))
    expect(copy?.completion).toBeNull()
  })

  it("returns null when duplicating a missing workout", () => {
    expect(useWorkouts.getState().duplicateWorkout("missing")).toBeNull()
  })

  it("migrates and sanitizes persisted workouts", async () => {
    localStorage.setItem(
      "gym-lib-workouts",
      JSON.stringify({
        state: {
          workouts: [
            {
              id: "valid",
              name: "Legacy name is discarded",
              date: "2026-09-01",
              exerciseIds: ["0001", "missing", "0001"],
              createdAt: "2026-08-01T00:00:00.000Z",
              updatedAt: "2026-08-01T00:00:00.000Z",
            },
            { id: "missing-date", exerciseIds: ["0001"] },
          ],
        },
        version: 0,
      })
    )

    await useWorkouts.persist.rehydrate()

    expect(useWorkouts.persist.getOptions().version).toBe(3)
    expect(useWorkouts.getState().workouts).toEqual([
      {
        id: "valid",
        date: "2026-09-01",
        exerciseIds: ["0001"],
        completion: null,
        createdAt: "2026-08-01T00:00:00.000Z",
        updatedAt: "2026-08-01T00:00:00.000Z",
      },
    ])
  })

  it("records completion stats and clears them when copied to today", () => {
    const id = useWorkouts.getState().createWorkout({
      date: "2026-09-01",
      exerciseIds: ["0001", "0002"],
    })
    useWorkouts.getState().completeWorkout(id, {
      activeCalories: 120,
      completedAt: "2026-09-01T10:30:00.000Z",
      completedExerciseIds: ["0001"],
      durationMs: 30 * 60_000,
      healthSyncStatus: "synced",
      startedAt: "2026-09-01T10:00:00.000Z",
    })

    const copyId = useWorkouts.getState().duplicateWorkout(id)!
    const source = useWorkouts
      .getState()
      .workouts.find((item) => item.id === id)
    const copy = useWorkouts
      .getState()
      .workouts.find((item) => item.id === copyId)

    expect(source?.completion).toMatchObject({
      activeCalories: 120,
      durationMs: 30 * 60_000,
      healthSyncStatus: "synced",
    })
    expect(copy).toMatchObject({
      completion: null,
      date: toISODate(new Date()),
      exerciseIds: ["0001", "0002"],
    })
  })
})
