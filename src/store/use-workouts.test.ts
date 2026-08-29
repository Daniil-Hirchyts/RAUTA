import { beforeEach, describe, expect, it } from "vitest"

import { useWorkouts } from "@/store/use-workouts"

describe("workouts store", () => {
  beforeEach(() => {
    localStorage.clear()
    useWorkouts.setState({ workouts: [] })
  })

  it("creates a workout", () => {
    const id = useWorkouts.getState().createWorkout({
      name: "Push day",
      date: "2026-09-01",
      exerciseIds: ["0001", "0002", "0001"],
    })

    const workout = useWorkouts.getState().workouts.find((w) => w.id === id)
    expect(workout).toMatchObject({
      name: "Push day",
      date: "2026-09-01",
      exerciseIds: ["0001", "0002"],
    })
  })

  it("updates a workout", () => {
    const id = useWorkouts.getState().createWorkout({
      name: "Push day",
      date: "2026-09-01",
      exerciseIds: ["0001"],
    })

    useWorkouts
      .getState()
      .updateWorkout(id, { name: "Push day v2", date: "2026-09-05" })

    const workout = useWorkouts.getState().workouts.find((w) => w.id === id)
    expect(workout?.name).toBe("Push day v2")
    expect(workout?.date).toBe("2026-09-05")
  })

  it("deletes a workout", () => {
    const id = useWorkouts.getState().createWorkout({
      name: "Push day",
      date: "2026-09-01",
      exerciseIds: ["0001"],
    })

    useWorkouts.getState().deleteWorkout(id)
    expect(useWorkouts.getState().workouts).toEqual([])
  })

  it("duplicates a workout as a new copy", () => {
    const id = useWorkouts.getState().createWorkout({
      name: "Push day",
      date: "2026-09-01",
      exerciseIds: ["0001", "0002"],
    })

    const copyId = useWorkouts.getState().duplicateWorkout(id)
    expect(copyId).not.toBe(id)
    expect(useWorkouts.getState().workouts).toHaveLength(2)

    const copy = useWorkouts.getState().workouts.find((w) => w.id === copyId)
    expect(copy?.name).toBe("Push day copy")
    expect(copy?.exerciseIds).toEqual(["0001", "0002"])
    expect(copy?.date).toBe("2026-09-01")
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
              name: "  Training  ",
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

    expect(useWorkouts.persist.getOptions().version).toBe(1)
    expect(useWorkouts.getState().workouts).toEqual([
      {
        id: "valid",
        name: "Training",
        date: "2026-09-01",
        exerciseIds: ["0001"],
        createdAt: "2026-08-01T00:00:00.000Z",
        updatedAt: "2026-08-01T00:00:00.000Z",
      },
    ])
  })
})
