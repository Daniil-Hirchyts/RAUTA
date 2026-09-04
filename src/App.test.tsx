import {
  act,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, describe, expect, it, vi } from "vitest"
import { Capacitor } from "@capacitor/core"

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
  act(() => {
    useFilters.setState({
      selectedMuscles: muscles as never,
      selectedEquipment: equipment,
    })
  })
  const chooseEquipment = screen.getByRole("button", {
    name: /choose equipment/i,
  })
  await waitFor(() => expect(chooseEquipment).toBeEnabled())
  await user.click(chooseEquipment)
  await screen.findByRole("heading", { name: "Equipment" })
  await user.click(
    await screen.findByRole("button", { name: /show exercises/i })
  )
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
    writeAppSession({
      ...DEFAULT_APP_SESSION,
      pages: [{ type: "workouts" }, { type: "muscles" }],
    })
  })

  it("opens on My workouts and starts creation from there", async () => {
    localStorage.clear()
    const user = userEvent.setup()
    render(<App />)

    expect(
      screen.getByRole("heading", { name: "My workouts" })
    ).toBeInTheDocument()
    await user.click(screen.getByRole("button", { name: "New workout" }))
    expect(screen.getByRole("heading", { name: "Muscles" })).toBeInTheDocument()
  })

  it("always uses workouts as the native launch page", () => {
    const native = vi
      .spyOn(Capacitor, "isNativePlatform")
      .mockReturnValueOnce(true)
    render(<App />)

    expect(
      screen.getByRole("heading", { name: "My workouts" })
    ).toBeInTheDocument()
    native.mockRestore()
  })

  it("keeps the rounded content surface separate from bottom controls", () => {
    render(<App />)

    const screenShell = document.querySelector(".app-shell-frame")
    const surface = screenShell?.querySelector(".app-surface")
    const header = surface?.querySelector(
      '.app-page-layer[data-active="true"] .app-shell-header'
    )
    const footer = document.querySelector(
      'footer[data-slot="app-controls"][data-active="true"]'
    )

    expect(document.querySelectorAll(".app-surface")).toHaveLength(1)
    expect(screenShell).toHaveAttribute("data-commands", "visible")
    expect(surface).toContainElement(header as HTMLElement)
    expect(header).toContainElement(screen.getByRole("progressbar"))
    expect(surface).not.toContainElement(footer as HTMLElement)
    expect(surface?.querySelector(".app-page-stack")).toBeInTheDocument()
    expect(document.querySelector(".app-drawer-host")).not.toBeInTheDocument()
    expect(document.querySelector(".app-controls-host")).toBeInTheDocument()
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

  it("shows settings only on workouts page and home button without erase button in flow header", async () => {
    const user = userEvent.setup()
    render(<App />)

    // In flow view (initial setup in beforeEach is flow view)
    expect(screen.getByRole("heading", { name: "Muscles" })).toBeInTheDocument()
    expect(
      screen.queryByRole("button", { name: "Settings" })
    ).not.toBeInTheDocument()
    expect(
      screen.queryByRole("button", { name: /reset/i })
    ).not.toBeInTheDocument()

    const homeButton = screen.getByRole("button", { name: "My workouts" })
    expect(homeButton).toBeInTheDocument()
    await user.click(homeButton)

    // Now on workouts page: settings button is shown
    expect(
      screen.getByRole("heading", { name: "My workouts" })
    ).toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Settings" })).toBeInTheDocument()
  })

  it("moves through separate muscle, equipment, and exercise stages", async () => {
    const user = userEvent.setup()
    render(<App />)

    expect(screen.getByRole("heading", { name: "Muscles" })).toBeInTheDocument()
    const chooseEquipment = screen.getByRole("button", {
      name: /choose equipment/i,
    })
    // Refused, not inert: the control keeps its press so it can shake.
    expect(chooseEquipment).toHaveAttribute("aria-disabled", "true")
    expect(chooseEquipment.querySelector("svg")).not.toBeInTheDocument()

    fireEvent.click(screen.getByRole("button", { name: "Front Chest" }))
    await user.click(screen.getByRole("button", { name: /choose equipment/i }))

    expect(
      await screen.findByRole("heading", { name: "Equipment" })
    ).toBeInTheDocument()
    const equipmentSurface = document.querySelector(".app-surface")
    const equipmentFooter = document.querySelector(
      'footer[data-slot="app-controls"]'
    )
    const presetDock = document.querySelector(".equipment-presets-dock")

    expect(equipmentSurface).toContainElement(presetDock as HTMLElement)
    expect(equipmentFooter).not.toContainElement(presetDock as HTMLElement)
    const fullGymPreset = screen.getByRole("button", { name: "Full gym" })
    const presetScroller = fullGymPreset.closest("[data-swipe-ignore]")
    expect(fullGymPreset.closest(".app-surface")).toBe(equipmentSurface)
    expect(presetScroller).toHaveClass("px-(--app-content-inset)")
    expect(presetDock).not.toHaveAttribute("data-slot", "app-controls")
    const createPreset = screen.getByRole("button", {
      name: "Create equipment preset",
    })
    expect(
      createPreset.closest('footer[data-slot="app-controls"]')
    ).toContainElement(createPreset)
    expect(createPreset).toHaveAttribute("aria-disabled", "true")
    await user.click(screen.getByRole("checkbox", { name: "Body Weight" }))
    const enabledCreatePreset = screen.getByRole("button", {
      name: "Create equipment preset",
    })
    expect(enabledCreatePreset).toBeEnabled()
    await user.click(enabledCreatePreset)
    expect(
      screen.queryByRole("button", { name: "Full gym" })
    ).not.toBeInTheDocument()
    // Naming a preset takes over the command band; the chip row it replaces
    // steps out of the way while it does.
    const presetName = screen.getByLabelText("Preset name")
    expect(
      document.querySelector(
        'footer[data-slot="app-controls"][data-active="true"]'
      )
    ).toContainElement(presetName)
    expect(document.querySelector(".equipment-presets-dock")).toBeNull()
    await user.type(presetName, "Travel")
    await user.click(screen.getByRole("button", { name: "Save preset" }))
    expect(screen.getByRole("button", { name: "Travel" })).toBeInTheDocument()
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

  it("morphs optional controls without remounting the primary action", async () => {
    const user = userEvent.setup()
    render(<App />)

    const chooseEquipment = screen.getByRole("button", {
      name: "Choose equipment",
    })
    const clearMuscles = document.querySelector<HTMLButtonElement>(
      '[aria-label="Clear muscle selection"]'
    )!
    const slot = clearMuscles.closest(".morphing-action-slot")

    expect(slot).not.toHaveAttribute("data-visible")
    expect(slot).toHaveAttribute("inert")

    fireEvent.click(screen.getByRole("button", { name: "Front Chest" }))
    await waitFor(() => expect(slot).toHaveAttribute("data-visible", "true"))
    expect(screen.getByRole("button", { name: "Choose equipment" })).toBe(
      chooseEquipment
    )

    await user.click(
      screen.getByRole("button", { name: "Clear muscle selection" })
    )
    await waitFor(() => expect(slot).not.toHaveAttribute("data-visible"))
    expect(slot).toHaveAttribute("inert")
    expect(screen.getByRole("button", { name: "Choose equipment" })).toBe(
      chooseEquipment
    )
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
    expect((image as HTMLImageElement).style.filter).toContain(
      "exercise-background-key"
    )
    expect(image).not.toHaveClass("mix-blend-screen")
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
    await waitFor(() =>
      expect(results.querySelectorAll("article")).toHaveLength(
        EXERCISE_PAGE_SIZE * 2
      )
    )
  })

  it("renders the zero-results state", async () => {
    useFilters.setState({
      selectedMuscles: ["chest"],
      selectedEquipment: ["not-real-equipment"],
    })
    writeAppSession({
      ...DEFAULT_APP_SESSION,
      pages: [
        { type: "workouts" },
        { type: "muscles" },
        { type: "equipment" },
        { type: "exercises" },
      ],
    })
    render(<App />)

    expect(
      screen.getByText(/Nothing uses every muscle and every piece of equipment/)
    ).toBeInTheDocument()
  })

  it("opens an exercise detail page on click", async () => {
    const user = userEvent.setup()
    const [first] = filterExercises(EXERCISES, ["chest"], ["body weight"])
    render(<App />)
    await goToExercises(user, ["chest"], ["body weight"])

    await user.click(
      screen.getByRole("button", { name: `View ${first.name} details` })
    )

    expect(
      await screen.findByRole("heading", { name: first.name })
    ).toBeInTheDocument()
    expect(
      screen.queryByRole("button", { name: "Select" })
    ).not.toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Back" })).toBeInTheDocument()
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument()
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

  it("resets the favorites-only filter after leaving exercises", async () => {
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
    await user.click(
      screen.getByRole("button", { name: `View ${first.name} details` })
    )
    await user.click(screen.getByRole("button", { name: "Back" }))

    expect(
      screen.getByRole("button", { name: "Show favorites only" })
    ).toBeInTheDocument()
    expect(
      screen.getByTestId("exercise-results").querySelectorAll("article")
    ).toHaveLength(Math.min(matches.length, EXERCISE_PAGE_SIZE))
    expect(
      JSON.parse(localStorage.getItem("gym-lib-app-session") ?? "{}").state
    ).not.toHaveProperty("favoritesOnly")
  })

  it("shows a floating back-to-top action after scrolling exercises", async () => {
    const user = userEvent.setup()
    render(<App />)
    await goToExercises(user, ["chest"], ["body weight"])
    const scroller = screen.getByLabelText("Matching exercises")
    const scrollTo = vi.fn()
    Object.defineProperties(scroller, {
      clientHeight: { configurable: true, value: 300 },
      scrollTop: { configurable: true, value: 700, writable: true },
      scrollTo: { configurable: true, value: scrollTo },
    })

    fireEvent.scroll(scroller)
    const backToTop = await screen.findByRole("button", {
      name: "Back to top",
    })
    await user.click(backToTop)

    expect(scrollTo).toHaveBeenCalledWith({ behavior: "smooth", top: 0 })
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
    const addToWorkout = screen.getByRole("button", {
      name: /add to workout/i,
    })
    expect(addToWorkout).toHaveAttribute("aria-disabled", "true")
    // The selection CTA sits in the command band with the rest of the row,
    // not in a dock of its own above it.
    expect(
      document.querySelector(
        'footer[data-slot="app-controls"][data-active="true"]'
      )
    ).toContainElement(addToWorkout)
    expect(addToWorkout.closest(".app-surface")).toBeNull()
  })

  it("opens exercise search into the shell band, in place of its buttons", async () => {
    const user = userEvent.setup()
    render(<App />)
    await goToExercises(user, ["chest"], ["body weight"])

    const footer = document.querySelector(
      'footer[data-slot="app-controls"][data-active="true"]'
    )
    const searchButton = screen.getByRole("button", {
      name: "Search exercises",
    })
    expect(footer).toContainElement(searchButton)

    await user.click(searchButton)

    const searchInput = screen.getByRole("textbox", {
      name: "Search exercises",
    })
    expect(footer).toContainElement(searchInput)
    expect(searchInput.closest(".app-surface")).toBeNull()

    // The field is the row now: the buttons it replaced are gone, all but the
    // one that puts them back.
    expect(footer).toContainElement(
      screen.getByRole("button", { name: "Close search" })
    )
    expect(
      screen.queryByRole("button", { name: "Show favorites only" })
    ).not.toBeInTheDocument()
    expect(
      screen.queryByRole("button", { name: "Select" })
    ).not.toBeInTheDocument()

    await user.click(screen.getByRole("button", { name: "Close search" }))
    expect(footer).toContainElement(
      screen.getByRole("button", { name: "Select" })
    )
  })

  it("keeps the exercise detail page informative only", async () => {
    const user = userEvent.setup()
    const [exercise] = filterExercises(EXERCISES, ["chest"], ["body weight"])
    render(<App />)
    await goToExercises(user, ["chest"], ["body weight"])

    await user.click(
      screen.getByRole("button", {
        name: `View ${exercise.name} details`,
      })
    )

    const detailLike = screen.getByRole("button", {
      name: `Add ${exercise.name} to favorites`,
    })
    expect(detailLike).toHaveClass("border", "border-border", "bg-card")

    expect(
      screen.queryByRole("button", { name: "Select" })
    ).not.toBeInTheDocument()
    expect(
      screen.queryByRole("button", { name: "Selected" })
    ).not.toBeInTheDocument()

    await user.click(screen.getByRole("button", { name: "Back" }))

    expect(
      await screen.findByRole("button", {
        name: `View ${exercise.name} details`,
      })
    ).toBeInTheDocument()
  })

  it("opens the detail page on long tap in selection mode without toggling selection", async () => {
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

    expect(
      await screen.findByRole("heading", { name: exercise.name })
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

    expect(
      await screen.findByRole("heading", { name: "Add 1 exercise" })
    ).toBeInTheDocument()
    await user.click(screen.getByRole("button", { name: /tue, sep 8/i }))

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

    expect(
      await screen.findByRole("heading", {
        name: "Add 2 exercises",
      })
    ).toBeInTheDocument()
    await user.click(screen.getByRole("button", { name: /new workout/i }))

    // The date picker trigger defaults to today — it doubles as the
    // workout's title, so there's no separate name field to fill in.
    const formHeading = await screen.findByRole("heading", {
      name: "New workout",
    })
    const formPage = formHeading.closest<HTMLElement>("[data-page-entry]")!
    const today = toISODate(new Date())
    const trigger = within(formPage).getByRole("button", {
      name: formatDateLong(today),
    })
    expect(trigger).toBeInTheDocument()

    await user.click(screen.getByRole("button", { name: "Create workout" }))

    expect(useWorkouts.getState().workouts).toHaveLength(1)
    expect(useWorkouts.getState().workouts[0]).toMatchObject({
      date: today,
      exerciseIds: [first.id, second.id],
    })

    // Select mode should exit and clear the selection after saving.
    expect(
      screen.queryByRole("button", { name: /add to workout/i })
    ).not.toBeInTheDocument()

    // Saving opens the direct-manipulation detail view. Scoped to the page on
    // screen: the pages it replaced are still mounted for as long as they take
    // to dissolve, and they name the same exercises.
    const detailPage = document.querySelector<HTMLElement>(
      '.app-page-layer[data-active="true"]'
    )!
    expect(within(detailPage).getByText(first.name)).toBeInTheDocument()
    expect(within(detailPage).getByText(second.name)).toBeInTheDocument()
    expect(within(detailPage).getByText("01")).toBeInTheDocument()
    expect(within(detailPage).getByText("02")).toBeInTheDocument()
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
