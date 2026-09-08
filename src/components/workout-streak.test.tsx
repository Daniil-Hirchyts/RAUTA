import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, describe, expect, it, vi } from "vitest"

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
    expect(screen.getByText("best 2 days")).toBeInTheDocument()
  })

  it("gives the week a day each, and names what is on them", () => {
    render(<WorkoutStreak workouts={WORKOUTS} />)

    expect(
      screen.getByLabelText(`${formatDateShort(TODAY)}: 1 workout, 2 exercises`)
    ).toBeInTheDocument()
    expect(
      screen.getAllByRole("button", { name: /:/ }).map((day) => day.textContent)
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

  it("reports the tapped day, and opens the workout logged on it", async () => {
    const user = userEvent.setup()
    const onSelectWorkout = vi.fn()
    render(
      <WorkoutStreak onSelectWorkout={onSelectWorkout} workouts={WORKOUTS} />
    )

    await user.click(
      screen.getByLabelText(`${formatDateShort(TODAY)}: 1 workout, 2 exercises`)
    )
    await user.click(
      screen.getByRole("button", {
        name: `${formatDateShort(TODAY)}, 2 exercises`,
      })
    )

    expect(onSelectWorkout).toHaveBeenCalledWith(WORKOUTS[0])
  })

  it("names a tapped day with nothing on it as a rest day", async () => {
    const user = userEvent.setup()
    render(<WorkoutStreak workouts={[]} />)

    const monday = daysAgo(daysSinceMonday())
    await user.click(
      screen.getByLabelText(`${formatDateShort(monday)}: rest day`)
    )
    expect(screen.getByText("Rest day")).toBeInTheDocument()
  })

  it("returns to the streak when the selected day is tapped again", async () => {
    const user = userEvent.setup()
    render(<WorkoutStreak workouts={WORKOUTS} />)

    const today = screen.getByLabelText(
      `${formatDateShort(TODAY)}: 1 workout, 2 exercises`
    )
    await user.click(today)
    expect(screen.queryByText("day streak")).not.toBeInTheDocument()

    await user.click(today)
    expect(screen.getByText("day streak")).toBeInTheDocument()
  })

  it("asks for a first day when there is no run to show", () => {
    render(<WorkoutStreak workouts={[]} />)

    expect(screen.getByText("0")).toBeInTheDocument()
    expect(screen.getByText("Train today to start one")).toBeInTheDocument()
  })
})
