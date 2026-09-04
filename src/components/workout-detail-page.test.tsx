import { useState, type ComponentProps } from "react"
import { act, render, screen, waitFor, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, describe, expect, it, vi } from "vitest"

import { WorkoutDetailPage } from "@/components/workout-detail-page"
import { shareWorkout } from "@/lib/workout-sharing"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useWorkouts } from "@/store/use-workouts"

vi.mock("@/lib/workout-sharing", () => ({ shareWorkout: vi.fn() }))

type DetailCallbacks = Pick<
  ComponentProps<typeof WorkoutDetailPage>,
  | "onAddExercise"
  | "onBack"
  | "onFindAlternative"
  | "onOpenExercise"
  | "onDelete"
  | "onDiscard"
  | "onFinish"
>

function detailCallbacks(
  overrides: Partial<DetailCallbacks> = {}
): DetailCallbacks {
  return {
    onAddExercise: () => {},
    onBack: () => {},
    onFindAlternative: () => {},
    onOpenExercise: () => {},
    onDelete: () => {},
    onDiscard: () => {},
    onFinish: () => {},
    ...overrides,
  }
}

function MissingWorkoutHarness() {
  const [showDetail, setShowDetail] = useState(true)

  if (!showDetail) return <p>Workouts</p>

  return (
    <WorkoutDetailPage
      {...detailCallbacks({ onBack: () => setShowDetail(false) })}
      workoutId="missing"
    />
  )
}

