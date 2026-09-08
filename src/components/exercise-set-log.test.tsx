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
/** The station each performed set was measured at, in order. */
const stations = () =>
  loggedSets()
    .filter((set) => set.observation?.completed)
    .map((set) =>
      set.observation?.resistance && "stationId" in set.observation.resistance
        ? set.observation.resistance.stationId
        : null
    )

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
    // The dial opens on nothing: an empty bar is 0 kg and the first step says
    // so, and only then does the load climb.
    await step(user, "Load", "Increase", 3)
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
    await step(user, "Load", "Increase", 3)
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
    await step(user, "Load", "Increase", 5)
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
    await step(user, "Load", "Increase")
    await user.click(screen.getByRole("button", { name: /Log set 1/ }))
    expect(loggedSets()).toHaveLength(1)

    await user.click(screen.getByRole("button", { name: /Edit set 1 of/ }))
    await user.click(screen.getByRole("button", { name: "Delete this set" }))

    expect(loggedSets()).toEqual([])
  })

  it("logs at the station the person picked, and never pools two stacks", async () => {
    const user = userEvent.setup()
    renderRunningWorkout()
    await start(user)
    await user.click(screen.getByRole("button", { name: /^Log a set/ }))

    // One tap adds a second bar for this exercise and moves logging to it.
    await user.click(
      screen.getByRole("button", {
        name: "Add another station for this exercise",
      })
    )
    await step(user, "Load", "Increase")
    await user.click(screen.getByRole("button", { name: /Log set 1/ }))

    const station = records().data.settings.loadConfigurations[0]
    expect(station.exerciseId).toBe(BENCH)
    expect(station.stationId.startsWith("barbell#")).toBe(true)
    expect(records().data.settings.activeLoadConfigurations).toEqual({
      [BENCH]: station.id,
    })
    expect(loggedSets()[0].observation?.resistance).toMatchObject({
      stationId: station.stationId,
      basis: "total",
    })

    // Switching back to the default bar logs against the default station: the
    // two are never added together, however similar the numbers look.
    await user.click(screen.getByRole("button", { name: /^Log set 2/ }))
    await user.click(screen.getByRole("button", { name: "Log at Barbell" }))
    await step(user, "Load", "Increase")
    await user.click(screen.getByRole("button", { name: /Log set 2/ }))

    expect(
      loggedSets().map((set) =>
        set.observation?.resistance && "stationId" in set.observation.resistance
          ? set.observation.resistance.stationId
          : null
      )
    ).toEqual([station.stationId, "barbell"])
  })

  it("says what the engine decided, and only what it decided", async () => {
    const user = userEvent.setup()
    renderRunningWorkout()
    await start(user)

    // No logged sets anywhere: the only honest line is that there is nothing
    // to progress from yet.
    expect(screen.getByText(/Not enough logged sets yet/)).toBeInTheDocument()

    await user.click(screen.getByRole("button", { name: /^Log a set/ }))
    await step(user, "Load", "Increase", 3)
    await user.click(screen.getByRole("button", { name: "2 reps in reserve" }))
    await user.click(screen.getByRole("button", { name: /Log set 1/ }))

    // A single set inside the running session is still not a completed
    // exposure, so nothing claims a load was earned.
    expect(screen.queryByText(/top of the range/i)).not.toBeInTheDocument()
  })

  it("describes a station with the dial and gives it back with one tap", async () => {
    const user = userEvent.setup()
    renderRunningWorkout()
    await start(user)
    await user.click(screen.getByRole("button", { name: /^Log a set/ }))
    await user.click(
      screen.getByRole("button", { name: /Show load steps for Barbell/ })
    )

    // The step this gym's bar actually offers, turned rather than typed.
    await user.click(
      screen.getByRole("button", { name: "Increase barbell load step" })
    )
    expect(records().data.settings.loadConfigurations).toEqual([
      {
        id: expect.any(String),
        exerciseId: BENCH,
        stationId: "barbell",
        basis: "total",
        grid: { incrementKg: 2.75, minimumKg: 0 },
      },
    ])

    // The lightest load the station has is the other half of the same station,
    // and describing it does not fork a second record.
    await user.click(
      screen.getByRole("button", { name: "Set the lightest load" })
    )
    await user.click(
      screen.getByRole("button", { name: "Increase barbell lightest load" })
    )
    expect(records().data.settings.loadConfigurations).toMatchObject([
      { grid: { incrementKg: 2.75, minimumKg: 0.5 } },
    ])

    // Logging follows the described station immediately: the dial establishes
    // its lightest load and then climbs in its own step.
    await user.click(screen.getByRole("button", { name: /Increase load/ }))
    await user.click(screen.getByRole("button", { name: /Increase load/ }))
    await user.click(screen.getByRole("button", { name: /Log set 1/ }))
    expect(loggedSets()[0].observation?.resistance).toMatchObject({
      kg: 3.25,
      stationId: "barbell",
    })

    // Handing the station back leaves the equipment default in place.
    await user.click(screen.getByRole("button", { name: /^Log set 2/ }))
    await user.click(
      screen.getByRole("button", { name: /Show load steps for Barbell/ })
    )
    await user.click(
      screen.getByRole("button", { name: /Use equipment default/ })
    )
    expect(records().data.settings.loadConfigurations).toEqual([])
    expect(records().data.settings.activeLoadConfigurations).toEqual({})
  })

  it("leaves an earlier set on the station it was performed at", async () => {
    const user = userEvent.setup()
    renderRunningWorkout()
    await start(user)

    // Set 1 on the bar the exercise starts on.
    await user.click(screen.getByRole("button", { name: /^Log a set/ }))
    await step(user, "Load", "Increase", 3)
    await user.click(screen.getByRole("button", { name: /Log set 1/ }))

    // Set 2 after moving to another bar.
    await user.click(screen.getByRole("button", { name: /^Log set 2/ }))
    await user.click(
      screen.getByRole("button", {
        name: "Add another station for this exercise",
      })
    )
    await step(user, "Load", "Increase")
    await user.click(screen.getByRole("button", { name: /Log set 2/ }))
    const second = records().data.settings.loadConfigurations[0]
    expect(stations()).toEqual(["barbell", second.stationId])

    // Correcting the reps of the first set touches the reps of the first set.
    await user.click(screen.getByRole("button", { name: /Edit set 1 of/ }))
    await step(user, "Reps", "Increase")
    await user.click(screen.getByRole("button", { name: /Save set 1/ }))

    expect(stations()).toEqual(["barbell", second.stationId])
    expect(loggedSets()[0].observation).toMatchObject({ reps: 11 })
    expect(loggedSets()[0].observation?.resistance).toMatchObject({ kg: 5 })
    // And the exercise is still pointed at the bar being used now.
    expect(records().data.settings.activeLoadConfigurations).toEqual({
      [BENCH]: second.id,
    })
  })

  it("corrects a set's station only when asked, and only that set", async () => {
    const user = userEvent.setup()
    renderRunningWorkout()
    await start(user)
    await user.click(screen.getByRole("button", { name: /^Log a set/ }))
    await step(user, "Load", "Increase", 3)
    await user.click(screen.getByRole("button", { name: /Log set 1/ }))

    // The set was logged on the default bar but performed on another one.
    await user.click(screen.getByRole("button", { name: /Edit set 1 of/ }))
    await user.click(
      screen.getByRole("button", {
        name: "Add another station for this exercise",
      })
    )
    await user.click(screen.getByRole("button", { name: /Save set 1/ }))

    const corrected = records().data.settings.loadConfigurations[0]
    expect(stations()).toEqual([corrected.stationId])
    // The kilograms were real; only where they were measured changed.
    expect(loggedSets()[0].observation?.resistance).toMatchObject({ kg: 5 })
    // Correcting one set says nothing about where the next one happens.
    expect(records().data.settings.activeLoadConfigurations ?? {}).toEqual({})
  })

  it("opens unset on a station nothing has been logged at yet", async () => {
    const user = userEvent.setup()
    renderRunningWorkout()
    await start(user)
    await user.click(screen.getByRole("button", { name: /^Log a set/ }))
    await step(user, "Load", "Increase", 3)
    await user.click(screen.getByRole("button", { name: /Log set 1/ }))

    await user.click(screen.getByRole("button", { name: /^Log set 2/ }))
    await user.click(
      screen.getByRole("button", {
        name: "Add another station for this exercise",
      })
    )

    // 5 kg on one bar says nothing about the next one, so the dial states
    // nothing and the set cannot be recorded until it does.
    const load = screen.getByRole("group", { name: "Load" })
    expect(within(load).getByText("—")).toBeInTheDocument()
    const submit = screen.getByRole("button", { name: /Dial in the load/ })
    // Marked disabled rather than natively disabled, so a tap can still say
    // why; either way it records nothing.
    expect(submit).toHaveAttribute("aria-disabled", "true")
    await user.click(submit)
    expect(loggedSets()).toHaveLength(1)
  })

  it("does not hand a deleted station's identity to the next one", async () => {
    const user = userEvent.setup()
    renderRunningWorkout()
    await start(user)
    await user.click(screen.getByRole("button", { name: /^Log a set/ }))
    await user.click(
      screen.getByRole("button", {
        name: "Add another station for this exercise",
      })
    )
    await step(user, "Load", "Increase", 3)
    await user.click(screen.getByRole("button", { name: /Log set 1/ }))
    const retired = records().data.settings.loadConfigurations[0].stationId

    // The machine is deleted, and a different one described in its place.
    await user.click(screen.getByRole("button", { name: /^Log set 2/ }))
    await user.click(
      screen.getByRole("button", { name: /Show load steps for Barbell 2/ })
    )
    await user.click(screen.getByRole("button", { name: /Remove Barbell 2/ }))
    await user.click(
      screen.getByRole("button", {
        name: "Add another station for this exercise",
      })
    )

    const replacement = records().data.settings.loadConfigurations[0].stationId
    expect(replacement).not.toBe(retired)
    // The set logged at the machine that is gone keeps its own identity, so
    // nothing compares it with the one described afterwards.
    expect(stations()).toEqual([retired])
  })

  it("describes a rack by the loads it actually has", async () => {
    const user = userEvent.setup()
    renderRunningWorkout()
    await start(user)
    await user.click(screen.getByRole("button", { name: /^Log a set/ }))
    await user.click(
      screen.getByRole("button", { name: /Show load steps for Barbell/ })
    )
    await user.click(
      screen.getByRole("button", { name: "List the loads this station has" })
    )

    // Three loads, dialled and added; the second one twice, which is still one
    // load. Nothing is saved while the list is being written.
    const dial = screen.getByRole("slider", { name: /load to add/ })
    const add = () =>
      user.click(screen.getByRole("button", { name: /^Add \d/ }))
    await user.click(dial)
    await user.keyboard("{End}")
    expect(records().data.settings.loadConfigurations).toEqual([])

    for (const load of [40, 27.5, 27.5, 60]) {
      await user.click(dial)
      await user.keyboard("{Home}")
      for (let step = 0; step < load / 0.5; step += 1)
        await user.keyboard("{ArrowUp}")
      if (
        !screen
          .getByRole("button", { name: `Add ${load} kg` })
          .hasAttribute("aria-disabled")
      )
        await add()
    }
    await user.click(screen.getByRole("button", { name: "Save loads" }))

    expect(records().data.settings.loadConfigurations[0].grid).toEqual({
      availableLoadsKg: [27.5, 40, 60],
    })

    // The dial in the editor now steps that rack and nothing between.
    await step(user, "Load", "Increase")
    await step(user, "Load", "Increase")
    await user.click(screen.getByRole("button", { name: /Log set 1/ }))
    expect(loggedSets()[0].observation?.resistance).toMatchObject({ kg: 40 })
  }, 30000)

  it("leaves a listed rack alone unless it is told to", async () => {
    const user = userEvent.setup()
    records().saveLoadConfiguration({
      exerciseId: BENCH,
      stationId: "barbell",
      basis: "total",
      grid: { availableLoadsKg: [20, 30, 45] },
    })
    renderRunningWorkout()
    await start(user)
    await user.click(screen.getByRole("button", { name: /^Log a set/ }))
    await user.click(
      screen.getByRole("button", { name: /Show load steps for Barbell/ })
    )

    // Asking for the step dial does not round the rack away: it offers the
    // conversion and waits.
    await user.click(screen.getByRole("button", { name: "Set the load step" }))
    expect(records().data.settings.loadConfigurations[0].grid).toEqual({
      availableLoadsKg: [20, 30, 45],
    })

    // Removing a load and backing out leaves the rack as it was.
    await user.click(
      screen.getByRole("button", { name: "List the loads this station has" })
    )
    await user.click(
      screen.getByRole("button", { name: /Remove 30 kg from Barbell/ })
    )
    await user.click(
      screen.getByRole("button", {
        name: /Discard changes to Barbell loads/,
      })
    )
    expect(records().data.settings.loadConfigurations[0].grid).toEqual({
      availableLoadsKg: [20, 30, 45],
    })

    // Converting is a thing to press.
    await user.click(screen.getByRole("button", { name: "Set the load step" }))
    await user.click(
      screen.getByRole("button", { name: "Use even steps instead" })
    )
    expect(records().data.settings.loadConfigurations[0].grid).toEqual({
      incrementKg: 2.5,
      minimumKg: 20,
    })
  }, 30000)
})
