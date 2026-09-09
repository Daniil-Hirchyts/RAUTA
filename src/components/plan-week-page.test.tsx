import { render, screen, waitFor } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, describe, expect, it, vi } from "vitest"

import { PlanWeekPage } from "@/components/plan-week-page"
import { useFilters } from "@/store/use-filters"
import { DEFAULT_SETTINGS, useSettings } from "@/store/use-settings"
import { useTrainingProfile } from "@/store/use-training-profile"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts } from "@/store/use-workouts"
import { createEmptyPersistedTrainingState } from "@/training-persistence/schema"

const records = () => useTrainingRecords.getState()

function renderPage(
  overrides: Partial<Parameters<typeof PlanWeekPage>[0]> = {}
) {
  const props = {
    onBack: vi.fn(),
    onCreated: vi.fn(),
    onOpenProfilePage: vi.fn(),
    ...overrides,
  }
  render(<PlanWeekPage {...props} />)
  return props
}

describe("PlanWeekPage", () => {
  beforeEach(() => {
    localStorage.clear()
    useTrainingRecords.setState({
      data: createEmptyPersistedTrainingState(),
      persistenceIssues: [],
    })
    useWorkouts.setState({ workouts: [] })
    useTrainingProfile.getState().resetTrainingProfile()
    useSettings.setState(DEFAULT_SETTINGS)
    useFilters.setState({
      equipmentPresets: [],
      gymEquipment: ["dumbbell"],
      selectedEquipment: [],
      selectedMuscles: [],
    })
  })

  it("asks for calendar dates and nothing the profile already knows", () => {
    useTrainingProfile
      .getState()
      .updateProfile({
        goal: "hypertrophy",
        preferredSessionDurationMinutes: 45,
      })
    renderPage()

    expect(screen.getByRole("grid")).toBeInTheDocument()
    expect(screen.getByText("3 training dates selected.", { exact: false })).toBeInTheDocument()
    // What is already saved is shown back, never asked for again.
    expect(screen.getByText(/Build muscle · 45 min/)).toBeInTheDocument()
    for (const asked of [/goal/i, /how old/i, /equipment/i, /experience/i])
      expect(screen.queryByRole("radiogroup", { name: asked })).toBeNull()
  })

  it("creates a plan from the selected calendar dates", async () => {
    const user = userEvent.setup()
    const props = renderPage()

    await user.click(screen.getByRole("button", { name: "Create plan" }))

    await waitFor(() => expect(props.onCreated).toHaveBeenCalledOnce())
    const program = records().data.programs[0]
    expect(records().data.activeProgramId).toBe(program.id)
    const sessions = program.snapshot.weeks[0].sessions
    expect(sessions).toHaveLength(3)
    // The suggested Monday, Wednesday and Friday are exact stored dates.
    const start = Date.parse(program.snapshot.weeks[0].start)
    expect(
      sessions.map((session) =>
        Math.round((Date.parse(session.scheduledAt) - start) / 86_400_000)
      )
    ).toEqual([0, 2, 4])
    expect(useWorkouts.getState().workouts).toHaveLength(3)
  })

  it("cannot ask for a plan with no dates in it", async () => {
    const user = userEvent.setup()
    renderPage()

    while (document.querySelector<HTMLButtonElement>("td[aria-selected='true'] button"))
      await user.click(
        document.querySelector<HTMLButtonElement>(
          "td[aria-selected='true'] button"
        )!
      )

    expect(screen.getByText("Pick at least one date.")).toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Create plan" })).toHaveAttribute(
      "aria-disabled",
      "true"
    )
  })

  it("explains a refusal in place and offers the page that can answer it", async () => {
    const user = userEvent.setup()
    useTrainingProfile.getState().toggleHealthLimitation("rehabilitation")
    const props = renderPage()

    await user.click(screen.getByRole("button", { name: "Create plan" }))

    const alert = await screen.findByRole("alert")
    expect(alert).toHaveTextContent(/health answers/i)
    expect(props.onCreated).not.toHaveBeenCalled()
    // No weaker plan was invented in place of the one that was refused.
    expect(records().data.programs).toEqual([])
    expect(useWorkouts.getState().workouts).toEqual([])

    await user.click(screen.getByRole("button", { name: "Open health" }))
    expect(props.onOpenProfilePage).toHaveBeenCalledWith("profile-health")
  })
})
