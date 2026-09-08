import { describe, expect, it } from "vitest"

import { buildStreak, STREAK_DAYS } from "@/lib/streak"
import type { Workout } from "@/store/use-workouts"

// A Thursday, so the strip has days behind it and days still ahead.
const TODAY = new Date(2026, 8, 3)

function makeWorkout(date: string, exercises = 1): Workout {
  return {
    id: `${date}-${exercises}`,
    name: "Session",
    date,
    exerciseIds: Array.from({ length: exercises }, (_, index) => `${index}`),
    completion: null,
    createdAt: "",
    updatedAt: "",
  }
}

describe("buildStreak", () => {
  it("spans the Monday-first week today falls in", () => {
    const { week } = buildStreak([], TODAY)

    expect(week).toHaveLength(STREAK_DAYS)
    expect(week[0].date).toBe("2026-08-31")
    expect(week.at(-1)?.date).toBe("2026-09-06")
    expect(week.map((day) => day.isToday)).toEqual([
      false,
      false,
      false,
      true,
      false,
      false,
      false,
    ])
  })

  it("marks the rest of the week as future, not as rest days", () => {
    expect(buildStreak([], TODAY).week.map((day) => day.isFuture)).toEqual([
      false,
      false,
      false,
      false,
      true,
      true,
      true,
    ])
  })

  it("adds up every workout logged on a day", () => {
    const { week, weekWorkouts } = buildStreak(
      [makeWorkout("2026-09-01", 4), makeWorkout("2026-09-01", 3)],
      TODAY
    )

    expect(week[1]).toMatchObject({ workouts: 2, exercises: 7 })
    expect(weekWorkouts).toBe(2)
  })

  it("counts the run of consecutive days ending today", () => {
    const streak = buildStreak(
      [
        makeWorkout("2026-09-03"),
        makeWorkout("2026-09-02"),
        makeWorkout("2026-09-01"),
        // A missed day ends the earlier run.
        makeWorkout("2026-08-30"),
        makeWorkout("2026-08-29"),
      ],
      TODAY
    )

    expect(streak.currentStreak).toBe(3)
    expect(streak.longestStreak).toBe(3)
  })

  it("waits out today before ending a streak", () => {
    const alive = buildStreak(
      [makeWorkout("2026-09-02"), makeWorkout("2026-09-01")],
      TODAY
    )
    expect(alive.currentStreak).toBe(2)

    // Nothing today and nothing yesterday: the run is over.
    const lapsed = buildStreak([makeWorkout("2026-09-01")], TODAY)
    expect(lapsed.currentStreak).toBe(0)
    expect(lapsed.longestStreak).toBe(1)
  })

  it("keeps the longest run from any point in the history", () => {
    const streak = buildStreak(
      [
        makeWorkout("2026-09-03"),
        makeWorkout("2025-01-04"),
        makeWorkout("2025-01-03"),
        makeWorkout("2025-01-02"),
        makeWorkout("2025-01-01"),
      ],
      TODAY
    )

    expect(streak.currentStreak).toBe(1)
    expect(streak.longestStreak).toBe(4)
  })

  it("counts a day once however many workouts it holds", () => {
    const streak = buildStreak(
      [makeWorkout("2026-09-03"), makeWorkout("2026-09-03")],
      TODAY
    )

    expect(streak.currentStreak).toBe(1)
  })
})
