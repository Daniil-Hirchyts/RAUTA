import { fireEvent, render, screen, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, describe, expect, it } from "vitest"

import { App } from "@/App"
import { formatDateLong, formatDateShort, toISODate } from "@/lib/date"
import { EXERCISES, filterExercises } from "@/lib/exercises"
import { useFavorites } from "@/store/use-favorites"
import { useFilters } from "@/store/use-filters"
import { useWorkouts } from "@/store/use-workouts"

async function goToExercises(
  user: ReturnType<typeof userEvent.setup>,
  muscles: string[],
  equipment: string[]
) {
  useFilters.setState({
    selectedMuscles: muscles as never,
    selectedEquipment: equipment,
  })
  await user.click(screen.getByRole("button", { name: /choose equipment/i }))
  await user.click(screen.getByRole("button", { name: /show exercises/i }))
}

describe("App", () => {
  beforeEach(() => {
    localStorage.clear()
    useFilters.setState({
      selectedMuscles: [],
      selectedEquipment: [],
      equipmentPresets: [],
    })
    useFavorites.setState({ favoriteIds: [] })
    useWorkouts.setState({ workouts: [] })
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
    const image = results.querySelector("img[src$='.webp']")
    expect(image).toHaveAttribute("loading", "lazy")
    expect(image).toHaveAttribute("decoding", "async")
    expect(image).toHaveAttribute("fetchpriority", "low")
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

  it("opens an exercise detail dialog on click", async () => {
    const user = userEvent.setup()
    const [first] = filterExercises(EXERCISES, ["chest"], ["body weight"])
    render(<App />)
    await goToExercises(user, ["chest"], ["body weight"])

    await user.click(
      screen.getByRole("button", { name: `View ${first.name} details` })
    )

    const dialog = await screen.findByRole("dialog")
    expect(
      within(dialog).getByRole("heading", { name: first.name })
    ).toBeInTheDocument()
  })

  it("toggles favorites and filters the list to favorites only", async () => {
    const user = userEvent.setup()
    const [first] = filterExercises(EXERCISES, ["chest"], ["body weight"])
    render(<App />)
    await goToExercises(user, ["chest"], ["body weight"])

    await user.click(
      screen.getByRole("button", { name: `Add ${first.name} to favorites` })
    )
    expect(useFavorites.getState().favoriteIds).toEqual([first.id])

    await user.click(
      screen.getByRole("button", { name: "Show favorites only" })
    )

    const results = screen.getByTestId("exercise-results")
    expect(results.querySelectorAll("article")).toHaveLength(1)
    expect(
      screen.getByRole("button", {
        name: `Remove ${first.name} from favorites`,
      })
    ).toBeInTheDocument()
  })

  it("composes a workout from selected exercises and shows it in My workouts", async () => {
    const user = userEvent.setup()
    const matches = filterExercises(EXERCISES, ["chest"], ["body weight"])
    const [first, second] = matches
    render(<App />)
    await goToExercises(user, ["chest"], ["body weight"])

    await user.click(screen.getByRole("button", { name: "Select" }))
    await user.click(
      screen.getByRole("button", { name: `Select ${first.name}` })
    )
    await user.click(
      screen.getByRole("button", { name: `Select ${second.name}` })
    )

    await user.click(
      screen.getByRole("button", { name: /add to workout \(2\)/i })
    )

    // The date picker trigger defaults to today — it doubles as the
    // workout's title, so there's no separate name field to fill in.
    const formDialog = await screen.findByRole("dialog")
    const today = toISODate(new Date())
    const trigger = within(formDialog).getByRole("button", {
      name: formatDateLong(today),
    })
    expect(trigger).toBeInTheDocument()

    await user.click(
      within(formDialog).getByRole("button", { name: "Create workout" })
    )

    expect(useWorkouts.getState().workouts).toHaveLength(1)
    expect(useWorkouts.getState().workouts[0]).toMatchObject({
      date: today,
      exerciseIds: [first.id, second.id],
    })

    // Select mode should exit and clear the selection after saving.
    expect(
      screen.queryByRole("button", { name: /add to workout/i })
    ).not.toBeInTheDocument()

    // "My workouts" is a full page, not a dialog — navigating there should
    // list the new workout by its date (there's no separate name field).
    await user.click(screen.getByRole("button", { name: "My workouts" }))
    expect(
      screen.getByRole("heading", { name: "My workouts" })
    ).toBeInTheDocument()
    const dateLabel = formatDateShort(today)
    expect(screen.getByText(dateLabel)).toBeInTheDocument()
    expect(screen.getByText("2 exercises")).toBeInTheDocument()

    // Clicking through shows the workout detail page with its exercises.
    await user.click(screen.getByText(dateLabel))
    expect(screen.getByText(first.name)).toBeInTheDocument()
    expect(screen.getByText(second.name)).toBeInTheDocument()
  })
})