describe("WorkoutDetailPage", () => {
  beforeEach(() => {
    localStorage.clear()
    useWorkouts.setState({ workouts: [] })
    useActiveWorkout.setState({ session: null, lastOutcome: null })
  })

  // Starting is guarded by a countdown, and every test that wants a running
  // session wants it now rather than three seconds from now — which is exactly
  // what the countdown's own "start now" affordance is for.
  async function startNow(user: ReturnType<typeof userEvent.setup>) {
    await user.click(screen.getByRole("button", { name: "Start workout" }))
    await user.click(screen.getByRole("button", { name: "Start now" }))
  }

  function renderWorkout(
    exerciseIds: string[],
    callbacks: Partial<DetailCallbacks> = {}
  ) {
    const workoutId = useWorkouts.getState().createWorkout({
      name: "Workout",
      date: "2026-09-01",
      exerciseIds,
    })

    render(
      <WorkoutDetailPage
        {...detailCallbacks(callbacks)}
        workoutId={workoutId}
      />
    )

    return workoutId
  }

  it("navigates away from a missing workout after rendering", () => {
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {})

    render(<MissingWorkoutHarness />)

    expect(screen.getByText("Workouts")).toBeInTheDocument()
    expect(
      consoleError.mock.calls.some((call) =>
        String(call[0]).includes("Cannot update a component")
      )
    ).toBe(false)
    consoleError.mockRestore()
  })

  it("confirms a delete in a popover before touching the workout", async () => {
    const user = userEvent.setup()
    const workoutId = useWorkouts.getState().createWorkout({
      name: "Workout",
      date: "2026-09-01",
      exerciseIds: ["0001"],
    })
    const onDelete = vi.fn()

    render(
      <WorkoutDetailPage
        {...detailCallbacks({ onDelete })}
        workoutId={workoutId}
      />
    )

    await user.click(screen.getByRole("button", { name: "Delete workout" }))
    const confirm = await screen.findByRole("dialog", {
      name: "Delete workout?",
    })
    expect(useWorkouts.getState().workouts).toHaveLength(1)
    expect(onDelete).not.toHaveBeenCalled()

    await user.click(
      within(confirm).getByRole("button", { name: "Delete workout" })
    )
    expect(onDelete).toHaveBeenCalledOnce()
  })

  it("opens the alternatives page for a busy exercise", async () => {
    const user = userEvent.setup()
    const workoutId = useWorkouts.getState().createWorkout({
      name: "Workout",
      date: "2026-09-01",
      exerciseIds: ["0001"],
    })

    const onFindAlternative = vi.fn()
    render(
      <WorkoutDetailPage
        {...detailCallbacks({ onFindAlternative })}
        workoutId={workoutId}
      />
    )

    await user.click(screen.getByRole("button", { name: "Find alternative" }))
    expect(onFindAlternative).toHaveBeenCalledWith(
      expect.objectContaining({ id: "0001" })
    )
    expect(useWorkouts.getState().workouts[0].exerciseIds).toEqual(["0001"])
  })

  it("starts a session on the first exercise and tracks it through to the end", async () => {
    const user = userEvent.setup()
    const workoutId = renderWorkout(["0001", "0002"], {
      onFinish: () => useActiveWorkout.getState().finish(),
    })

    await startNow(user)

    const session = useActiveWorkout.getState().session
    expect(session).toMatchObject({ workoutId, currentExerciseId: "0001" })
    const timer = screen.getByRole("timer")
    const timerPanel = timer.closest(".active-workout-timer")
    const pageSurface = document.querySelector(".app-page-surface")
    const scroller = document.querySelector(".app-scroll-region")
    const footer = document.querySelector('footer[data-slot="app-controls"]')

    expect(timer).toHaveTextContent("00:00")
    expect(pageSurface).toContainElement(timerPanel as HTMLElement)
    expect(scroller).not.toContainElement(timerPanel as HTMLElement)
    expect(footer).not.toContainElement(timerPanel as HTMLElement)

    const hero = screen.getByRole("region", { name: "Current exercise" })
    expect(within(hero).getByText("3/4 sit-up")).toBeInTheDocument()
    expect(
      within(hero).queryByRole("button", { name: "Mark done" })
    ).not.toBeInTheDocument()

    await user.click(screen.getByRole("button", { name: "Mark done" }))
    expect(useActiveWorkout.getState().session).toMatchObject({
      completedIds: ["0001"],
      currentExerciseId: "0002",
    })

    await user.click(screen.getByRole("button", { name: "Finish workout" }))
    const confirm = await screen.findByRole("dialog", {
      name: "Finish workout?",
    })
    await user.click(
      within(confirm).getByRole("button", { name: "Finish workout" })
    )
    expect(useActiveWorkout.getState()).toMatchObject({
      session: null,
      lastOutcome: "finished",
    })
    // Whatever the footer offers a finished workout, the clock is gone.
    expect(screen.queryByRole("timer")).not.toBeInTheDocument()
  })

  it("asks before finishing a running session, and cancelling leaves it alone", async () => {
    const user = userEvent.setup()
    const onFinish = vi.fn()
    renderWorkout(["0001"], { onFinish })

    await startNow(user)
    await user.click(screen.getByRole("button", { name: "Finish workout" }))
    const confirm = await screen.findByRole("dialog", {
      name: "Finish workout?",
    })
    expect(useActiveWorkout.getState().session).not.toBeNull()
    expect(onFinish).not.toHaveBeenCalled()

    await user.click(within(confirm).getByRole("button", { name: "Cancel" }))
    expect(useActiveWorkout.getState().session).not.toBeNull()
    expect(onFinish).not.toHaveBeenCalled()
  })

  it("pauses and resumes the workout clock", async () => {
    const user = userEvent.setup()
    renderWorkout(["0001"])

    await startNow(user)
    await user.click(screen.getByRole("button", { name: "Pause workout" }))
    expect(useActiveWorkout.getState().session?.runningSince).toBeNull()

    await user.click(screen.getByRole("button", { name: "Resume workout" }))
    expect(useActiveWorkout.getState().session?.runningSince).not.toBeNull()
  })

  it("keeps the checklist out of another workout's session", async () => {
    const user = userEvent.setup()
    renderWorkout(["0001"])
    useActiveWorkout.setState({
      session: {
        workoutId: "some-other-workout",
        workoutName: "Pull day",
        workoutDate: "2026-09-02",
        exerciseIds: ["0002"],
        completedIds: [],
        currentExerciseId: "0002",
        runningSince: Date.now(),
        accumulatedMs: 0,
        startedAt: Date.now(),
      },
    })

    expect(screen.queryByRole("timer")).not.toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Start workout" })).toBeVisible()

    await startNow(user)
    expect(useActiveWorkout.getState().session?.workoutId).not.toBe(
      "some-other-workout"
    )
  })

  it("asks before discarding a running session", async () => {
    const user = userEvent.setup()
    const onDiscard = vi.fn()
    renderWorkout(["0001"], { onDiscard })

    await startNow(user)
    await user.click(screen.getByRole("button", { name: "Discard session" }))
    const confirm = await screen.findByRole("dialog", {
      name: "Discard this session?",
    })
    expect(useActiveWorkout.getState().session).not.toBeNull()
    expect(onDiscard).not.toHaveBeenCalled()

    await user.click(
      within(confirm).getByRole("button", { name: "Discard session" })
    )
    expect(onDiscard).toHaveBeenCalledOnce()
  })

  it("shows a loader while a share is in flight", async () => {
    const user = userEvent.setup()
    let finishShare: (result: "shared") => void = () => {}
    vi.mocked(shareWorkout).mockReturnValue(
      new Promise((resolve) => {
        finishShare = resolve
      })
    )
    renderWorkout(["0001"])

    await user.click(screen.getByRole("button", { name: "Share workout" }))
    expect(
      screen.getByRole("status", { name: "Sharing workout" })
    ).toBeInTheDocument()

    await act(async () => {
      finishShare("shared")
    })
    await waitFor(() => {
      expect(
        screen.queryByRole("status", { name: "Sharing workout" })
      ).not.toBeInTheDocument()
    })
  })

  it("keeps the workout editable while it is being performed", async () => {
    const user = userEvent.setup()
    const workoutId = renderWorkout(["0001", "0002"])

    await startNow(user)

    expect(
      screen.getByRole("button", { name: "Reorder 3/4 sit-up" })
    ).toBeInTheDocument()
    expect(
      screen.getAllByRole("button", { name: "Find alternative" })
    ).toHaveLength(2)

    await user.click(screen.getByRole("button", { name: "Remove 3/4 sit-up" }))

    expect(
      useWorkouts.getState().workouts.find((item) => item.id === workoutId)
        ?.exerciseIds
    ).toEqual(["0002"])
    // The session follows the edit rather than pointing at a removed exercise.
    expect(useActiveWorkout.getState().session).toMatchObject({
      exerciseIds: ["0002"],
      currentExerciseId: "0002",
    })
  })

  it("counts a workout in before the clock starts, and can be called off", async () => {
    const user = userEvent.setup()
    renderWorkout(["0001"])

    await user.click(screen.getByRole("button", { name: "Start workout" }))
    expect(useActiveWorkout.getState().session).toBeNull()

    await user.click(screen.getByRole("button", { name: "Cancel" }))
    expect(useActiveWorkout.getState().session).toBeNull()
    expect(
      screen.queryByRole("dialog", { name: "Starting workout" })
    ).not.toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Start workout" })).toBeVisible()
  })

  it("adds an exercise to a workout that is already being performed", async () => {
    const user = userEvent.setup()
    const onAddExercise = vi.fn()
    const workoutId = useWorkouts.getState().createWorkout({
      name: "Workout",
      date: "2026-09-01",
      exerciseIds: ["0001"],
    })

    render(
      <WorkoutDetailPage
        {...detailCallbacks({ onAddExercise })}
        workoutId={workoutId}
      />
    )

    await startNow(user)
    await user.click(screen.getByRole("button", { name: "Add exercise" }))
    expect(onAddExercise).toHaveBeenCalledOnce()

    // The session follows exercises added from anywhere, not just this page.
    useWorkouts.getState().updateWorkout(workoutId, {
      exerciseIds: ["0001", "0002"],
    })
    expect(useActiveWorkout.getState().session).toMatchObject({
      exerciseIds: ["0001", "0002"],
    })
  })

  it("changes the date from a popover without leaving the page", async () => {
    const user = userEvent.setup()
    const workoutId = renderWorkout(["0001"])

    await user.click(
      screen.getByRole("button", {
        name: /^Change date, currently/,
      })
    )

    const calendar = await screen.findByRole("dialog", {
      name: "Choose workout date",
    })
    // The page it was opened from is still the page underneath.
    expect(screen.getByRole("button", { name: "Add exercise" })).toBeVisible()

    await user.click(
      within(calendar).getByRole("button", { name: /September 4/ })
    )

    await waitFor(() =>
      expect(
        useWorkouts.getState().workouts.find((item) => item.id === workoutId)
          ?.date
      ).toBe("2026-09-04")
    )
  })

  it("offers no skip once this is the last exercise left", async () => {
    const user = userEvent.setup()
    renderWorkout(["0001"])

    await startNow(user)
    expect(
      screen.getByRole("button", { name: "Skip 3/4 sit-up" })
    ).toHaveAttribute("aria-disabled", "true")
  })

  it("skips to the next exercise from the in-progress dock", async () => {
    const user = userEvent.setup()
    renderWorkout(["0001", "0002", "0003"])

    await startNow(user)
    expect(useActiveWorkout.getState().session?.currentExerciseId).toBe("0001")

    await user.click(screen.getByRole("button", { name: "Skip 3/4 sit-up" }))
    expect(useActiveWorkout.getState().session?.currentExerciseId).toBe("0002")
  })
})
