import { render, screen, waitFor, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, describe, expect, it } from "vitest"

import { App } from "@/App"
import { formatDateLong } from "@/lib/date"
import { DEFAULT_APP_SESSION, writeAppSession } from "@/store/app-session"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useFavorites } from "@/store/use-favorites"
import { useFilters } from "@/store/use-filters"
import { DEFAULT_SETTINGS, useSettings } from "@/store/use-settings"
import { useWorkouts } from "@/store/use-workouts"

function renderWorkoutDetail(exerciseIds = ["0001"]) {
  const workoutId = useWorkouts.getState().createWorkout({
    name: "Workout",
    date: "2026-09-02",
    exerciseIds,
  })
  writeAppSession({
    ...DEFAULT_APP_SESSION,
    pages: [{ type: "workouts" }, { type: "workout-detail", workoutId }],
  })
  render(<App />)
  return workoutId
}

describe("page-based app flows", () => {
  beforeEach(() => {
    localStorage.clear()
    useActiveWorkout.setState({ lastOutcome: null, session: null })
    useFavorites.setState({ favoriteIds: [] })
    useFilters.setState({
      equipmentPresets: [],
      selectedEquipment: [],
      selectedMuscles: [],
    })
    useSettings.setState(DEFAULT_SETTINGS)
    useWorkouts.setState({ workouts: [] })
  })

  it("keeps one surface while the command band expands and collapses", async () => {
    const user = userEvent.setup()
    writeAppSession(DEFAULT_APP_SESSION)
    render(<App />)

    const shell = document.querySelector(".app-shell-frame")!
    const surface = document.querySelector(".app-surface")!
    const grain = document.querySelector(".app-surface-grain")!
    expect(shell).toHaveAttribute("data-commands", "visible")
    expect(shell).toContainElement(grain as HTMLElement)
    expect(surface).not.toContainElement(grain as HTMLElement)
    expect(document.querySelectorAll(".app-surface-grain")).toHaveLength(1)

    await user.click(screen.getByRole("button", { name: "Settings" }))
    expect(shell).toHaveAttribute("data-commands", "hidden")
    expect(document.querySelectorAll(".app-surface")).toHaveLength(1)
    expect(document.querySelector(".app-surface")).toBe(surface)

    await user.click(screen.getByRole("button", { name: /^Back$/ }))
    expect(shell).toHaveAttribute("data-commands", "visible")
    expect(document.querySelector(".app-surface")).toBe(surface)
  })

  it("uses a two-step confirmation popover to clear all data", async () => {
    const user = userEvent.setup()
    useWorkouts.getState().createWorkout({
      name: "Saved workout",
      date: "2026-09-02",
      exerciseIds: ["0001"],
    })
    writeAppSession({
      ...DEFAULT_APP_SESSION,
      pages: [{ type: "workouts" }, { type: "settings" }],
    })
    render(<App />)

    await user.click(screen.getByRole("button", { name: /Clear all data/ }))
    const confirm = await screen.findByRole("dialog", {
      name: "Clear all data?",
    })
    // Settings is still the page underneath — nothing was pushed over it.
    expect(screen.getByRole("heading", { name: "Settings" })).toBeVisible()

    await user.click(within(confirm).getByRole("button", { name: "Continue" }))
    expect(
      within(confirm).getByRole("heading", { name: "This cannot be undone" })
    ).toBeVisible()
    expect(useWorkouts.getState().workouts).toHaveLength(1)

    await user.click(
      within(confirm).getByRole("button", { name: "Delete everything" })
    )
    expect(useWorkouts.getState().workouts).toEqual([])
    expect(screen.getByRole("heading", { name: "My workouts" })).toBeVisible()
  })

  it("deletes a workout from a confirmation popover", async () => {
    const user = userEvent.setup()
    renderWorkoutDetail()

    await user.click(screen.getByRole("button", { name: "Delete workout" }))
    const confirm = await screen.findByRole("dialog", {
      name: "Delete workout?",
    })
    expect(useWorkouts.getState().workouts).toHaveLength(1)

    await user.click(
      within(confirm).getByRole("button", { name: "Delete workout" })
    )
    expect(useWorkouts.getState().workouts).toEqual([])
    expect(screen.getByRole("heading", { name: "My workouts" })).toBeVisible()
  })

  it("changes a workout date in a popover over the same page", async () => {
    const user = userEvent.setup()
    const workoutId = renderWorkoutDetail()

    await user.click(
      screen.getByRole("button", { name: /^Change date, currently/ })
    )
    const calendar = await screen.findByRole("dialog", {
      name: "Choose workout date",
    })
    // The workout is still the page underneath, commands and all.
    expect(screen.getByRole("button", { name: "Add exercise" })).toBeVisible()
    expect(document.querySelector(".app-shell-frame")).toHaveAttribute(
      "data-commands",
      "visible"
    )

    await user.click(
      within(calendar).getByRole("button", { name: /September 4/ })
    )
    await waitFor(() =>
      expect(
        useWorkouts.getState().workouts.find((item) => item.id === workoutId)
          ?.date
      ).toBe("2026-09-04")
    )
    expect(screen.getByText(formatDateLong("2026-09-04"))).toBeVisible()
    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: /^Change date, currently/ })
      ).toHaveAttribute("aria-expanded", "false")
    )
  })

  it("swaps an exercise on the alternatives page", async () => {
    const user = userEvent.setup()
    const workoutId = renderWorkoutDetail(["0001"])

    await user.click(screen.getByRole("button", { name: "Find alternative" }))
    expect(
      screen.getByRole("heading", { name: "Find alternative" })
    ).toBeVisible()
    const replacement = screen.getAllByRole("button", { name: /Swap to/ })[0]
    await user.click(replacement)

    expect(
      useWorkouts.getState().workouts.find((item) => item.id === workoutId)
        ?.exerciseIds
    ).not.toEqual(["0001"])
  })

  it("temporarily collapses commands for the countdown overlay", async () => {
    const user = userEvent.setup()
    renderWorkoutDetail()
    const shell = document.querySelector(".app-shell-frame")!

    await user.click(screen.getByRole("button", { name: "Start workout" }))
    expect(
      screen.getByRole("dialog", { name: "Starting workout" })
    ).toBeVisible()
    expect(shell).toHaveAttribute("data-commands", "hidden")

    await user.click(screen.getByRole("button", { name: "Cancel" }))
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument()
    expect(shell).toHaveAttribute("data-commands", "visible")
  })
})
