import {
  afterEach,
  beforeAll,
  beforeEach,
  describe,
  expect,
  it,
  vi,
} from "vitest"
import {
  rescheduleWorkout,
  substituteScheduledPlannedExercise,
} from "@/lib/training-edits"
import {
  activePlannedSessions,
  activeProgramRecord,
  createTrainingWeek,
  plannedWorkoutFor,
  projectPlannedWorkouts,
  sessionViews,
} from "@/lib/training-plan"
import {
  adjustRemainingWeek,
  remainingWeekEligibility,
} from "@/lib/training-adaptation"
import { replacementIds } from "@/lib/training-workflow"
import { toISODate } from "@/lib/date"
import {
  useActiveWorkout,
  reconcileRestoredActiveWorkout,
} from "@/store/use-active-workout"
import { useFilters } from "@/store/use-filters"
import { useTrainingProfile } from "@/store/use-training-profile"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts } from "@/store/use-workouts"
import { createEmptyPersistedTrainingState } from "@/training-persistence/schema"
import {
  isStartablePlannedSession,
  toEngineProgramSnapshot,
} from "@/training-persistence/program"
import { validatePersistedTrainingState } from "@/training-persistence/validation"
import { recordStartIntent } from "@/lib/workout-transition"
import type { TrainingProgram } from "@/training"

const records = () => useTrainingRecords.getState()
let initial: TrainingProgram
beforeAll(() => {
  useTrainingProfile.getState().resetTrainingProfile()
  useFilters.getState().setGymEquipment(["dumbbell"])
  useActiveWorkout.setState({ session: null })
  useWorkouts.setState({ workouts: [] })
  useTrainingRecords.setState({ data: createEmptyPersistedTrainingState() })
  const result = createTrainingWeek({
    days: [0, 2, 4],
    now: "2026-09-07T10:00:00.000Z",
  })
  if (result.status !== "created") throw new Error(result.message)
  initial = toEngineProgramSnapshot(activeProgramRecord()!.snapshot)
})
beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] })
  vi.setSystemTime(new Date("2026-09-15T10:00:00.000Z"))
  useActiveWorkout.setState({ session: null })
  localStorage.clear()
  useWorkouts.setState({ workouts: [] })
  useTrainingRecords.setState({ data: createEmptyPersistedTrainingState() })
  useTrainingProfile.getState().resetTrainingProfile()
  useFilters.getState().setGymEquipment(["dumbbell"])
  records().saveProgram(structuredClone(initial))
  projectPlannedWorkouts(sessionViews(initial))
})
afterEach(() => {
  vi.useRealTimers()
  vi.restoreAllMocks()
})

function logFreeSession() {
  const id = useWorkouts
    .getState()
    .createWorkout({ name: "Extra", date: "2026-09-15", exerciseIds: ["0289"] })
  records().startFreeWorkout(["0289"], "2026-09-15T08:00:00.000Z", id)
  const exercise = records().data.activeWorkout!.exercises[0]
  records().addUnplannedSet({
    exerciseEntryId: exercise.id,
    setType: "working",
    side: "both",
    observation: {
      completed: true,
      reps: 10,
      resistance: {
        type: "external_load",
        kg: 12,
        basis: "per_implement",
        stationId: "Dumbbells",
      },
    },
  })
  return records().completeWorkout("completed", "2026-09-15T08:30:00.000Z")!
}

