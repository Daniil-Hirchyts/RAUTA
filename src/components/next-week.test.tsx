import { render, screen, waitFor, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import * as engine from "@/training"

import { PlanWeekPage } from "@/components/plan-week-page"
import { WorkoutsPage } from "@/components/workouts-page"
import { createNextTrainingWeek } from "@/lib/training-adaptation"
import { activeProgramRecord } from "@/lib/training-plan"
import {
  ADAPT_NOW,
  adaptationWeek,
  records,
} from "@/test/training-adaptation-fixture"

const NEXT_NOW = "2026-09-20T12:00:00.000Z"

let sessions: ReturnType<typeof adaptationWeek>

beforeEach(() => {
  sessions = adaptationWeek()
  vi.setSystemTime(new Date(NEXT_NOW))
})

afterEach(() => vi.restoreAllMocks())

function workoutsPage(onCreatePlan = vi.fn()) {
  return {
    onCreatePlan,
    view: render(
      <WorkoutsPage
        onCreate={() => {}}
        onCreatePlan={onCreatePlan}
        onDelete={() => {}}
        onSelect={() => {}}
        onSettings={() => {}}
      />
    ),
  }
}

describe("next-week UI", () => {
  it("offers Plan next week only when the active week has no usable sessions", async () => {
    const user = userEvent.setup()
    const onCreatePlan = vi.fn()
    const { view } = workoutsPage(onCreatePlan)

    expect(
      screen.getByRole("button", { name: "Train with RAUTA" })
    ).toHaveTextContent("This week is done. Let’s plan the next one.")
    await user.click(
      screen.getByRole("button", { name: "Open RAUTA actions" })
    )
    expect(
      screen.getByRole("button", { name: "Plan next week" })
    ).toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: "New training week" })
    ).toBeInTheDocument()
    await user.click(screen.getByRole("button", { name: "Plan next week" }))
    expect(onCreatePlan).toHaveBeenCalledWith(sessions[0].programId)

    view.unmount()
    vi.setSystemTime(new Date(ADAPT_NOW))
    workoutsPage()
    await user.click(
      screen.getByRole("button", { name: "Open RAUTA actions" })
    )
    expect(
      screen.queryByRole("button", { name: "Plan next week" })
    ).not.toBeInTheDocument()
  })

  it("reuses PlanWeekPage as a dated continuation", async () => {
    const user = userEvent.setup()
    const onCreated = vi.fn()
    render(
      <PlanWeekPage
        onBack={() => {}}
        onCreated={onCreated}
        onOpenProfilePage={() => {}}
        sourceProgramId={sessions[0].programId}
      />
    )

    expect(
      screen.getByRole("heading", { name: "Extend training plan" })
    ).toBeInTheDocument()
    expect(
      screen.getByText("Choose every date you want to add.")
    ).toBeInTheDocument()
    for (const asked of [/goal/i, /how old/i, /equipment/i, /experience/i])
      expect(screen.queryByRole("radiogroup", { name: asked })).toBeNull()

    await user.click(screen.getByRole("button", { name: "Extend plan" }))

    await waitFor(() => expect(onCreated).toHaveBeenCalledOnce())
    expect(activeProgramRecord()?.snapshot.weeks[0].sessions).toHaveLength(3)
    expect(activeProgramRecord()?.revision).toMatchObject({
      sourceProgramId: sessions[0].programId,
      reason: "manual_regeneration",
    })
  })

  it("acknowledges an already active next-week revision in RAUTA", async () => {
    const result = createNextTrainingWeek({
      days: [1, 4],
      sourceProgramId: sessions[0].programId,
      now: NEXT_NOW,
    })
    expect(result.status).toBe("created")

    const user = userEvent.setup()
    workoutsPage()
    expect(
      screen.getByRole("button", { name: "Train with RAUTA" })
    ).toHaveTextContent("Your next week is ready.")
    await user.click(
      screen.getByRole("button", { name: "Open RAUTA actions" })
    )
    expect(
      within(screen.getByRole("dialog")).getByRole("status")
    ).toHaveTextContent("Your next week is ready.")
  })

  it("shows a controlled RAUTA refusal without replacing the source plan", async () => {
    const user = userEvent.setup()
    const onCreated = vi.fn()
    vi.spyOn(engine, "generateTrainingProgram").mockReturnValue({
      status: "infeasible",
      issues: [{ code: "VOLUME_LIMIT" }],
      suggestions: [],
    })
    render(
      <PlanWeekPage
        onBack={() => {}}
        onCreated={onCreated}
        onOpenProfilePage={() => {}}
        sourceProgramId={sessions[0].programId}
      />
    )

    await user.click(screen.getByRole("button", { name: "Extend plan" }))
    expect(await screen.findByRole("alert")).toHaveTextContent(
      /volume/i
    )
    expect(onCreated).not.toHaveBeenCalled()
    expect(records().data.programs).toHaveLength(1)
    expect(activeProgramRecord()?.id).toBe(sessions[0].programId)
  })
})
