import { render, screen } from "@testing-library/react"
import { beforeEach, describe, expect, it } from "vitest"

import { App } from "@/App"
import { EXERCISES, filterExercises } from "@/lib/exercises"
import { useFilters } from "@/store/use-filters"

describe("App", () => {
  beforeEach(() => {
    localStorage.clear()
    useFilters.setState({ selectedMuscles: [], selectedEquipment: [] })
  })

  it("keeps results hidden until both filter groups are selected", () => {
    const { rerender } = render(<App />)
    expect(screen.queryByTestId("exercise-results")).not.toBeInTheDocument()

    useFilters.setState({ selectedMuscles: ["chest"] })
    rerender(<App />)
    expect(screen.queryByTestId("exercise-results")).not.toBeInTheDocument()
  })

  it("renders the matching result count and cards", () => {
    const expected = filterExercises(EXERCISES, ["chest"], ["body weight"])
    useFilters.setState({
      selectedMuscles: ["chest"],
      selectedEquipment: ["body weight"],
    })
    render(<App />)

    expect(screen.getByTestId("result-count")).toHaveTextContent(
      String(expected.length)
    )
    expect(screen.getByTestId("exercise-results").children).toHaveLength(
      expected.length
    )
  })

  it("renders the zero-results state", () => {
    useFilters.setState({
      selectedMuscles: ["chest"],
      selectedEquipment: ["not-real-equipment"],
    })
    render(<App />)
    expect(screen.getByText("0 exercises")).toBeInTheDocument()
  })
})
