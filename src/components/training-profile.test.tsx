import { render, screen, waitFor, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, describe, expect, it } from "vitest"

import { App } from "@/App"
import { EQUIPMENT_OPTIONS } from "@/lib/exercises"
import { DEFAULT_APP_SESSION, writeAppSession } from "@/store/app-session"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useFavorites } from "@/store/use-favorites"
import { useFilters } from "@/store/use-filters"
import { DEFAULT_SETTINGS, useSettings } from "@/store/use-settings"
import { useTrainingProfile } from "@/store/use-training-profile"
import { useWorkouts } from "@/store/use-workouts"
import { completedOnboardingState } from "@/test/profile"

const profile = () => useTrainingProfile.getState().profile

function freshInstall() {
  localStorage.clear()
  useActiveWorkout.setState({ lastOutcome: null, session: null })
  useFavorites.setState({ favoriteIds: [] })
  useFilters.setState({
    equipmentPresets: [],
    gymEquipment: [],
    selectedEquipment: [],
    selectedMuscles: [],
  })
  useSettings.setState(DEFAULT_SETTINGS)
  useWorkouts.setState({ workouts: [] })
  useTrainingProfile.getState().resetTrainingProfile()
}

function openSettings() {
  writeAppSession({
    ...DEFAULT_APP_SESSION,
    pages: [{ type: "workouts" }, { type: "settings" }],
  })
  render(<App />)
}

