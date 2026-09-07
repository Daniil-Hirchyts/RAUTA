import {
  act,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import * as engine from "@/training"
import { WorkoutsPage } from "./workouts-page"
import { WorkoutDetailPage } from "./workout-detail-page"
import {
  ADAPT_NOW,
  adaptationWeek,
  logPlannedSession,
  records,
} from "@/test/training-adaptation-fixture"
import { activeProgramRecord, plannedWorkoutFor } from "@/lib/training-plan"
import { adjustRemainingWeek } from "@/lib/training-adaptation"
import { useWorkouts, type Workout } from "@/store/use-workouts"
import { useTrainingRecords } from "@/store/use-training-records"
import { useActiveWorkout } from "@/store/use-active-workout"

let sessions: ReturnType<typeof adaptationWeek>
beforeEach(() => {
  sessions = adaptationWeek()
  vi.setSystemTime(new Date(ADAPT_NOW))
})
afterEach(() => vi.restoreAllMocks())

function page(onSelect: (workout: Workout) => void = () => {}) {
  return (
    <WorkoutsPage
      onCreate={() => {}}
      onCreatePlan={() => {}}
      onDelete={() => {}}
      onSettings={() => {}}
      onSelect={onSelect}
    />
  )
}

describe("RAUTA remaining-week actions", () => {
  it.each(["completed", "partial"] as const)(
    "offers a %s observation, adjusts in place, and opens the revised detail",
    async (status) => {
      logPlannedSession(sessions[0], status)
      const user = userEvent.setup()
      const opened = vi.fn()
      const view = render(page(opened))
      expect(
        screen.getByRole("button", { name: "Train with RAUTA" })
      ).toHaveTextContent(/adjust the rest of your week/)
      await user.click(
        screen.getByRole("button", { name: "Open RAUTA actions" })
      )
      await user.click(
        screen.getByRole("button", { name: "Adjust remaining week" })
      )
      await waitFor(
        () => expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
        { timeout: 3000 }
      )
      expect(
        screen.getByRole("button", { name: "Train with RAUTA" })
      ).toHaveTextContent("I adjusted 2 remaining sessions")
      const plan = screen.getByRole("region", { name: /Training plan/i })
      expect(within(plan).getAllByRole("button")).toHaveLength(2)
      await user.click(within(plan).getAllByRole("button")[0])
      expect(opened.mock.calls[0][0].planned.programId).toBe(
        activeProgramRecord()!.id
      )
      expect(opened.mock.calls[0][0].planned.programId).not.toBe(
        sessions[0].programId
      )
      view.unmount()
      await useTrainingRecords.persist.rehydrate()
      await useWorkouts.persist.rehydrate()
      render(page())
      await user.click(
        screen.getByRole("button", { name: "Open RAUTA actions" })
      )
      expect(
        screen.queryByRole("button", { name: "Adjust remaining week" })
      ).not.toBeInTheDocument()
      expect(
        within(screen.getByRole("dialog")).getByRole("status")
      ).toHaveTextContent(/already been incorporated/)
      expect(records().data.programs).toHaveLength(2)
    }
  )

  it("locks repeated taps and uses the existing loader", async () => {
    logPlannedSession(sessions[0])
    const frames: FrameRequestCallback[] = []
    vi.spyOn(window, "requestAnimationFrame").mockImplementation((callback) => {
      frames.push(callback)
      return frames.length
    })
    render(page())
    fireEvent.click(screen.getByRole("button", { name: "Open RAUTA actions" }))
    const button = screen.getByRole("button", { name: "Adjust remaining week" })
    fireEvent.click(button)
    fireEvent.click(button)
    expect(screen.getByLabelText("Adjusting your week")).toBeInTheDocument()
    expect(button).toHaveAttribute("aria-disabled", "true")
    await act(async () => {
      // Two frames allow loading to paint; unrelated animation callbacks may
      // also be scheduled by the existing sheet.
      for (let round = 0; round < 4; round++)
        frames.splice(0).forEach((frame) => frame(performance.now()))
    })
    expect(records().data.programs).toHaveLength(2)
  })

  it.each(["infeasible", "unsupported"] as const)(
    "shows a controlled RAUTA refusal for %s without creating a fallback",
    async (status) => {
      logPlannedSession(sessions[0])
      vi.spyOn(engine, "adaptTrainingProgram").mockReturnValue({
        status,
        issues: [{ code: "VOLUME_LIMIT" }],
        suggestions: [],
      })
      const user = userEvent.setup()
      render(page())
      await user.click(
        screen.getByRole("button", { name: "Open RAUTA actions" })
      )
      await user.click(
        screen.getByRole("button", { name: "Adjust remaining week" })
      )
      expect(await screen.findByRole("alert")).toHaveTextContent(
        /could not adjust the remaining week/
      )
      expect(screen.getByRole("dialog")).toBeInTheDocument()
      expect(records().data.programs).toHaveLength(1)
      expect(useWorkouts.getState().workouts).toHaveLength(3)
    }
  )

  it("keeps storage failures in the sheet with a retry", async () => {
    logPlannedSession(sessions[0])
    const user = userEvent.setup()
    render(page())
    await user.click(screen.getByRole("button", { name: "Open RAUTA actions" }))
    vi.spyOn(localStorage, "setItem").mockImplementation(() => {
      throw new Error("Device full")
    })
    await user.click(
      screen.getByRole("button", { name: "Adjust remaining week" })
    )
    expect(await screen.findByRole("alert")).toHaveTextContent(
      /could not save the adjustment/
    )
    expect(
      screen.getByRole("button", { name: "Adjust remaining week" })
    ).toBeEnabled()
    expect(records().data.programs).toHaveLength(1)
  })

  it("does not offer empty work, and explains when there are no future slots", async () => {
    const user = userEvent.setup()
    render(page())
    await user.click(screen.getByRole("button", { name: "Open RAUTA actions" }))
    expect(
      screen.queryByRole("button", { name: "Adjust remaining week" })
    ).not.toBeInTheDocument()
    expect(
      within(screen.getByRole("dialog")).getByRole("status")
    ).toHaveTextContent(/Log performed sets/)
    await user.click(
      screen.getByRole("button", { name: "Close RAUTA actions" })
    )
    vi.setSystemTime(new Date("2026-09-20T12:00:00.000Z"))
    await user.click(screen.getByRole("button", { name: "Open RAUTA actions" }))
    expect(
      within(screen.getByRole("dialog")).getByRole("status")
    ).toHaveTextContent(/no future sessions/)
  })

  it("keeps stale withdrawn projections invisible and unstartable even after their dates pass", () => {
    logPlannedSession(sessions[0])
    const stale = structuredClone(plannedWorkoutFor(sessions[1])!)
    expect(adjustRemainingWeek().status).toBe("adjusted")
    // Simulate a restored old workout store alongside the committed revision.
    useWorkouts.setState((state) => ({ workouts: [...state.workouts, stale] }))
    vi.setSystemTime(new Date("2026-09-20T12:00:00.000Z"))
    const view = render(page())
    expect(
      screen.queryByRole("button", { name: /Copy 16 Sep workout/ })
    ).not.toBeInTheDocument()
    view.unmount()
    render(
      <WorkoutDetailPage
        workoutId={stale.id}
        onAddExercise={() => {}}
        onBack={() => {}}
        onFindAlternative={() => {}}
        onOpenExercise={() => {}}
        onDelete={() => {}}
        onDiscard={() => {}}
        onFinish={() => {}}
      />
    )
    expect(screen.getByRole("alert")).toHaveTextContent(/no longer available/)
    expect(useActiveWorkout.getState().start(stale)).toBe(false)
    expect(records().data.activeWorkout).toBeNull()
  })
})
