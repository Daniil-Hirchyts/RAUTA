import { render, screen, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, describe, expect, it, vi } from "vitest"

import { WorkoutHeatmap } from "@/components/workout-heatmap"
import { formatDateShort, toISODate } from "@/lib/date"
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

let TODAY = ""
let LAST_WEEK = ""
let WORKOUTS: Workout[] = []

describe("WorkoutHeatmap", () => {
  beforeEach(() => {
    TODAY = daysAgo(0)
    LAST_WEEK = daysAgo(7)
    WORKOUTS = [makeWorkout(TODAY, 2), makeWorkout(LAST_WEEK, 5)]
  })

  it("summarises the year and the running streak", () => {
    render(<WorkoutHeatmap workouts={WORKOUTS} />)

    expect(screen.getByText("2 wk")).toBeInTheDocument()
    expect(screen.getByText("best 2 wk")).toBeInTheDocument()
    expect(screen.getByText("2 active days")).toBeInTheDocument()
  })

  it("gives every day up to today a cell, and none to tomorrow", () => {
    render(<WorkoutHeatmap workouts={WORKOUTS} />)
    const grid = screen.getByTestId("heatmap-grid")

    expect(
      within(grid).getByLabelText(
        `${formatDateShort(TODAY)}: 1 workout, 2 exercises`
      )
    ).toBeInTheDocument()
    expect(
      within(grid).getByLabelText(`${formatDateShort(daysAgo(3))}: rest day`)
    ).toBeInTheDocument()
    expect(
      within(grid).queryByLabelText(
        new RegExp(`^${formatDateShort(daysAgo(-1))}:`)
      )
    ).not.toBeInTheDocument()
  })

  it("reports the tapped day, and opens the workout logged on it", async () => {
    const user = userEvent.setup()
    const onSelectWorkout = vi.fn()
    render(
      <WorkoutHeatmap onSelectWorkout={onSelectWorkout} workouts={WORKOUTS} />
    )

    await user.click(
      screen.getByLabelText(
        `${formatDateShort(LAST_WEEK)}: 1 workout, 5 exercises`
      )
    )
    const caption = screen.getByRole("button", {
      name: `${formatDateShort(LAST_WEEK)} · 5 exercises`,
    })

    await user.click(caption)
    expect(onSelectWorkout).toHaveBeenCalledWith(WORKOUTS[1])
  })

  it("names a tapped day with nothing on it as a rest day", async () => {
    const user = userEvent.setup()
    render(<WorkoutHeatmap workouts={WORKOUTS} />)

    const restDay = daysAgo(3)
    await user.click(
      screen.getByLabelText(`${formatDateShort(restDay)}: rest day`)
    )
    expect(
      screen.getByText(`${formatDateShort(restDay)} · Rest day`)
    ).toBeInTheDocument()
  })

  it("clears the caption when the selected day is tapped again", async () => {
    const user = userEvent.setup()
    render(<WorkoutHeatmap workouts={WORKOUTS} />)

    const cell = screen.getByLabelText(
      `${formatDateShort(TODAY)}: 1 workout, 2 exercises`
    )
    await user.click(cell)
    expect(screen.getByText(/2 exercises/)).toBeInTheDocument()

    await user.click(cell)
    expect(screen.getByText("2 active days")).toBeInTheDocument()
  })
})
