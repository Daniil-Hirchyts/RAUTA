import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import * as engine from "@/training"
import {
  adjustRemainingWeek,
  isObsoleteProjection,
  remainingWeekEligibility,
} from "./training-adaptation"
import {
  activePlannedSessions,
  activeProgramRecord,
  ensurePlannedWorkout,
  plannedWorkoutFor,
} from "./training-plan"
import { trainingIndex } from "./training-workflow"
import {
  useTrainingRecords,
  TRAINING_STORAGE_KEY,
} from "@/store/use-training-records"
import { useWorkouts } from "@/store/use-workouts"
import { useTrainingProfile } from "@/store/use-training-profile"
import {
  ADAPT_NOW,
  adaptationWeek,
  logPlannedSession,
  records,
} from "@/test/training-adaptation-fixture"

let sessions: ReturnType<typeof adaptationWeek>
beforeEach(() => {
  sessions = adaptationWeek()
  vi.setSystemTime(new Date(ADAPT_NOW))
})
afterEach(() => vi.restoreAllMocks())

describe("actual performance to remaining-week adaptation", () => {
  it.each(["completed", "partial"] as const)(
    "enables a %s planned observation with real sets",
    (status) => {
      const id = logPlannedSession(sessions[0], status)
      expect(remainingWeekEligibility()).toMatchObject({
        status: "eligible",
        observationIds: [id],
      })
    }
  )

  it("does not treat targets, empty completions, drafts or checked exercises as performance", () => {
    expect(remainingWeekEligibility()).toMatchObject({ reason: "empty" })
    const workout = plannedWorkoutFor(sessions[0])!
    records().startPlannedWorkout(sessions[0].programId, sessions[0].sessionId)
    expect(remainingWeekEligibility()).toMatchObject({ reason: "active" })
    records().cancelWorkout()
    logPlannedSession(sessions[0], "completed", { empty: true })
    useWorkouts.getState().completeWorkout(workout.id, {
      startedAt: "2026-09-14T10:00:00.000Z",
      completedAt: "2026-09-14T10:30:00.000Z",
      durationMs: 1800000,
      completedExerciseIds: workout.exerciseIds,
      activeCalories: 100,
      healthSyncStatus: "not-requested",
    })
    expect(remainingWeekEligibility()).toMatchObject({ reason: "empty" })
    expect(adjustRemainingWeek()).toMatchObject({
      status: "blocked",
      reason: "empty",
    })
    expect(records().data.programs).toHaveLength(1)
  })

  it("passes actual partial history, profile, goal, priorities, equipment and grids to the engine", () => {
    const id = logPlannedSession(sessions[0], "partial")
    const exerciseId = records().data.sessions[0].exercises[0].exerciseId
    useTrainingProfile.getState().updateProfile({
      age: 41,
      goal: "hypertrophy",
      trainingExperience: "advanced",
      preferredSessionDurationMinutes: 45,
    })
    useTrainingProfile.getState().setMusclePriority("chest", "specialization")
    records().saveLoadConfiguration({
      exerciseId,
      stationId: "Rack A",
      basis: "total",
      grid: { incrementKg: 2.5 },
    })
    const adapt = vi.spyOn(engine, "adaptTrainingProgram")
    const history = records().getTrainingHistory()
    const outcome = adjustRemainingWeek()
    expect(outcome.status).toBe("adjusted")
    const input = adapt.mock.calls[0][0]
    expect(input.mode).toBe("remaining_week")
    expect(input.previousProgram.id).toBe(sessions[0].programId)
    expect(input.request.history).toEqual(history)
    expect(input.request.history.sessions[0]).toMatchObject({
      id,
      status: "partial",
      exercises: [
        { exerciseId, sets: [{ reps: 13, rir: 2, resistance: { kg: 40 } }] },
      ],
    })
    expect(input.request.profile).toMatchObject({
      age: 41,
      trainingExperience: "advanced",
      health: { status: "healthy" },
    })
    expect(input.request.preferences).toMatchObject({
      goal: "hypertrophy",
      preferredSessionDurationMinutes: 45,
      priorityMuscles: [{ muscleId: "chest", level: "specialization" }],
      availableEquipment: expect.arrayContaining(["dumbbell", "bench"]),
      loadContexts: { [exerciseId]: { stationId: "Rack A", basis: "total" } },
      loadGrids: { [exerciseId]: { incrementKg: 2.5 } },
    })
    expect(input.request.schedule).toEqual({
      weekStart: "2026-09-14T00:00:00.000Z",
      days: [2, 4],
      durationWeeks: 1,
    })
  })

  it("preserves source bytes and history, replaces only future slots, and survives reload without repeats", async () => {
    const observationId = logPlannedSession(sessions[0])
    const original = JSON.stringify(activeProgramRecord()!.snapshot)
    const history = JSON.stringify(records().data.sessions)
    const completed = structuredClone(plannedWorkoutFor(sessions[0])!)
    const stale = sessions
      .slice(1)
      .map((session) => plannedWorkoutFor(session)!)
    const result = adjustRemainingWeek()
    expect(result.status).toBe("adjusted")
    if (result.status !== "adjusted") return
    expect(result.sessions.map((session) => session.date)).toEqual(
      sessions.slice(1).map((session) => session.date)
    )
    expect(
      JSON.stringify(
        records().data.programs.find(
          (program) => program.id === sessions[0].programId
        )!.snapshot
      )
    ).toBe(original)
    expect(
      records().data.programs.find(
        (program) => program.id === sessions[0].programId
      )!.lifecycle
    ).toBe("archived")
    expect(JSON.stringify(records().data.sessions)).toBe(history)
    expect(plannedWorkoutFor(sessions[0])).toEqual(completed)
    expect(activeProgramRecord()).toMatchObject({
      id: result.programId,
      lifecycle: "active",
      revision: {
        sourceProgramId: sessions[0].programId,
        reason: "remaining_week",
        asOf: ADAPT_NOW,
        incorporatedSessionIds: [observationId],
        replacedSessionIds: sessions
          .slice(1)
          .map((session) => session.sessionId),
      },
      snapshot: {
        adaptation: {
          sourceProgramId: sessions[0].programId,
          mode: "remaining_week",
          asOf: ADAPT_NOW,
        },
      },
    })
    for (const old of stale) {
      expect(
        useWorkouts.getState().workouts.find((workout) => workout.id === old.id)
      ).toBeUndefined()
      expect(isObsoleteProjection(old, records().data)).toBe(true)
      expect(() =>
        records().startPlannedWorkout(
          old.planned!.programId,
          old.planned!.sessionId
        )
      ).toThrow(/replaced/)
    }
    for (const session of result.sessions) {
      expect(plannedWorkoutFor(session)?.planned).toEqual({
        programId: result.programId,
        sessionId: session.sessionId,
      })
      expect(session.sessionId).not.toBe(
        sessions.find((old) => old.date === session.date)?.sessionId
      )
    }
    expect(adjustRemainingWeek()).toMatchObject({ reason: "incorporated" })
    await useTrainingRecords.persist.rehydrate()
    await useWorkouts.persist.rehydrate()
    expect(activeProgramRecord()?.id).toBe(result.programId)
    expect(activePlannedSessions()).toEqual(result.sessions)
    expect(
      JSON.stringify(
        records().data.programs.find(
          (program) => program.id === sessions[0].programId
        )!.snapshot
      )
    ).toBe(original)
    expect(adjustRemainingWeek("2026-09-15T13:00:00.000Z")).toMatchObject({
      reason: "incorporated",
    })
    expect(records().data.programs).toHaveLength(2)
    // Reactivating A cannot reuse the same observation or resurrect withdrawn slots.
    records().activateProgram(sessions[0].programId)
    expect(adjustRemainingWeek().status).toBe("blocked")
    expect(activePlannedSessions()).toEqual([sessions[0]])
  })

  it("enables another revision only after actual work on the revised active program", () => {
    logPlannedSession(sessions[0], "partial")
    const first = adjustRemainingWeek()
    if (first.status !== "adjusted") throw new Error(first.message)
    const secondObservation = logPlannedSession(first.sessions[0], "partial")
    const now = "2026-09-17T12:00:00.000Z"
    expect(remainingWeekEligibility(undefined, now)).toMatchObject({
      status: "eligible",
      observationIds: [secondObservation],
    })
    const second = adjustRemainingWeek(now)
    expect(second.status).toBe("adjusted")
    expect(activeProgramRecord()?.revision?.sourceProgramId).toBe(
      first.programId
    )
    expect(records().data.sessions).toHaveLength(2)
    expect(activePlannedSessions().map((session) => session.date)).toEqual([
      "2026-09-18",
    ])
  })

  it("keeps missed sessions available and early completed history intact", () => {
    logPlannedSession(sessions[1], "partial", { date: "2026-09-14" })
    const past = structuredClone(plannedWorkoutFor(sessions[0]))!
    const early = structuredClone(plannedWorkoutFor(sessions[1]))
    const original = JSON.stringify(records().data.programs[0].snapshot)
    const result = adjustRemainingWeek()
    expect(result.status).toBe("adjusted")
    expect(activePlannedSessions().map((session) => session.date)).toEqual([
      "2026-09-14",
      "2026-09-18",
    ])
    const carried = plannedWorkoutFor(activePlannedSessions()[0])!
    expect(carried.date).toBe(past.date)
    expect(carried.exerciseIds).toEqual(past.exerciseIds)
    expect(plannedWorkoutFor(sessions[1])).toEqual(early)
    expect(
      JSON.stringify(
        records().data.programs.find(
          (program) => program.id === sessions[0].programId
        )!.snapshot
      )
    ).toBe(original)
  })

  it.each(["gym-lib-workouts", TRAINING_STORAGE_KEY, "all"])(
    "rolls back when %s persistence fails and permits one retry",
    async (failingKey) => {
      logPlannedSession(sessions[0])
      const before = structuredClone(records().data)
      const workouts = structuredClone(useWorkouts.getState().workouts)
      const disk = localStorage.getItem(TRAINING_STORAGE_KEY)
      const write = localStorage.setItem.bind(localStorage)
      const failure = vi
        .spyOn(localStorage, "setItem")
        .mockImplementation((key, value) => {
          if (key === failingKey || failingKey === "all")
            throw new Error("Device full")
          write(key, value)
        })
      expect(adjustRemainingWeek()).toMatchObject({
        status: "blocked",
        reason: "persistence",
      })
      expect(records().data).toEqual(before)
      expect(useWorkouts.getState().workouts).toEqual(workouts)
      expect(localStorage.getItem(TRAINING_STORAGE_KEY)).toBe(disk)
      failure.mockRestore()
      await useTrainingRecords.persist.rehydrate()
      await useWorkouts.persist.rehydrate()
      expect(remainingWeekEligibility().status).toBe("eligible")
      expect(adjustRemainingWeek().status).toBe("adjusted")
      expect(adjustRemainingWeek()).toMatchObject({ reason: "incorporated" })
    }
  )

  it("recovers from interruption between projection staging and the revision commit", async () => {
    logPlannedSession(sessions[0])
    const sourceDisk = localStorage.getItem(TRAINING_STORAGE_KEY)!
    expect(adjustRemainingWeek().status).toBe("adjusted")
    localStorage.setItem(TRAINING_STORAGE_KEY, sourceDisk)
    await useTrainingRecords.persist.rehydrate()
    const orphan = useWorkouts
      .getState()
      .workouts.find(
        (workout) => workout.planned?.programId !== sessions[0].programId
      )!
    expect(isObsoleteProjection(orphan, records().data)).toBe(true)
    expect(() =>
      records().startPlannedWorkout(
        orphan.planned!.programId,
        orphan.planned!.sessionId
      )
    ).toThrow(/not found/)
    expect(ensurePlannedWorkout(sessions[1])).toBeTruthy()
    expect(adjustRemainingWeek().status).toBe("adjusted")
    expect(records().data.programs).toHaveLength(2)
    expect(useWorkouts.getState().workouts).toHaveLength(3)
  })

  it("returns controlled missing-source and no-future outcomes", () => {
    logPlannedSession(sessions[0])
    expect(adjustRemainingWeek("2026-09-20T12:00:00.000Z")).toMatchObject({
      reason: "future",
    })
    useTrainingRecords.setState((state) => ({
      data: { ...state.data, activeProgramId: "missing" },
    }))
    expect(adjustRemainingWeek()).toMatchObject({ reason: "source" })
  })

  it.each(["infeasible", "unsupported"] as const)(
    "preserves state when the engine returns %s",
    (status) => {
      logPlannedSession(sessions[0])
      const before = structuredClone(records().data)
      vi.spyOn(engine, "adaptTrainingProgram").mockReturnValue({
        status,
        issues: [{ code: "VOLUME_LIMIT" }],
        suggestions: [],
      })
      expect(adjustRemainingWeek()).toMatchObject({
        status: "blocked",
        reason: "engine",
      })
      expect(records().data).toEqual(before)
    }
  )

  it("uses standalone performed sets to enable adaptation and also passes legacy history", () => {
    records().startFreeWorkout(["0025"], "2026-09-14T08:00:00.000Z")
    const exercise = records().data.activeWorkout!.exercises[0]
    records().addUnplannedSet({
      exerciseEntryId: exercise.id,
      setType: "working",
      side: "both",
      observation: {
        reps: 8,
        resistance: {
          type: "external_load",
          kg: 20,
          stationId: "Rack A",
          basis: "total",
        },
        completed: true,
      },
    })
    const freeId = records().completeWorkout(
      "partial",
      "2026-09-14T08:30:00.000Z"
    )
    const legacyId = useWorkouts.getState().createWorkout({
      name: "Legacy",
      date: "2026-09-13",
      exerciseIds: ["0025"],
    })
    useWorkouts.getState().completeWorkout(legacyId, {
      startedAt: "2026-09-13T10:00:00.000Z",
      completedAt: "2026-09-13T11:00:00.000Z",
      durationMs: 3600000,
      completedExerciseIds: ["0025"],
      activeCalories: 100,
      healthSyncStatus: "not-requested",
    })
    expect(remainingWeekEligibility()).toMatchObject({
      status: "eligible",
      observationIds: [freeId],
    })
    const plannedId = logPlannedSession(sessions[0])
    const expected = records().getTrainingHistory()
    const adapt = vi.spyOn(engine, "adaptTrainingProgram")
    expect(adjustRemainingWeek().status).toBe("adjusted")
    expect(adapt.mock.calls[0][0].request.history).toEqual(expected)
    expect(activeProgramRecord()?.revision?.incorporatedSessionIds).toEqual(
      expect.arrayContaining([freeId, plannedId])
    )
    expect(
      expected.sessions
        .find((session) => session.id === legacyId)
        ?.exercises.flatMap((exercise) => exercise.sets)
    ).toEqual([])
    expect(
      records().data.sessions.find((session) => session.id === freeId)
        ?.plannedProgramId
    ).toBeUndefined()
  })

  it("uses logged load, reps, RIR and the saved increment for future progression", () => {
    const exerciseId = sessions[1].exerciseIds.find(
      (id) =>
        trainingIndex().byId.get(id)?.metadata.tracking === "external_load"
    )!
    expect(exerciseId).toBeTruthy()
    records().saveLoadConfiguration({
      exerciseId,
      stationId: "Rack A",
      basis: "total",
      grid: { incrementKg: 2.5 },
    })
    logPlannedSession(sessions[0], "completed", { exerciseId, sets: 3 })
    const result = adjustRemainingWeek()
    expect(result.status).toBe("adjusted")
    const exercises = activeProgramRecord()!
      .snapshot.weeks.flatMap((week) =>
        week.sessions.flatMap((session) => session.exercises)
      )
      .filter((exercise) => exercise.exerciseId === exerciseId)
    expect(exercises.length).toBeGreaterThan(0)
    expect(exercises[0].progression.action).toBe("increase_load")
    expect(exercises[0].workingSets[0].resistance).toMatchObject({
      type: "external_load",
      kg: 42.5,
    })
  })
})
