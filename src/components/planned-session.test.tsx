import { act, render, screen, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, describe, expect, it } from "vitest"

import { WorkoutDetailPage } from "@/components/workout-detail-page"
import { WorkoutsPage } from "@/components/workouts-page"
import {
  createTrainingWeek,
  plannedWorkoutFor,
  type PlannedSessionView,
} from "@/lib/training-plan"
import { substituteRunningPlannedExercise } from "@/lib/planned-substitution"
import { replacementIds } from "@/lib/training-workflow"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useFilters } from "@/store/use-filters"
import { DEFAULT_SETTINGS, useSettings } from "@/store/use-settings"
import { useTrainingProfile } from "@/store/use-training-profile"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts, type Workout } from "@/store/use-workouts"
import { createEmptyPersistedTrainingState } from "@/training-persistence/schema"

const records = () => useTrainingRecords.getState()
const NOW = "2026-09-07T10:00:00.000Z"

function week() {
  const outcome = createTrainingWeek({ days: [0, 2, 4], now: NOW })
  if (outcome.status !== "created") throw new Error(outcome.message)
  return outcome.sessions
}

function detailProps() {
  return {
    onAddExercise: () => {},
    onBack: () => {},
    onFindAlternative: () => {},
    onOpenExercise: () => {},
    onDelete: () => {},
    onDiscard: () => {},
    onFinish: () => {},
  }
}

function renderPlannedDetail(session: PlannedSessionView) {
  const workout = plannedWorkoutFor(session)!
  render(<WorkoutDetailPage {...detailProps()} workoutId={workout.id} />)
  return workout
}

/**
 * Confirms the first prescribed set of the first exercise.
 *
 * The prescription names reps and effort but, until something has been logged
 * at this station, no load — so the person states the one they used. That is
 * the point: a set is recorded from what was performed, never from what was
 * planned.
 */
async function logFirstPlannedSet(user: ReturnType<typeof userEvent.setup>) {
  await user.click(screen.getAllByRole("button", { name: /^Log set 1 of / })[0])
  const load = screen.queryByRole("group", { name: "Load" })
  if (load)
    await user.click(
      within(load).getByRole("button", { name: "Increase load" })
    )
  await user.click(screen.getByRole("button", { name: "Save set 1" }))
}

async function startNow(user: ReturnType<typeof userEvent.setup>) {
  await user.click(screen.getByRole("button", { name: "Start workout" }))
  await user.click(screen.getByRole("button", { name: "Start now" }))
}

