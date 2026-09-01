import { act, fireEvent, render, screen, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, describe, expect, it } from "vitest"

import { App } from "@/App"
import { formatDateLong, formatDateShort, toISODate } from "@/lib/date"
import {
  EQUIPMENT_OPTIONS,
  EXERCISE_PAGE_SIZE,
  EXERCISES,
  filterExercises,
} from "@/lib/exercises"
import { useFavorites } from "@/store/use-favorites"
import { useFilters } from "@/store/use-filters"
import { DEFAULT_SETTINGS, useSettings } from "@/store/use-settings"
import { useWorkouts } from "@/store/use-workouts"
import { DEFAULT_APP_SESSION, writeAppSession } from "@/store/app-session"
import { triggerIntersection } from "@/test/setup"
import { MUSCLE_IDS } from "@/types"

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
    useSettings.setState(DEFAULT_SETTINGS)
    writeAppSession({ ...DEFAULT_APP_SESSION, view: { type: "flow" } })
  })

  it("opens on My workouts and starts creation from there", async () => {
    localStorage.clear()
    const user = userEvent.setup()
    render(<App />)

    expect(
      screen.getByRole("heading", { name: "My workouts" })
    ).toBeInTheDocument()
    await user.click(screen.getByRole("button", { name: "Add workout" }))
    expect(screen.getByRole("heading", { name: "Muscles" })).toBeInTheDocument()
  })

  it("keeps the rounded content surface separate from bottom controls", () => {
    render(<App />)

    const screenShell = document.querySelector(".app-screen")
    const surface = screenShell?.querySelector(".app-surface")
    const header = screenShell?.querySelector(".app-shell-header")
    const footer = screenShell?.querySelector("footer.bottom-controls-scrim")

    expect(screenShell).toHaveAttribute("data-bottom-controls", "true")
    expect(surface).toContainElement(header as HTMLElement)
    expect(surface).not.toContainElement(footer as HTMLElement)
    expect(surface?.querySelector(".app-stage-frame")).toBeInTheDocument()
  })

  it("opens settings from the workouts header and persists preferences", async () => {
    localStorage.clear()
    const user = userEvent.setup()
    render(<App />)

    await user.click(screen.getByRole("button", { name: "Settings" }))
    expect(
      screen.getByRole("heading", { name: "Settings" })
    ).toBeInTheDocument()

    await user.click(screen.getByRole("switch", { name: "Sound chimes" }))
    expect(useSettings.getState()).toMatchObject({
      soundChimesEnabled: true,
    })

    await user.click(screen.getByRole("button", { name: "Back" }))
    expect(
      screen.getByRole("heading", { name: "My workouts" })
    ).toBeInTheDocument()
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

  it("restores the in-progress flow after the app remounts", async () => {
    const user = userEvent.setup()
    const [exercise] = filterExercises(EXERCISES, ["chest"], ["body weight"])
    const firstRender = render(<App />)

    fireEvent.click(screen.getByRole("button", { name: "Front Chest" }))
    await user.click(screen.getByRole("button", { name: /choose equipment/i }))
    await user.click(screen.getByRole("checkbox", { name: "Body Weight" }))
    await user.click(screen.getByRole("button", { name: /show exercises/i }))
    await user.click(screen.getByRole("button", { name: "Select" }))
    await user.click(
      screen.getByRole("button", { name: `Select ${exercise.name}` })
    )

    firstRender.unmount()
    render(<App />)

    expect(
      screen.getByRole("heading", { name: "Exercises" })
    ).toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: "Add to workout (1)" })
    ).toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: `Select ${exercise.name}` })
    ).toHaveAttribute("aria-pressed", "true")
  })

  it("renders the matching visual cards", async () => {
    const user = userEvent.setup()
    const expected = filterExercises(EXERCISES, ["chest"], ["body weight"])
    useFilters.setState({
      selectedMuscles: ["chest"],
      selectedEquipment: ["body weight"],
    })
    render(<App />)

    await user.click(screen.getByRole("button", { name: /choose equipment/i }))
    await user.click(screen.getByRole("button", { name: /show exercises/i }))

    const results = screen.getByTestId("exercise-results")
    expect(results.querySelectorAll("article")).toHaveLength(
      Math.min(expected.length, EXERCISE_PAGE_SIZE)
    )
    const image = results.querySelector("img[src$='.webp']")
    expect(image).toHaveAttribute("loading", "lazy")
    expect(image).toHaveAttribute("decoding", "async")
    expect(image).toHaveAttribute("fetchpriority", "low")
  })

  it("paginates a large result set instead of mounting every card at once", async () => {
    const user = userEvent.setup()
    const expected = filterExercises(
      EXERCISES,
      [...MUSCLE_IDS],
      [...EQUIPMENT_OPTIONS]
    )
    expect(expected.length).toBeGreaterThan(EXERCISE_PAGE_SIZE * 2)
    useFilters.setState({
      selectedMuscles: [...MUSCLE_IDS],
      selectedEquipment: [...EQUIPMENT_OPTIONS],
    })
    render(<App />)

    await user.click(screen.getByRole("button", { name: /choose equipment/i }))
    await user.click(screen.getByRole("button", { name: /show exercises/i }))

    const results = screen.getByTestId("exercise-results")
    expect(results.querySelectorAll("article")).toHaveLength(EXERCISE_PAGE_SIZE)

    // The next batch loads automatically once the sentinel below the grid
    // scrolls into view — simulate that (jsdom does no real layout, so
    // there's no geometry to trigger it for real).
    act(() => {
      triggerIntersection(screen.getByTestId("load-more-sentinel"))
    })
    expect(results.querySelectorAll("article")).toHaveLength(
      EXERCISE_PAGE_SIZE * 2
    )
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

    expect(
      screen.getByTestId("exercise-results").querySelectorAll("article")
    ).toHaveLength(Math.min(matches.length, EXERCISE_PAGE_SIZE))
    expect(
      screen.getByRole("button", { name: /add to workout/i })
    ).toBeDisabled()
  })

  it("selects an exercise from its detail drawer without opening workout creation", async () => {
    const user = userEvent.setup()
    const [exercise] = filterExercises(EXERCISES, ["chest"], ["body weight"])
    render(<App />)
    await goToExercises(user, ["chest"], ["body weight"])

    await user.click(
      screen.getByRole("button", {
        name: `View ${exercise.name} details`,
      })
    )

    const detailDrawer = await screen.findByRole("dialog")
    await user.click(
      within(detailDrawer).getByRole("button", { name: "Select" })
    )

    expect(screen.queryByRole("dialog")).not.toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: "Add to workout (1)" })
    ).toBeInTheDocument()
    expect(
      screen.queryByRole("button", { name: "Create workout" })
    ).not.toBeInTheDocument()
  })

  it("opens the detail drawer on long tap in selection mode without toggling selection", async () => {
    const user = userEvent.setup()
    const [exercise] = filterExercises(EXERCISES, ["chest"], ["body weight"])
    render(<App />)
    await goToExercises(user, ["chest"], ["body weight"])

    await user.click(screen.getByRole("button", { name: "Select" }))
    const cardButton = screen.getByRole("button", {
      name: `Select ${exercise.name}`,
    })
    expect(cardButton).toHaveAttribute("aria-pressed", "false")

    fireEvent.pointerDown(cardButton, { button: 0, clientX: 100, clientY: 100 })
    act(() => {
      new Promise((resolve) => setTimeout(resolve, 550))
    })
    // Wait for the timer
    await new Promise((resolve) => setTimeout(resolve, 550))
    fireEvent.pointerUp(cardButton)
    fireEvent.click(cardButton)

    const detailDrawer = await screen.findByRole("dialog")
    expect(
      within(detailDrawer).getByRole("heading", { name: exercise.name })
    ).toBeInTheDocument()
    expect(cardButton).toHaveAttribute("aria-pressed", "false")
  })

  it("adds selected exercises to an existing workout", async () => {
    const user = userEvent.setup()
    const [exercise] = filterExercises(EXERCISES, ["chest"], ["body weight"])
    const workoutId = useWorkouts.getState().createWorkout({
      name: "Workout",
      date: "2026-09-08",
      exerciseIds: [],
    })
    render(<App />)
    await goToExercises(user, ["chest"], ["body weight"])

    await user.click(screen.getByRole("button", { name: "Select" }))
    await user.click(
      screen.getByRole("button", { name: `Select ${exercise.name}` })
    )
    await user.click(screen.getByRole("button", { name: "Add to workout (1)" }))

    const destination = await screen.findByRole("dialog")
    await user.click(
      within(destination).getByRole("button", { name: /tue, sep 8/i })
    )

    expect(
      useWorkouts
        .getState()
        .workouts.find((workout) => workout.id === workoutId)?.exerciseIds
    ).toEqual([exercise.id])
    expect(
      screen.getByRole("button", { name: "Add exercise" })
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

    const addToWorkout = screen.getByRole("button", {
      name: /add to workout \(2\)/i,
    })
    expect(addToWorkout.querySelector("svg")).not.toBeInTheDocument()
    await user.click(addToWorkout)

    const destinationDrawer = await screen.findByRole("dialog")
    expect(
      within(destinationDrawer).getByRole("heading", {
        name: "Add 2 exercises",
      })
    ).toBeInTheDocument()
    await user.click(
      within(destinationDrawer).getByRole("button", { name: /new workout/i })
    )

    // The date picker trigger defaults to today — it doubles as the
    // workout's title, so there's no separate name field to fill in.
    const formHeading = await screen.findByRole("heading", {
      name: "New workout",
    })
    const formDrawer = formHeading.closest<HTMLElement>("[role='dialog']")!
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

    // Saving opens the direct-manipulation detail view.
    expect(screen.getByText(first.name)).toBeInTheDocument()
    expect(screen.getByText(second.name)).toBeInTheDocument()
    expect(screen.getByText("01")).toBeInTheDocument()
    expect(screen.getByText("02")).toBeInTheDocument()
    expect(
      screen.queryByRole("button", { name: "Edit workout" })
    ).not.toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: "Add exercise" })
    ).toBeInTheDocument()

    await user.click(screen.getByRole("button", { name: "Back to workouts" }))
    expect(
      screen.getByRole("heading", { name: "My workouts" })
    ).toBeInTheDocument()
    const dateLabel = formatDateShort(today)
    expect(screen.getByText(dateLabel)).toBeInTheDocument()
    expect(screen.getByText("2 exercises")).toBeInTheDocument()
  })
})
