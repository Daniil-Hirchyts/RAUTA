import { render, screen } from "@testing-library/react"
import { beforeEach, describe, expect, it } from "vitest"

import { WorkoutStreak } from "@/components/workout-streak"
import { formatDateShort, formatWeekdayShort, toISODate } from "@/lib/date"
import type { Workout } from "@/store/use-workouts"

function daysAgo(days: number) {
  const date = new Date()
  date.setDate(date.getDate() - days)
  return toISODate(date)
}

function makeWorkout(date: string, exercises: number): Workout {
  return {
    id: `workout-${date}`,
    name: "Session",
    date,
    exerciseIds: Array.from({ length: exercises }, (_, index) => `${index}`),
    completion: null,
    createdAt: "",
    updatedAt: "",
  }
}

/** Monday-first, counted from today: how far back this week reaches. */
function daysSinceMonday() {
  return (new Date().getDay() + 6) % 7
}

let TODAY = ""
let WORKOUTS: Workout[] = []

describe("WorkoutStreak", () => {
  beforeEach(() => {
    TODAY = daysAgo(0)
    WORKOUTS = [makeWorkout(TODAY, 2), makeWorkout(daysAgo(1), 5)]
  })

  it("counts the run of days ending today", () => {
    render(<WorkoutStreak workouts={WORKOUTS} />)

    expect(screen.getByText("2")).toBeInTheDocument()
    expect(screen.getByText("day streak")).toBeInTheDocument()
  })

  it("gives the week a day each, and names what is on them", () => {
    render(<WorkoutStreak workouts={WORKOUTS} />)

    expect(
      screen.getByLabelText(`${formatDateShort(TODAY)}: 1 workout, 2 exercises`)
    ).toBeInTheDocument()
    expect(
      screen.getAllByRole("listitem").map((day) => day.textContent)
    ).toEqual(
      Array.from({ length: 7 }, (_, index) =>
        formatWeekdayShort(daysAgo(daysSinceMonday() - index))
      )
    )
  })

  it("holds a day still ahead apart from a day nothing was logged on", () => {
    render(<WorkoutStreak workouts={[]} />)

    const monday = daysAgo(daysSinceMonday())
    const sunday = daysAgo(daysSinceMonday() - 6)
    expect(
      screen.getByLabelText(`${formatDateShort(monday)}: rest day`)
    ).toBeInTheDocument()
    if (sunday !== TODAY) {
      expect(
        screen.getByLabelText(`${formatDateShort(sunday)}: still ahead`)
      ).toBeInTheDocument()
    }
  })

  it("contains no clickable buttons", () => {
    render(<WorkoutStreak workouts={WORKOUTS} />)

    expect(screen.queryAllByRole("button")).toHaveLength(0)
  })

  it("shows 0 day streak when there is no run to show", () => {
    render(<WorkoutStreak workouts={[]} />)

    expect(screen.getByText("0")).toBeInTheDocument()
    expect(screen.getByText("day streak")).toBeInTheDocument()
  })
})