describe("first-run profile setup", () => {
  beforeEach(freshInstall)

  it("asks one question per screen and lands on My workouts", async () => {
    const user = userEvent.setup()
    render(<App />)

    expect(
      screen.getByRole("heading", { name: "Your name" })
    ).toBeInTheDocument()
    expect(screen.getByRole("progressbar")).toHaveAttribute(
      "aria-label",
      "Step 1 of 7"
    )

    await user.type(screen.getByRole("textbox", { name: "Your name" }), "Alex")
    await user.click(screen.getByRole("button", { name: "Continue to Age" }))

    await user.click(screen.getByRole("slider", { name: "Age" }))
    await user.keyboard("{ArrowUp}{ArrowUp}")
    await user.click(
      screen.getByRole("button", { name: "Continue to Experience" })
    )

    await user.click(screen.getByRole("radio", { name: /Intermediate/ }))
    await user.click(screen.getByRole("button", { name: "Continue to Goal" }))

    await user.click(screen.getByRole("radio", { name: /Build muscle/ }))
    await user.click(
      screen.getByRole("button", { name: "Continue to Session length" })
    )

    await user.click(
      screen.getByRole("slider", { name: "Preferred session duration" })
    )
    await user.keyboard("{ArrowDown}{ArrowDown}{ArrowDown}")
    await user.click(
      screen.getByRole("button", { name: "Continue to Your gym" })
    )

    expect(
      screen.getByRole("heading", { name: "Your gym" })
    ).toBeInTheDocument()
    await user.click(screen.getByRole("button", { name: "Home kit" }))
    await user.click(screen.getByRole("button", { name: "Continue to Health" }))

    await user.click(screen.getByRole("checkbox", { name: /Injury/ }))
    await user.click(screen.getByRole("button", { name: "Finish setup" }))

    expect(
      screen.getByRole("heading", { name: "My workouts" })
    ).toBeInTheDocument()
    expect(profile()).toMatchObject({
      name: "Alex",
      age: 32,
      trainingExperience: "intermediate",
      goal: "hypertrophy",
      preferredSessionDurationMinutes: 45,
      health: { status: "unsupported", reasons: ["active_injury"] },
    })
    expect(useFilters.getState().gymEquipment).toContain("dumbbell")
    expect(useTrainingProfile.getState().onboarding.completed).toBe(true)
  })

  it("can step back to an earlier answer without losing the later ones", async () => {
    const user = userEvent.setup()
    render(<App />)

    await user.type(screen.getByRole("textbox", { name: "Your name" }), "Alex")
    await user.click(screen.getByRole("button", { name: "Continue to Age" }))
    await user.click(screen.getByRole("button", { name: "Previous step" }))

    expect(
      screen.getByRole("heading", { name: "Your name" })
    ).toBeInTheDocument()
    expect(screen.getByRole("textbox", { name: "Your name" })).toHaveValue(
      "Alex"
    )
    // The first step is the root of the app, so there is nowhere further back.
    expect(screen.queryByRole("button", { name: "Back" })).toBeNull()
  })

  it("asks for the keyboard only for the name", async () => {
    const user = userEvent.setup()
    render(<App />)

    const fields = () =>
      [...document.querySelectorAll("input")].filter(
        (input) => input.type !== "file" && input.type !== "checkbox"
      )
    expect(fields().map((input) => input.getAttribute("aria-label"))).toEqual([
      "Your name",
    ])

    for (const next of [
      "Age",
      "Experience",
      "Goal",
      "Session length",
      "Your gym",
      "Health",
    ]) {
      await user.click(
        screen.getByRole("button", { name: `Continue to ${next}` })
      )
      expect(fields()).toHaveLength(0)
    }
    // Numbers are dials, not text boxes.
    expect(screen.queryByRole("spinbutton")).not.toBeInTheDocument()
  })

  it("can be skipped without leaving setup due again", async () => {
    const user = userEvent.setup()
    const { unmount } = render(<App />)

    await user.click(screen.getByRole("button", { name: "Skip setup" }))
    expect(
      screen.getByRole("heading", { name: "My workouts" })
    ).toBeInTheDocument()
    expect(useTrainingProfile.getState().onboarding.completed).toBe(true)

    unmount()
    render(<App />)
    expect(
      screen.getByRole("heading", { name: "My workouts" })
    ).toBeInTheDocument()
  })

  it("never interrupts someone who already has a library", () => {
    useWorkouts.getState().createWorkout({
      name: "Push day",
      date: "2026-09-02",
      exerciseIds: ["0001"],
    })
    render(<App />)

    expect(
      screen.getByRole("heading", { name: "My workouts" })
    ).toBeInTheDocument()
    expect(useTrainingProfile.getState().onboarding.completed).toBe(false)
  })

  it("leaves the exercise picker exactly as it was", async () => {
    const user = userEvent.setup()
    useTrainingProfile.setState(completedOnboardingState())
    useFilters.getState().setGymEquipment(["barbell"])
    render(<App />)

    await user.click(screen.getByRole("button", { name: "New workout" }))
    expect(screen.getByRole("heading", { name: "Muscles" })).toBeInTheDocument()
    await user.click(screen.getByRole("button", { name: /Front Chest/ }))
    await user.click(screen.getByRole("button", { name: /choose equipment/i }))

    // The gym profile is not a filter: the picker still starts from nothing.
    expect(useFilters.getState().selectedEquipment).toEqual([])
    await user.click(screen.getByRole("checkbox", { name: "Dumbbell" }))
    expect(useFilters.getState().selectedEquipment).toEqual(["dumbbell"])
    expect(useFilters.getState().gymEquipment).toEqual(["barbell"])
    await user.click(screen.getByRole("button", { name: /show exercises/i }))
    expect(
      screen.getByRole("heading", { name: "Exercises" })
    ).toBeInTheDocument()
  })
})

