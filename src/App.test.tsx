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
    const chooseEquipment = screen.getByRole("button", {
      name: /choose equipment/i,
    })
    expect(chooseEquipment).toBeDisabled()
    expect(chooseEquipment.querySelector("svg")).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole("button", { name: "Front Chest" }))
    await user.click(screen.getByRole("button", { name: /choose equipment/i }))

    expect(
      await screen.findByRole("heading", { name: "Equipment" })
    ).toBeInTheDocument()
    await user.click(screen.getByRole("checkbox", { name: "Body Weight" }))
    const showExercises = screen.getByRole("button", {
      name: /show exercises/i,
    })
    expect(showExercises.querySelector("svg")).not.toBeInTheDocument()
    await user.click(showExercises)

    expect(
      await screen.findByRole("heading", { name: "Exercises" })
    ).toBeInTheDocument()
    expect(screen.getByTestId("exercise-results")).toBeInTheDocument()
  })

  it("moves forward and back between stages with horizontal swipes", async () => {
    useFilters.setState({
      selectedMuscles: ["chest"],
      selectedEquipment: ["body weight"],
    })
    render(<App />)
    const main = document.querySelector("main") as HTMLElement

    fireEvent.pointerDown(main, {
      clientX: 330,
      clientY: 400,
      pointerType: "touch",
    })
    fireEvent.pointerUp(main, {
      clientX: 120,
      clientY: 405,
      pointerType: "touch",
    })
    expect(
      await screen.findByRole("heading", { name: "Equipment" })
    ).toBeVisible()

    fireEvent.pointerDown(main, {
      clientX: 80,
      clientY: 400,
      pointerType: "touch",
    })
    fireEvent.pointerUp(main, {
      clientX: 300,
      clientY: 405,
      pointerType: "touch",
    })
    expect(
      await screen.findByRole("heading", { name: "Muscles" })
    ).toBeVisible()
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

  it("opens an exercise detail drawer on click", async () => {
    const user = userEvent.setup()
    const [first] = filterExercises(EXERCISES, ["chest"], ["body weight"])
    render(<App />)
    await goToExercises(user, ["chest"], ["body weight"])

    await user.click(
      screen.getByRole("button", { name: `View ${first.name} details` })
    )

    const drawer = await screen.findByRole("dialog")
    expect(
      within(drawer).getByRole("heading", { name: first.name })
    ).toBeInTheDocument()
    expect(
      within(drawer).getByRole("button", { name: "Select" })
    ).toBeInTheDocument()
    expect(
      within(drawer).getByRole("button", { name: "Close drawer" })
    ).toBeInTheDocument()
    expect(
      document.querySelector("[data-slot='drawer-swipe-handle']")
    ).not.toBeInTheDocument()
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

  it("keeps the favorites filter available while selecting exercises", async () => {
    const user = userEvent.setup()
    const matches = filterExercises(EXERCISES, ["chest"], ["body weight"])
    const [first] = matches
    render(<App />)
    await goToExercises(user, ["chest"], ["body weight"])

    await user.click(
      screen.getByRole("button", { name: `Add ${first.name} to favorites` })
    )
    await user.click(
      screen.getByRole("button", { name: "Show favorites only" })
    )
    await user.click(screen.getByRole("button", { name: "Select" }))

    const clearFilter = screen.getByRole("button", {
      name: "Show all exercises",
    })
    expect(clearFilter).toBeInTheDocument()
    await user.click(clearFilter)

    expect(screen.getByTestId("exercise-results").querySelectorAll("article"))
      .toHaveLength(matches.length)
    expect(
      screen.getByRole("button", { name: /add to workout/i })
    ).toBeDisabled()
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

    const addToWorkout = screen.getByRole("button", {
      name: /add to workout \(2\)/i,
    })
    expect(addToWorkout.querySelector("svg")).not.toBeInTheDocument()
    await user.click(addToWorkout)

    // The date picker trigger defaults to today — it doubles as the
    // workout's title, so there's no separate name field to fill in.
    const formDrawer = await screen.findByRole("dialog")
    const today = toISODate(new Date())
    const trigger = within(formDrawer).getByRole("button", {
      name: formatDateLong(today),
    })
    expect(trigger).toBeInTheDocument()

    await user.click(
      within(formDrawer).getByRole("button", { name: "Create workout" })
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

    // "My workouts" is a full page, not a drawer — navigating there should
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

    await user.click(screen.getByRole("button", { name: "Edit workout" }))
    const editDrawer = await screen.findByRole("dialog")
    expect(
      within(editDrawer).getByRole("button", { name: "Save changes" })
    ).toBeInTheDocument()
    expect(
      within(editDrawer).getByRole("img", {
        name: `${first.name} demonstration`,
      })
    ).toBeInTheDocument()
  })
})
