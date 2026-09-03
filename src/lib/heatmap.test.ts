import { describe, expect, it } from "vitest"

import { buildHeatmap, HEATMAP_WEEKS } from "@/lib/heatmap"
import type { Workout } from "@/store/use-workouts"

// A Monday, so the final column of the matrix starts on "today".
const TODAY = new Date(2026, 7, 31)

function makeWorkout(date: string, exercises = 1): Workout {
  return {
    id: `${date}-${exercises}`,
    date,
    exerciseIds: Array.from({ length: exercises }, (_, index) => `${index}`),
    completion: null,
    createdAt: "",
    updatedAt: "",
  }
}

function findDay(workouts: Workout[], date: string) {
  return buildHeatmap(workouts, TODAY)
    .weeks.flat()
    .find((day) => day.date === date)
}

describe("buildHeatmap", () => {
  it("spans a year of Monday-first weeks ending with the current one", () => {
    const { weeks } = buildHeatmap([], TODAY)

    expect(weeks).toHaveLength(HEATMAP_WEEKS)
    expect(weeks.every((week) => week.length === 7)).toBe(true)
    expect(weeks[0][0].date).toBe("2025-09-01")
    expect(weeks.at(-1)?.[0].date).toBe("2026-08-31")
    expect(weeks.at(-1)?.[0].isToday).toBe(true)
  })

  it("marks the rest of the current week as future, not as rest days", () => {
    const lastWeek = buildHeatmap([], TODAY).weeks.at(-1)

    expect(lastWeek?.map((day) => day.isFuture)).toEqual([
      false,
      true,
      true,
      true,
      true,
      true,
      true,
    ])
  })

  it("adds up every workout on a day and shades it by exercise count", () => {
    const day = findDay(
      [makeWorkout("2026-08-25", 4), makeWorkout("2026-08-25", 3)],
      "2026-08-25"
    )

    expect(day).toMatchObject({ workouts: 2, exercises: 7, level: 3 })
  })

  it("keeps a logged day visible even with no exercises in it", () => {
    expect(findDay([makeWorkout("2026-08-25", 0)], "2026-08-25")).toMatchObject(
      {
        workouts: 1,
        level: 1,
      }
    )
    expect(findDay([], "2026-08-25")).toMatchObject({ workouts: 0, level: 0 })
  })

  it("ignores workouts outside the window", () => {
    const heatmap = buildHeatmap(
      [makeWorkout("2025-08-31"), makeWorkout("2026-12-01")],
      TODAY
    )

    expect(heatmap.totalWorkouts).toBe(0)
    expect(heatmap.activeDays).toBe(0)
  })

  it("counts totals and active days across the window", () => {
    const heatmap = buildHeatmap(
      [
        makeWorkout("2026-08-24", 5),
        makeWorkout("2026-08-24", 2),
        makeWorkout("2026-08-19", 6),
      ],
      TODAY
    )

    expect(heatmap.totalWorkouts).toBe(3)
    expect(heatmap.activeDays).toBe(2)
  })

  it("counts a streak in consecutive trained weeks", () => {
    const heatmap = buildHeatmap(
      [
        makeWorkout("2026-08-31"),
        makeWorkout("2026-08-26"),
        makeWorkout("2026-08-18"),
        // A missed week ends the earlier run.
        makeWorkout("2026-08-04"),
        makeWorkout("2026-07-28"),
        makeWorkout("2026-07-21"),
        makeWorkout("2026-07-14"),
      ],
      TODAY
    )

    expect(heatmap.currentStreak).toBe(3)
    expect(heatmap.longestStreak).toBe(4)
  })

  it("waits out the current week before ending a streak", () => {
    const started = buildHeatmap([makeWorkout("2026-08-26")], TODAY)
    expect(started.currentStreak).toBe(1)

    // Nothing this week and nothing last week: the streak is over.
    const lapsed = buildHeatmap([makeWorkout("2026-08-19")], TODAY)
    expect(lapsed.currentStreak).toBe(0)
    expect(lapsed.longestStreak).toBe(1)
  })

  it("labels each month at the week it first appears", () => {
    const { months } = buildHeatmap([], TODAY)

    expect(months.map((month) => month.label)).toEqual([
      "Oct",
      "Nov",
      "Dec",
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
    ])
    expect(months.every((month) => month.weekIndex > 0)).toBe(true)
  })
})