describe("shared workout scheduling and edits", () => {
  it("moves a program session and reloads matching plan/workout dates without rewriting the source", async () => {
    const before = JSON.stringify(activeProgramRecord()!.snapshot)
    const workout = plannedWorkoutFor(activePlannedSessions()[1])!
    rescheduleWorkout(workout.id, "2026-09-17")
    const updated = useWorkouts
      .getState()
      .workouts.find((item) => item.id === workout.id)!
    expect(updated.date).toBe("2026-09-17")
    expect(
      activePlannedSessions().find(
        (item) => item.sessionId === updated.planned?.sessionId
      )?.date
    ).toBe(updated.date)
    expect(
      JSON.stringify(
        records().data.programs.find((item) => item.id === initial.id)!.snapshot
      )
    ).toBe(before)
    expect(
      isStartablePlannedSession(
        records().data,
        workout.planned!.programId,
        workout.planned!.sessionId
      )
    ).toBe(false)
    await useTrainingRecords.persist.rehydrate()
    await useWorkouts.persist.rehydrate()
    expect(activePlannedSessions().map((item) => item.date)).toEqual([
      "2026-09-14",
      "2026-09-17",
      "2026-09-18",
    ])
    expect(validatePersistedTrainingState(records().data)).toEqual([])
  })

  it("substitutes before starting, prescribes the replacement, and starts that revision", () => {
    const workout = plannedWorkoutFor(activePlannedSessions()[1])!
    const oldId = workout.exerciseIds[0]
    const alternative = replacementIds(oldId, workout.id)[0]
    expect(alternative).toBeTruthy()
    substituteScheduledPlannedExercise(workout.id, oldId, alternative)
    const changed = useWorkouts
      .getState()
      .workouts.find((item) => item.id === workout.id)!
    expect(changed.exerciseIds[0]).toBe(alternative)
    const view = activePlannedSessions().find(
      (item) => item.sessionId === changed.planned?.sessionId
    )!
    expect(view.prescription[0].exerciseId).toBe(alternative)
    expect(useActiveWorkout.getState().start(changed)).toBe(true)
    const draft = records().data.activeWorkout!
    expect(draft.exercises[0]).toMatchObject({
      exerciseId: alternative,
      plannedExerciseId: alternative,
    })
    expect(
      draft.exercises[0].sets.every((set) =>
        set.plannedSetId?.includes(alternative)
      )
    ).toBe(true)
    expect(
      useWorkouts.getState().workouts.find((item) => item.id === workout.id)
        ?.date
    ).toBe(toISODate(new Date()))
    expect(validatePersistedTrainingState(records().data)).toEqual([])
  })

  it("uses a standalone session to adapt the moved slots and retains sessions moved to another week", () => {
    rescheduleWorkout(
      plannedWorkoutFor(activePlannedSessions()[1])!.id,
      "2026-09-17"
    )
    rescheduleWorkout(
      plannedWorkoutFor(activePlannedSessions()[2])!.id,
      "2026-09-22"
    )
    const actualId = logFreeSession()
    expect(remainingWeekEligibility()).toMatchObject({
      status: "eligible",
      observationIds: [actualId],
    })
    const result = adjustRemainingWeek()
    expect(result.status).toBe("adjusted")
    expect(activePlannedSessions().map((item) => item.date)).toEqual([
      "2026-09-14",
      "2026-09-17",
      "2026-09-22",
    ])
    expect(activeProgramRecord()?.revision?.incorporatedSessionIds).toEqual([
      actualId,
    ])
    expect(remainingWeekEligibility()).toMatchObject({ reason: "incorporated" })
    for (const view of activePlannedSessions())
      expect(plannedWorkoutFor(view)?.date).toBe(view.date)
    expect(validatePersistedTrainingState(records().data)).toEqual([])
  })

  it("keeps both program sessions when rescheduling puts them on the same day", () => {
    rescheduleWorkout(
      plannedWorkoutFor(activePlannedSessions()[1])!.id,
      "2026-09-18"
    )
    logFreeSession()
    const result = adjustRemainingWeek()
    expect(result.status).toBe("adjusted")
    expect(
      activePlannedSessions().filter((item) => item.date === "2026-09-18")
    ).toHaveLength(2)
    expect(validatePersistedTrainingState(records().data)).toEqual([])
  })

  it("moves an overdue standalone workout to today and recovers an interrupted start on that same day", () => {
    const id = useWorkouts
      .getState()
      .createWorkout({
        name: "Extra",
        date: "2026-09-10",
        exerciseIds: ["0289"],
      })
    const workout = useWorkouts
      .getState()
      .workouts.find((item) => item.id === id)!
    recordStartIntent(workout, Date.now())
    records().startFreeWorkout(
      workout.exerciseIds,
      new Date().toISOString(),
      id
    )
    reconcileRestoredActiveWorkout()
    expect(useActiveWorkout.getState().session?.workoutDate).toBe("2026-09-15")
    expect(
      useWorkouts.getState().workouts.find((item) => item.id === id)?.date
    ).toBe("2026-09-15")
    expect(records().data.transition).toBeUndefined()
  })

  it("restores the workout projections when the revision cannot be saved", () => {
    const before = structuredClone(useWorkouts.getState().workouts)
    vi.spyOn(records(), "saveProgram").mockImplementation(() => {
      throw new Error("Storage unavailable")
    })
    expect(() => rescheduleWorkout(before[1].id, "2026-09-17")).toThrow(
      "Storage unavailable"
    )
    expect(useWorkouts.getState().workouts).toEqual(before)
    expect(activeProgramRecord()?.id).toBe(initial.id)
  })
})