describe("planned sessions in the existing workout UI", () => {
  beforeEach(() => {
    localStorage.clear()
    useTrainingRecords.setState({
      data: createEmptyPersistedTrainingState(),
      persistenceIssues: [],
    })
    useWorkouts.setState({ workouts: [] })
    useActiveWorkout.setState({ session: null, lastOutcome: null })
    useTrainingProfile.getState().resetTrainingProfile()
    useSettings.setState(DEFAULT_SETTINGS)
    useFilters.setState({
      equipmentPresets: [],
      gymEquipment: ["dumbbell"],
      selectedEquipment: [],
      selectedMuscles: [],
    })
  })

  it("lists the plan above next workouts and opens a session through the existing detail page", async () => {
    const user = userEvent.setup()
    const sessions = week()
    const opened: Workout[] = []
    render(
      <WorkoutsPage
        onCreate={() => {}}
        onCreatePlan={() => {}}
        onDelete={() => {}}
        onSelect={(workout) => opened.push(workout)}
        onSettings={() => {}}
      />
    )

    const plan = screen.getByRole("region", { name: /training plan/i })
    expect(within(plan).getAllByRole("button")).toHaveLength(sessions.length)
    expect(
      within(plan).getAllByText(new RegExp(`· ${sessions[0].title}$`))
    ).toHaveLength(sessions.length)
    // A planned session is not repeated under Next workouts.
    expect(
      screen.queryByRole("region", { name: /next workouts/i })
    ).not.toBeInTheDocument()

    await user.click(within(plan).getAllByRole("button")[0])
    expect(opened).toHaveLength(1)
    expect(opened[0].planned).toEqual({
      programId: sessions[0].programId,
      sessionId: sessions[0].sessionId,
    })
  })

  it("shows the prescription on the workout detail page before anything is performed", () => {
    const sessions = week()
    renderPlannedDetail(sessions[0])

    const first = sessions[0].prescription[0]
    const reps =
      first.reps.min === first.reps.max
        ? `${first.reps.max}`
        : `${first.reps.min}–${first.reps.max}`
    expect(
      screen.getAllByText(
        new RegExp(`${first.sets} × ${reps} · RIR ${first.rir}`)
      ).length
    ).toBeGreaterThan(0)
    expect(screen.getByLabelText("Planned session")).toHaveTextContent(
      String(sessions[0].workingSets)
    )
    // The plan owns the day and the exercise list; this page does not edit them.
    expect(
      screen.queryByRole("button", { name: /Change date/ })
    ).not.toBeInTheDocument()
    expect(
      screen.queryByRole("button", { name: "Delete workout" })
    ).not.toBeInTheDocument()
  })

  it("starts a planned structured draft and logs an actual set against the planned one", async () => {
    const user = userEvent.setup()
    const sessions = week()
    const workout = renderPlannedDetail(sessions[0])

    await startNow(user)

    const draft = records().data.activeWorkout!
    expect(draft.plannedProgramId).toBe(sessions[0].programId)
    expect(draft.plannedSessionId).toBe(sessions[0].sessionId)
    expect(draft.sourceWorkoutId).toBe(workout.id)
    expect(
      draft.exercises.every((exercise) =>
        exercise.sets.every((set) => set.target && !set.observation)
      )
    ).toBe(true)

    const exercise = draft.exercises[0]
    const first = exercise.sets[0]
    await logFirstPlannedSet(user)

    const recorded = records().data.activeWorkout!.exercises.find(
      (item) => item.id === exercise.id
    )!
    const logged = recorded.sets.find((set) => set.observation?.completed)!
    // The observation is written against the planned set it answers, the
    // target it was measured against is untouched, and no other planned set
    // has quietly gained one.
    expect(logged.id).toBe(first.id)
    expect(logged.plannedSetId).toBe(first.plannedSetId)
    expect(logged.target).toEqual(first.target)
    expect(logged.observation?.reps).toBeGreaterThan(0)
    expect(
      recorded.sets.filter((set) => set.observation?.completed)
    ).toHaveLength(1)
  })

  it("uses an engine-approved live substitution without rewriting the prescription", async () => {
    const user = userEvent.setup()
    const sessions = week()
    const workout = renderPlannedDetail(sessions[0])
    const originalProgram = JSON.stringify(records().data.programs[0])

    await startNow(user)

    const before = records().data.activeWorkout!.exercises[0]
    const replacementId = replacementIds(before.exerciseId).find(
      (exerciseId) => !workout.exerciseIds.includes(exerciseId)
    )
    expect(replacementId).toBeDefined()

    substituteRunningPlannedExercise(
      workout.id,
      before.exerciseId,
      replacementId!
    )

    const after = records().data.activeWorkout!.exercises.find(
      (exercise) => exercise.id === before.id
    )!
    expect(after.exerciseId).toBe(replacementId)
    expect(after.plannedExerciseId).toBe(before.plannedExerciseId)
    expect(after.sets.map((set) => set.plannedSetId)).toEqual(
      before.sets.map((set) => set.plannedSetId)
    )
    expect(replacementIds(replacementId!)).toContain(before.plannedExerciseId)
    expect(useActiveWorkout.getState().session?.exerciseIds).toContain(
      replacementId
    )
    expect(
      useWorkouts.getState().workouts.find((item) => item.id === workout.id)
        ?.exerciseIds
    ).toContain(replacementId)
    expect(JSON.stringify(records().data.programs[0])).toBe(originalProgram)
  })

  it("offers planned alternatives only during the live session and locks a recorded exercise", async () => {
    const user = userEvent.setup()
    const sessions = week()
    const workout = plannedWorkoutFor(sessions[0])!
    const opened: string[] = []
    render(
      <WorkoutDetailPage
        {...detailProps()}
        onFindAlternative={(exercise) => opened.push(exercise.id)}
        workoutId={workout.id}
      />
    )

    expect(
      screen.queryByRole("button", { name: "Find alternative" })
    ).not.toBeInTheDocument()
    await startNow(user)
    expect(
      screen.getAllByRole("button", { name: "Find alternative" }).length
    ).toBeGreaterThan(0)

    await logFirstPlannedSet(user)
    await user.click(
      screen.getAllByRole("button", { name: "Find alternative" })[0]
    )

    expect(opened).toEqual([])
    expect(screen.getByRole("alert")).toHaveTextContent(
      /already has recorded sets/i
    )
  })

  it("saves only performed sets when a planned session ends early", async () => {
    const user = userEvent.setup()
    const sessions = week()
    renderPlannedDetail(sessions[0])
    const original = JSON.stringify(records().data.programs[0])

    await startNow(user)
    const draft = records().data.activeWorkout!
    const performed = draft.exercises[0]
    const untouched = draft.exercises[1]

    await logFirstPlannedSet(user)

    useActiveWorkout.getState().cancel()

    const saved = records().data.sessions[0]
    expect(saved.status).toBe("partial")
    expect(saved.exercises).toHaveLength(1)
    expect(saved.exercises[0].exerciseId).toBe(performed.exerciseId)
    expect(
      saved.exercises.some((item) => item.exerciseId === untouched.exerciseId)
    ).toBe(false)
    // Prescription is history of its own and survives the session unchanged.
    expect(JSON.stringify(records().data.programs[0])).toBe(original)
  })

  it("says the session will be recorded as partial when the plan is unfinished", async () => {
    const user = userEvent.setup()
    const sessions = week()
    renderPlannedDetail(sessions[0])

    await startNow(user)
    await logFirstPlannedSet(user)
    await user.click(screen.getByRole("button", { name: "Finish workout" }))

    // The same confirmation, telling the truth about what it is about to write.
    expect(screen.getByRole("dialog")).toHaveTextContent(/partial session/i)
    expect(
      screen.getAllByRole("button", { name: "Finish workout" }).length
    ).toBeGreaterThan(0)
  })

  it("does not celebrate checkmarks while prescribed sets remain unlogged", async () => {
    const user = userEvent.setup()
    const sessions = week()
    renderPlannedDetail(sessions[0])
    await startNow(user)
    const exercise = records().data.activeWorkout!.exercises[0]
    const set = exercise.sets.find((item) => item.setType === "working")!
    act(() => {
      records().recordSet({
        exerciseEntryId: exercise.id,
        setDraftId: set.id,
        observation: {
          completed: true,
          reps: 8,
          resistance: {
            type: "external_load",
            kg: 40,
            basis: "total",
            stationId: "Rack A",
          },
        },
      })
      for (const id of useActiveWorkout.getState().session!.exerciseIds)
        useActiveWorkout.getState().toggleComplete(id)
    })
    expect(
      screen.queryByText(/Every exercise done|Whole session done/)
    ).not.toBeInTheDocument()

    await user.click(screen.getByRole("button", { name: "Finish workout" }))
    expect(screen.getByRole("dialog")).toHaveTextContent(/partial session/i)
  })

  it("asks the plain question once the whole prescription is performed", async () => {
    const user = userEvent.setup()
    const sessions = week()
    renderPlannedDetail(sessions[0])

    await startNow(user)
    for (const exercise of records().data.activeWorkout!.exercises)
      for (const set of exercise.sets)
        if (set.setType !== "warmup")
          records().recordSet({
            exerciseEntryId: exercise.id,
            setDraftId: set.id,
            observation: {
              reps: 8,
              rir: 2,
              resistance: {
                type: "external_load",
                kg: 40,
                basis: "total",
                stationId: "Rack A",
              },
              completed: true,
            },
          })

    await user.click(screen.getByRole("button", { name: "Finish workout" }))

    const dialog = screen.getByRole("dialog")
    expect(dialog).not.toHaveTextContent(/partial session/i)
    expect(dialog).toHaveTextContent(/saved to your history/i)
  })

  it("keeps a hand-built workout free of any program identity", async () => {
    const user = userEvent.setup()
    week()
    const workoutId = useWorkouts.getState().createWorkout({
      name: "",
      date: "2026-09-02",
      exerciseIds: ["0001", "0002"],
    })
    render(<WorkoutDetailPage {...detailProps()} workoutId={workoutId} />)

    // The manual flow keeps every control it always had.
    expect(
      screen.getByRole("button", { name: "Delete workout" })
    ).toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: "Add exercise" })
    ).toBeInTheDocument()

    await startNow(user)
    const draft = records().data.activeWorkout!
    expect(draft.plannedProgramId).toBeUndefined()
    expect(draft.plannedSessionId).toBeUndefined()
    expect(draft.exercises.flatMap((item) => item.sets)).toEqual([])
  })

  it("keeps an unavailable planned projection locked and does not start it as a free workout", () => {
    const sessions = week()
    const workout = plannedWorkoutFor(sessions[0])!
    useTrainingRecords.setState((state) => ({
      data: {
        ...state.data,
        activeProgramId: undefined,
        programs: [],
      },
    }))

    render(<WorkoutDetailPage {...detailProps()} workoutId={workout.id} />)

    expect(screen.getByRole("alert")).toHaveTextContent(
      /planned session is no longer available/i
    )
    expect(
      screen.getByRole("button", { name: "Plan unavailable" })
    ).toHaveAttribute("aria-disabled", "true")
    expect(
      screen.queryByRole("button", { name: "Delete workout" })
    ).not.toBeInTheDocument()
    expect(useActiveWorkout.getState().start(workout)).toBe(false)
    expect(useActiveWorkout.getState().session).toBeNull()
    expect(records().data.activeWorkout).toBeNull()
  })

  it("shows a prescribed load without letting it become a set at another station", async () => {
    const user = userEvent.setup()
    const sessions = week()
    const workout = renderPlannedDetail(sessions[0])
    await startNow(user)

    // The plan prescribes against the station the engine planned for. Put a
    // load on that prescription, then move to a machine it was not measured at.
    const draft = records().data.activeWorkout!
    const exercise = draft.exercises[0]
    const planned = exercise.sets.find((set) => set.setType === "working")!
    act(() => {
      const data = structuredClone(records().data)
      const target = data
        .activeWorkout!.exercises.find((item) => item.id === exercise.id)!
        .sets.find((item) => item.id === planned.id)!
      target.target = {
        ...target.target!,
        resistance: {
          type: "external_load",
          kg: 40,
          basis: "total",
          stationId: "dumbbell",
        },
      }
      useTrainingRecords.setState({ data })
    })

    await user.click(
      screen.getAllByRole("button", { name: /^Log set \d of / })[0]
    )
    await user.click(
      screen.getByRole("button", {
        name: "Add another station for this exercise",
      })
    )

    // The prescription stays on the card; the dial does not inherit its load.
    const load = screen.getByRole("group", { name: "Load" })
    expect(within(load).getByText("—")).toBeInTheDocument()
    const [submit] = screen.getAllByRole("button", { name: /Dial in the load/ })
    expect(submit).toHaveAttribute("aria-disabled", "true")
    expect(workout).toBeTruthy()
  })
})
