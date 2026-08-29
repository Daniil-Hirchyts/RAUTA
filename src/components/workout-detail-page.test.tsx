import { useState } from "react"
import { render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import { WorkoutDetailPage } from "@/components/workout-detail-page"

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
})
