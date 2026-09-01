import { render, screen } from "@testing-library/react"
import { beforeEach, describe, expect, it } from "vitest"

import { WorkoutsPage } from "@/components/workouts-page"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useWorkouts } from "@/store/use-workouts"

function renderPage() {
  render(
    <WorkoutsPage
      onCreate={() => {}}
      onSelect={() => {}}
      onSettings={() => {}}
    />
  )
}

describe("WorkoutsPage", () => {
  beforeEach(() => {
    localStorage.clear()
    useWorkouts.setState({ workouts: [] })
    useActiveWorkout.setState({ session: null, lastOutcome: null })
  })

  it("marks the workout being performed and leaves the others alone", () => {
    const running = useWorkouts.getState().createWorkout({
      name: "Push day",
      date: "2026-09-01",
      exerciseIds: ["0001", "0002"],
    })
    useWorkouts.getState().createWorkout({
      name: "Pull day",
      date: "2026-09-02",
      exerciseIds: ["0003"],
    })

    const workout = useWorkouts
      .getState()
      .workouts.find((item) => item.id === running)!
    useActiveWorkout.getState().start(workout)
    useActiveWorkout.getState().completeCurrent()

    renderPage()

    expect(screen.getByText(/In progress/)).toHaveTextContent("00:00")
    expect(screen.getByText(/In progress/)).toHaveTextContent("1/2")
    // The workout that is not running keeps its ordinary exercise count.
    expect(screen.getByText("1 exercise")).toBeInTheDocument()
  })

  it("says so when the session is paused", () => {
    const id = useWorkouts.getState().createWorkout({
      name: "Push day",
      date: "2026-09-01",
      exerciseIds: ["0001"],
    })
    const workout = useWorkouts.getState().workouts.find((w) => w.id === id)!
    useActiveWorkout.getState().start(workout)
    useActiveWorkout.getState().pause()

    renderPage()

    expect(screen.getByText(/Paused/)).toBeInTheDocument()
  })

  it("shows plain exercise counts when nothing is running", () => {
    useWorkouts.getState().createWorkout({
      name: "Push day",
      date: "2026-09-01",
      exerciseIds: ["0001", "0002"],
    })

    renderPage()

    expect(screen.getByText("2 exercises")).toBeInTheDocument()
    expect(screen.queryByText(/In progress/)).not.toBeInTheDocument()
  })

  it("separates past workouts and shows their completion stats", () => {
    const pastId = useWorkouts.getState().createWorkout({
      name: "Past session",
      date: "2026-08-31",
      exerciseIds: ["0001", "0002"],
    })
    useWorkouts.getState().completeWorkout(pastId, {
      activeCalories: 118,
      completedAt: "2026-08-31T10:15:00.000Z",
      completedExerciseIds: ["0001", "0002"],
      durationMs: 15 * 60_000,
      healthSyncStatus: "synced",
      startedAt: "2026-08-31T10:00:00.000Z",
    })
    useWorkouts.getState().createWorkout({
      name: "Next session",
      date: "2026-09-02",
      exerciseIds: ["0003"],
    })

    renderPage()

    expect(screen.getByRole("heading", { name: "Next workouts" })).toBeVisible()
    expect(screen.getByRole("heading", { name: "Past workouts" })).toBeVisible()
    expect(screen.getByText("15:00")).toBeVisible()
    expect(screen.getByText("118 kcal")).toBeVisible()
    expect(
      screen.getAllByRole("button", { name: /Copy .* workout to today/ })
    ).not.toHaveLength(0)
  })
})
