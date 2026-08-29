import { fireEvent, render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, describe, expect, it } from "vitest"

import { App } from "@/App"
import { EXERCISES, filterExercises } from "@/lib/exercises"
import { useFilters } from "@/store/use-filters"

describe("App", () => {
  beforeEach(() => {
    localStorage.clear()
    useFilters.setState({
      selectedMuscles: [],
      selectedEquipment: [],
      equipmentPresets: [],
    })
  })

  it("moves through separate muscle, equipment, and exercise stages", async () => {
    const user = userEvent.setup()
    render(<App />)

    expect(screen.getByRole("heading", { name: "Muscles" })).toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: /choose equipment/i })
    ).toBeDisabled()

    fireEvent.click(screen.getByRole("button", { name: "Front Chest" }))
    await user.click(screen.getByRole("button", { name: /choose equipment/i }))

    expect(
      screen.getByRole("heading", { name: "Equipment" })
    ).toBeInTheDocument()
    await user.click(screen.getByRole("checkbox", { name: "Body Weight" }))
    await user.click(screen.getByRole("button", { name: /show exercises/i }))

    expect(
      screen.getByRole("heading", { name: "Exercises" })
    ).toBeInTheDocument()
    expect(screen.getByTestId("exercise-results")).toBeInTheDocument()
  })

  it("renders the matching result count and visual cards", async () => {
    const user = userEvent.setup()
    const expected = filterExercises(EXERCISES, ["chest"], ["body weight"])
    useFilters.setState({
      selectedMuscles: ["chest"],
      selectedEquipment: ["body weight"],
    })
    render(<App />)

    await user.click(screen.getByRole("button", { name: /choose equipment/i }))
    await user.click(screen.getByRole("button", { name: /show exercises/i }))

    expect(screen.getByTestId("stage-count")).toHaveTextContent(
      `${expected.length} exercises`
    )
    const results = screen.getByTestId("exercise-results")
    expect(results.querySelectorAll("article")).toHaveLength(expected.length)
    expect(results.querySelector("img[src^='/assets/exercises/']")).toBeTruthy()
  })

  it("renders the zero-results state", async () => {
    const user = userEvent.setup()
    useFilters.setState({
      selectedMuscles: ["chest"],
      selectedEquipment: ["not-real-equipment"],
    })
    render(<App />)

    await user.click(screen.getByRole("button", { name: /choose equipment/i }))
    await user.click(screen.getByRole("button", { name: /show exercises/i }))

    expect(screen.getByText("0 exercises")).toBeInTheDocument()
  })
})
