import { describe, expect, it } from "vitest"

import { workoutShareContent } from "@/lib/workout-sharing"
import type { Workout } from "@/store/use-workouts"

describe("workout sharing", () => {
  it("exports an ordered, readable exercise list", () => {
    const workout: Workout = {
      id: "workout",
      name: "Workout",
      date: "2026-09-01",
      exerciseIds: ["0001", "0002"],
      completion: null,
      createdAt: "2026-08-31T00:00:00.000Z",
      updatedAt: "2026-08-31T00:00:00.000Z",
    }

    const content = workoutShareContent(workout)

    expect(content.title).toBe("RAUTA workout — Tuesday, September 1")
    expect(content.text).toContain("1. 3/4 Sit-Up\n   Body Weight")
    expect(content.text).toContain("2. 45° Side Bend\n   Body Weight")
    expect(content.text).toMatch(/Shared from RAUTA$/)
  })
})
