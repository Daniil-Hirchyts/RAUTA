import { render, screen, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, describe, expect, it } from "vitest"

import { WorkoutDetailPage } from "@/components/workout-detail-page"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts } from "@/store/use-workouts"
import { createEmptyPersistedTrainingState } from "@/training-persistence/schema"

/** Barbell bench press: total load, 2.5 kg steps. */
const BENCH = "0025"

const records = () => useTrainingRecords.getState()
const loggedSets = () => records().data.activeWorkout?.exercises[0].sets ?? []

function renderRunningWorkout() {
  const workoutId = useWorkouts.getState().createWorkout({
    name: "Push",
    date: "2026-09-01",
    exerciseIds: [BENCH],
  })
  render(
    <WorkoutDetailPage
      onAddExercise={() => {}}
      onBack={() => {}}
      onDelete={() => {}}
      onDiscard={() => {}}
      onFinish={() => {}}
      onFindAlternative={() => {}}
      onOpenExercise={() => {}}
      workoutId={workoutId}
    />
  )
  return workoutId
}

async function start(user: ReturnType<typeof userEvent.setup>) {
  await user.click(screen.getByRole("button", { name: "Start workout" }))
  await user.click(screen.getByRole("button", { name: "Start now" }))
}

async function step(
  user: ReturnType<typeof userEvent.setup>,
  group: "Load" | "Reps",
  direction: "Increase" | "Decrease",
  times = 1
) {
  const control = screen.getByRole("group", { name: group })
  const button = within(control).getByRole("button", {
    name: `${direction} ${group.toLowerCase()}`,
  })
  for (let index = 0; index < times; index += 1) await user.click(button)
}

describe("logging sets during a workout", () => {
  beforeEach(() => {
    localStorage.clear()
    useWorkouts.setState({ workouts: [] })
    useActiveWorkout.setState({ session: null, lastOutcome: null })
    useTrainingRecords.setState({ data: createEmptyPersistedTrainingState() })
  })

  it("records nothing until the set is confirmed", async () => {
    const user = userEvent.setup()
    renderRunningWorkout()
    await start(user)

    await user.click(screen.getByRole("button", { name: /^Log a set/ }))
    await step(user, "Load", "Increase", 2)
    await step(user, "Reps", "Increase")

    // The editor is showing 5 kg × 11 and the draft still holds no set at all.
    expect(screen.getByText("5")).toBeInTheDocument()
    expect(loggedSets()).toEqual([])

    await user.click(screen.getByRole("button", { name: /Log set 1/ }))

    expect(loggedSets()).toHaveLength(1)
    expect(loggedSets()[0].observation).toMatchObject({
      reps: 11,
      completed: true,
    })
    expect(loggedSets()[0].observation?.resistance).toMatchObject({
      type: "external_load",
      kg: 5,
      basis: "total",
    })
  })

  it("logs several sets, each prefilled from the one before", async () => {
    const user = userEvent.setup()
    renderRunningWorkout()
    await start(user)

    await user.click(screen.getByRole("button", { name: /^Log a set/ }))
    await step(user, "Load", "Increase", 2)
    await user.click(screen.getByRole("button", { name: "2 reps in reserve" }))
    await user.click(screen.getByRole("button", { name: /Log set 1/ }))

    // The second set opens on the first one's load and reps; only the reps that
    // actually changed have to be dialled.
    await user.click(screen.getByRole("button", { name: /^Log set 2/ }))
    await step(user, "Reps", "Decrease")
    await user.click(screen.getByRole("button", { name: "1 reps in reserve" }))
    await user.click(screen.getByRole("button", { name: /Log set 2/ }))

    const observations = loggedSets().map((set) => ({
      reps: set.observation?.reps,
      rir: set.observation?.rir,
      kg:
        set.observation?.resistance && "kg" in set.observation.resistance
          ? set.observation.resistance.kg
          : null,
    }))
    expect(observations).toEqual([
      { reps: 10, rir: 2, kg: 5 },
      { reps: 9, rir: 1, kg: 5 },
    ])

    const rows = screen.getAllByRole("button", { name: /Edit set \d of/ })
    expect(rows).toHaveLength(2)
    expect(rows[0]).toHaveTextContent("5 kg")
    expect(rows[0]).toHaveTextContent("10")
  })

  it("shows the logged sets again after a reload", async () => {
    const user = userEvent.setup()
    const workoutId = renderRunningWorkout()
    await start(user)
    await user.click(screen.getByRole("button", { name: /^Log a set/ }))
    await step(user, "Load", "Increase", 4)
    await user.click(screen.getByRole("button", { name: /Log set 1/ }))

    const stored = localStorage.getItem("gym-lib-training")!
    useTrainingRecords.setState({ data: createEmptyPersistedTrainingState() })
    localStorage.setItem("gym-lib-training", stored)
    await useTrainingRecords.persist.rehydrate()

    render(
      <WorkoutDetailPage
        onAddExercise={() => {}}
        onBack={() => {}}
        onDelete={() => {}}
        onDiscard={() => {}}
        onFinish={() => {}}
        onFindAlternative={() => {}}
        onOpenExercise={() => {}}
        workoutId={workoutId}
      />
    )

    const restored = screen.getAllByRole("button", { name: /Edit set 1 of/ })
    expect(restored[restored.length - 1]).toHaveTextContent("10 kg")
  })

  it("takes back a set logged by mistake", async () => {
    const user = userEvent.setup()
    renderRunningWorkout()
    await start(user)
    await user.click(screen.getByRole("button", { name: /^Log a set/ }))
    await user.click(screen.getByRole("button", { name: /Log set 1/ }))
    expect(loggedSets()).toHaveLength(1)

    await user.click(screen.getByRole("button", { name: /Edit set 1 of/ }))
    await user.click(screen.getByRole("button", { name: "Delete this set" }))

    expect(loggedSets()).toEqual([])
  })
})
