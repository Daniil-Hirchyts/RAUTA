import { beforeEach, describe, expect, it, vi } from "vitest"

import {
  createEngineWorkout,
  duplicateWorkoutWithEngine,
  ensureEngineWorkout,
} from "@/lib/engine-workout"
import { createTrainingPlanForDates } from "@/lib/training-plan"
import { plannedSessionView } from "@/lib/training-plan"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useFilters } from "@/store/use-filters"
import { useTrainingProfile } from "@/store/use-training-profile"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts } from "@/store/use-workouts"
import { createEmptyPersistedTrainingState } from "@/training-persistence/schema"
import { isStartablePlannedSession } from "@/training-persistence/program"
import { deleteScheduledWorkout } from "@/lib/training-edits"

describe("engine workouts", () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ["Date"] })
    vi.setSystemTime(new Date("2026-09-09T10:00:00.000Z"))
    localStorage.clear()
    useActiveWorkout.setState({ session: null })
    useWorkouts.setState({ workouts: [] })
    useTrainingRecords.setState({
      data: createEmptyPersistedTrainingState(),
      persistenceIssues: [],
    })
    useTrainingProfile.getState().resetTrainingProfile()
    useFilters.getState().setGymEquipment(["dumbbell"])
  })

  it("creates a startable prescribed workout without replacing the active plan", () => {
    const plan = createTrainingPlanForDates({
      dates: ["2026-09-14"],
      now: "2026-09-09T10:00:00.000Z",
    })
    if (plan.status !== "created") throw new Error(plan.message)

    const id = createEngineWorkout({
      date: "2026-09-10",
      exerciseIds: ["0289"],
      now: "2026-09-09T10:00:00.000Z",
    })
    const workout = useWorkouts.getState().workouts.find((item) => item.id === id)!
    const data = useTrainingRecords.getState().data
    const record = data.programs.find((item) => item.id === workout.planned!.programId)!

    expect(data.activeProgramId).toBe(plan.programId)
    expect(record.kind).toBe("workout")
    expect(isStartablePlannedSession(data, record.id, workout.planned!.sessionId)).toBe(true)
    expect(plannedSessionView(record.id, workout.planned!.sessionId)?.prescription[0].sets).toBe(3)
  })

  it("copies any workout as a fresh engine prescription", () => {
    const sourceId = useWorkouts.getState().createWorkout({
      name: "Chest",
      date: "2026-09-09",
      exerciseIds: ["0289"],
    })
    const copiedId = duplicateWorkoutWithEngine(sourceId, "2026-09-10")
    const copy = useWorkouts.getState().workouts.find((item) => item.id === copiedId)!
    expect(copy.name).toBe("Chest copy")
    expect(copy.planned).toBeDefined()
    expect(copy.date).toBe("2026-09-10")
  })

  it("upgrades an unfinished legacy workout without changing its identity", () => {
    const id = useWorkouts.getState().createWorkout({
      name: "Legacy",
      date: "2026-09-10",
      exerciseIds: ["0289"],
    })
    expect(ensureEngineWorkout(id)).toBe(id)
    expect(useWorkouts.getState().workouts[0]).toMatchObject({
      id,
      name: "Legacy",
      date: "2026-09-10",
      planned: expect.any(Object),
    })
  })

  it("creates one plan across explicitly selected weeks", () => {
    const outcome = createTrainingPlanForDates({
      dates: ["2026-09-14", "2026-09-16", "2026-09-28"],
      now: "2026-09-09T10:00:00.000Z",
    })
    if (outcome.status !== "created") throw new Error(outcome.message)
    const program = useTrainingRecords.getState().data.programs[0]
    expect(program.snapshot.weeks).toHaveLength(2)
    expect(outcome.sessions.map((session) => session.date)).toEqual([
      "2026-09-14",
      "2026-09-16",
      "2026-09-28",
    ])
  })

  it("removes a planned workout through an immutable revision", () => {
    const outcome = createTrainingPlanForDates({
      dates: ["2026-09-14"],
      now: "2026-09-09T10:00:00.000Z",
    })
    if (outcome.status !== "created") throw new Error(outcome.message)
    const workout = useWorkouts.getState().workouts[0]
    deleteScheduledWorkout(workout.id)

    expect(useWorkouts.getState().workouts).toHaveLength(0)
    const data = useTrainingRecords.getState().data
    expect(data.programs).toHaveLength(2)
    expect(data.programs.find((item) => item.id === data.activeProgramId)?.snapshot.weeks[0].sessions).toEqual([])
  })
})
