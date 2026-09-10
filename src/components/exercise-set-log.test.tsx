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

/**
 * Logging sets.
 *
 * Which station a load was measured at is still carried on every set — the
 * engine compares kilograms only within one station — but it is no longer
 * chosen by hand mid-set: the exercise's own equipment answers it. The tests
 * that drove that picker went with it.
 */
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

    // The dial opens on an empty bar — 0 kg — and climbs from there in the
    // steps this station really has.
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
    // Saving a set starts the rest it earned, beside the target it rests
    // against.
    expect(screen.getByRole("timer", { name: /^Rest/ })).toBeInTheDocument()
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

    await step(user, "Load", "Increase", 2)
    await user.click(screen.getByRole("button", { name: /Log set 1/ }))

    // The card moves on to the second set by itself, opened on the first
    // one's load and reps; only the reps that actually changed are dialled. Effort is not asked for mid-set:
    // it is the plan's to state, and this workout has no plan.
    await step(user, "Reps", "Decrease")
    await user.click(screen.getByRole("button", { name: /Log set 2/ }))

    const observations = loggedSets().map((set) => ({
      reps: set.observation?.reps,
      rir: set.observation?.rir,
      kg:
        set.observation?.resistance && "kg" in set.observation.resistance
          ? set.observation.resistance.kg
          : null,
    }))
    // Reps and load are what the person stated; effort is left unrecorded
    // rather than guessed, because nothing here prescribed one.
    expect(observations).toEqual([
      { reps: 10, rir: undefined, kg: 5 },
      { reps: 9, rir: undefined, kg: 5 },
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
    await step(user, "Load", "Increase")
    await user.click(screen.getByRole("button", { name: /Log set 1/ }))
    expect(loggedSets()).toHaveLength(1)

    await user.click(screen.getByRole("button", { name: /Edit set 1 of/ }))
    await user.click(screen.getByRole("button", { name: "Delete this set" }))

    expect(loggedSets()).toEqual([])
  })

  it("says what the engine decided, and only what it decided", async () => {
    const user = userEvent.setup()
    renderRunningWorkout()
    await start(user)

    // No logged sets anywhere, and nothing said about it: the card opens on a
    // load of zero, which is the whole of what the engine knows.
    expect(screen.queryByText(/logged sets yet/)).toBeNull()

    await step(user, "Load", "Increase", 3)
    await user.click(screen.getByRole("button", { name: /Log set 1/ }))

    // A single set inside the running session is still not a completed
    // exposure, so nothing claims a load was earned.
    expect(screen.queryByText(/top of the range/i)).not.toBeInTheDocument()
  })

  it("keeps stale history unset when the engine requests calibration", async () => {
    const user = userEvent.setup()
    records().startFreeWorkout([BENCH], "2020-01-01T10:00:00.000Z")
    const entry = records().data.activeWorkout!.exercises[0]
    records().addUnplannedSet({
      exerciseEntryId: entry.id,
      setType: "working",
      side: "both",
      observation: {
        reps: 12,
        rir: 2,
        completed: true,
        timestamp: "2020-01-01T10:05:00.000Z",
        resistance: {
          type: "external_load",
          kg: 80,
          basis: "total",
          stationId: "barbell",
        },
      },
    })
    records().completeWorkout("completed", "2020-01-01T10:30:00.000Z")
    renderRunningWorkout()
    await start(user)
    // The engine says so, and the dial does not offer the stale number: it
    // opens at zero, to be found again from the bottom.
    expect(screen.getByText(/It has been a while/)).toBeInTheDocument()
    const load = screen.getByRole("group", { name: "Load" })
    expect(load).toHaveTextContent("0")
    expect(load).not.toHaveTextContent("80")
    expect(loggedSets()).toEqual([])
  })
})
