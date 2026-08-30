import { useState } from "react"
import { render, screen, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, describe, expect, it, vi } from "vitest"

import { WorkoutDetailPage } from "@/components/workout-detail-page"
import { useWorkouts } from "@/store/use-workouts"

function MissingWorkoutHarness() {
  const [showDetail, setShowDetail] = useState(true)

  if (!showDetail) return <p>Workouts</p>

  return (
    <WorkoutDetailPage
      onBack={() => setShowDetail(false)}
      onDeleted={() => {}}
      onDuplicated={() => {}}
      onEdit={() => {}}
      onOpenExercise={() => {}}
      workoutId="missing"
    />
  )
}

describe("WorkoutDetailPage", () => {
  beforeEach(() => {
    localStorage.clear()
    useWorkouts.setState({ workouts: [] })
  })

  it("navigates away from a missing workout after rendering", () => {
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {})

    render(<MissingWorkoutHarness />)

    expect(screen.getByText("Workouts")).toBeInTheDocument()
    expect(
      consoleError.mock.calls.some((call) =>
        String(call[0]).includes("Cannot update a component")
      )
    ).toBe(false)
    consoleError.mockRestore()
  })

  it("requires confirmation before deleting a workout", async () => {
    const user = userEvent.setup()
    const workoutId = useWorkouts.getState().createWorkout({
      name: "Workout",
      date: "2026-09-01",
      exerciseIds: ["0001"],
    })
    const onDeleted = vi.fn()

    render(
      <WorkoutDetailPage
        onBack={() => {}}
        onDeleted={onDeleted}
        onDuplicated={() => {}}
        onEdit={() => {}}
        onOpenExercise={() => {}}
        workoutId={workoutId}
      />
    )

    await user.click(screen.getByRole("button", { name: "Delete workout" }))
    expect(useWorkouts.getState().workouts).toHaveLength(1)

    const confirmation = await screen.findByRole("dialog")
    expect(
      within(confirmation).getByRole("heading", { name: "Delete workout?" })
    ).toBeInTheDocument()

    const confirmDelete = within(confirmation).getByRole("button", {
      name: "Delete workout",
    })
    expect(confirmDelete.querySelector("svg")).not.toBeInTheDocument()
    await user.click(confirmDelete)
    expect(useWorkouts.getState().workouts).toEqual([])
    expect(onDeleted).toHaveBeenCalledOnce()
  })
})