describe("training profile in Settings", () => {
  beforeEach(() => {
    freshInstall()
    useTrainingProfile.setState(completedOnboardingState())
  })

  it("lists two groups and two single entries, each summarised", () => {
    openSettings()

    const profileRow = screen.getByRole("button", { name: /^Profile/ })
    expect(profileRow).toHaveTextContent("Not set")
    expect(profileRow).toHaveTextContent("30 · Beginner")
    expect(screen.getByRole("button", { name: /^Training/ })).toHaveTextContent(
      "General fitness · 60 min"
    )
    expect(
      screen.getByRole("button", { name: /^Priority muscles/ })
    ).toHaveTextContent("None")
    expect(
      screen.getByRole("button", { name: /^Health & eligibility/ })
    ).toHaveTextContent("Ready to train")
    expect(
      screen.getByRole("button", { name: /^Available equipment/ })
    ).toHaveTextContent("Not set")

    // The questions those two rows group are not also rows of their own.
    expect(screen.queryByRole("button", { name: /^Age/ })).toBeNull()
    expect(screen.queryByRole("button", { name: /^Experience/ })).toBeNull()
    expect(screen.queryByRole("button", { name: /^Session length/ })).toBeNull()
  })

  it("walks the profile group one question at a time", async () => {
    const user = userEvent.setup()
    openSettings()

    await user.click(screen.getByRole("button", { name: /^Profile/ }))
    expect(
      screen.getByRole("heading", { name: "Your name" })
    ).toBeInTheDocument()
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument()
    expect(screen.getByRole("progressbar")).toHaveAttribute(
      "aria-label",
      "Step 1 of 3"
    )

    await user.type(
      screen.getByRole("textbox", { name: "Your name" }),
      "Sam Fisher"
    )
    await user.click(screen.getByRole("button", { name: "Continue to Age" }))
    await user.click(screen.getByRole("slider", { name: "Age" }))
    await user.keyboard("{PageUp}")
    await user.click(
      screen.getByRole("button", { name: "Continue to Experience" })
    )
    await user.click(screen.getByRole("radio", { name: /Advanced/ }))
    await user.click(screen.getByRole("button", { name: "Done with profile" }))

    expect(profile()).toMatchObject({
      name: "Sam Fisher",
      age: 35,
      trainingExperience: "advanced",
    })
    expect(screen.getByRole("heading", { name: "Settings" })).toBeVisible()
    const profileRow = screen.getByRole("button", { name: /^Profile/ })
    expect(profileRow).toHaveTextContent("Sam Fisher")
    expect(profileRow).toHaveTextContent("35 · Advanced")
  })

  it("walks the training group and leaves by its first step", async () => {
    const user = userEvent.setup()
    openSettings()

    await user.click(screen.getByRole("button", { name: /^Training/ }))
    expect(screen.getByRole("heading", { name: "Goal" })).toBeInTheDocument()

    await user.click(screen.getByRole("radio", { name: /Get stronger/ }))
    await user.click(
      screen.getByRole("button", { name: "Continue to Session length" })
    )
    await user.click(
      screen.getByRole("slider", { name: "Preferred session duration" })
    )
    await user.keyboard("{ArrowDown}{ArrowDown}{ArrowDown}")
    await user.click(screen.getByRole("button", { name: "Previous step" }))

    // Back from the first step leaves the group rather than the app.
    expect(screen.getByRole("heading", { name: "Goal" })).toBeInTheDocument()
    await user.click(screen.getByRole("button", { name: "Back" }))

    expect(screen.getByRole("heading", { name: "Settings" })).toBeVisible()
    expect(profile()).toMatchObject({
      goal: "strength",
      preferredSessionDurationMinutes: 45,
    })
    expect(screen.getByRole("button", { name: /^Training/ })).toHaveTextContent(
      "Get stronger · 45 min"
    )
  })

  it("records health eligibility in the engine's own vocabulary", async () => {
    const user = userEvent.setup()
    openSettings()

    await user.click(
      screen.getByRole("button", { name: /^Health & eligibility/ })
    )
    expect(screen.getByRole("heading", { name: "Health" })).toBeInTheDocument()
    await user.click(screen.getByRole("checkbox", { name: /rehabilitation/i }))
    await user.click(screen.getByRole("button", { name: /^Done with health/ }))

    expect(profile().health).toEqual({
      status: "unsupported",
      reasons: ["rehabilitation"],
    })
    expect(
      screen.getByRole("button", { name: /^Health & eligibility/ })
    ).toHaveTextContent("Manual only")
  })

  it("sets muscle priority by tapping the body map, and shows it in the paint", async () => {
    const user = userEvent.setup()
    openSettings()

    await user.click(screen.getByRole("button", { name: /^Priority muscles/ }))
    expect(
      screen.getByRole("heading", { name: "Priority muscles" })
    ).toBeInTheDocument()

    const chest = () => screen.getByRole("button", { name: /Front Chest/ })
    const paint = () =>
      (chest() as unknown as SVGGElement).style.getPropertyValue(
        "--muscle-weight"
      )

    // The map is the whole control: tapping again walks the scale and back off.
    await user.click(chest())
    expect(profile().priorityMuscles).toEqual([
      { muscleId: "chest", level: "high" },
    ])
    const more = paint()

    await user.click(chest())
    expect(profile().priorityMuscles).toEqual([
      { muscleId: "chest", level: "specialization" },
    ])
    const focus = paint()

    await user.click(chest())
    expect(profile().priorityMuscles).toEqual([
      { muscleId: "chest", level: "low" },
    ])
    const less = paint()

    // A stronger level paints more strongly, which is the only readout there is.
    expect(Number(less)).toBeLessThan(Number(more))
    expect(Number(more)).toBeLessThan(Number(focus))
    expect(Number(focus)).toBe(1)

    await user.click(chest())
    expect(profile().priorityMuscles).toEqual([])

    // Nothing sits under the figure pushing it around.
    expect(screen.queryByRole("button", { name: "Chest: Focus" })).toBeNull()
  })

  it("configures gym equipment through the same grid and presets", async () => {
    const user = userEvent.setup()
    useFilters.setState({
      equipmentPresets: [
        { id: "saved", name: "My gym", equipment: ["barbell", "cable"] },
      ],
    })
    openSettings()

    await user.click(
      screen.getByRole("button", { name: /^Available equipment/ })
    )
    expect(
      screen.getByRole("heading", { name: "Available equipment" })
    ).toBeInTheDocument()

    await user.click(screen.getByRole("button", { name: "My gym" }))
    expect(useFilters.getState().gymEquipment).toEqual(["barbell", "cable"])

    await user.click(screen.getByRole("checkbox", { name: "Dumbbell" }))
    expect(useFilters.getState().gymEquipment).toContain("dumbbell")

    // Saving from here fills the same preset list the picker uses.
    await user.click(
      screen.getByRole("button", { name: "Create equipment preset" })
    )
    await user.type(
      screen.getByRole("textbox", { name: "Preset name" }),
      "Travel"
    )
    await user.click(screen.getByRole("button", { name: "Save preset" }))
    await waitFor(() =>
      expect(useFilters.getState().equipmentPresets).toHaveLength(2)
    )
    expect(useFilters.getState().equipmentPresets[1]).toMatchObject({
      name: "Travel",
      equipment: ["barbell", "cable", "dumbbell"],
    })

    await user.click(
      screen.getByRole("button", { name: "Done choosing equipment" })
    )
    expect(
      screen.getByRole("button", { name: /^Available equipment/ })
    ).toHaveTextContent("3 items")
    // Nothing here touched the browse filter.
    expect(useFilters.getState().selectedEquipment).toEqual([])
  })

  it("clears the profile along with everything else", async () => {
    const user = userEvent.setup()
    useTrainingProfile.getState().updateProfile({ name: "Sam", age: 44 })
    useFilters.getState().setGymEquipment([...EQUIPMENT_OPTIONS])
    openSettings()

    await user.click(screen.getByRole("button", { name: /Clear all data/ }))
    const confirm = await screen.findByRole("dialog", {
      name: "Clear all data?",
    })
    await user.click(
      within(confirm).getByRole("button", { name: "Clear data" })
    )
    await user.click(
      within(confirm).getByRole("button", { name: "Delete everything" })
    )

    expect(profile()).toMatchObject({ name: "", age: 30 })
    expect(useTrainingProfile.getState().onboarding.completed).toBe(false)
    expect(useFilters.getState().gymEquipment).toEqual([])
  })
})
