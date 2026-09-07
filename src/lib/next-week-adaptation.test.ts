import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import * as engine from "@/training"

import {
  createNextTrainingWeek,
  nextWeekEligibility,
} from "@/lib/training-adaptation"
import { activeProgramRecord, plannedWorkoutFor } from "@/lib/training-plan"
import { trainingIndex } from "@/lib/training-workflow"
import { useTrainingProfile } from "@/store/use-training-profile"
import {
  TRAINING_STORAGE_KEY,
  useTrainingRecords,
} from "@/store/use-training-records"
import { useWorkouts } from "@/store/use-workouts"
import {
  ADAPT_NOW,
  adaptationWeek,
  logPlannedSession,
  records,
} from "@/test/training-adaptation-fixture"

const NEXT_NOW = "2026-09-20T12:00:00.000Z"

let sessions: ReturnType<typeof adaptationWeek>

beforeEach(() => {
  sessions = adaptationWeek()
  vi.setSystemTime(new Date(NEXT_NOW))
})

afterEach(() => vi.restoreAllMocks())

describe("completed week to next-week revision", () => {
  it("becomes eligible when the week ends and stays hidden while usable sessions remain", () => {
    expect(nextWeekEligibility(undefined, ADAPT_NOW)).toMatchObject({
      status: "blocked",
      reason: "future",
    })
    expect(
      nextWeekEligibility(undefined, "2026-09-21T00:01:00.000Z")
    ).toMatchObject({ status: "eligible" })
  })

  it("does not become eligible during an active workout", () => {
    records().startPlannedWorkout(
      sessions[0].programId,
      sessions[0].sessionId,
      "2026-09-20T10:00:00.000Z"
    )
    expect(nextWeekEligibility(undefined, NEXT_NOW)).toMatchObject({
      status: "blocked",
      reason: "active",
    })
    records().cancelWorkout()
  })

  it("passes selected days, completed and partial history, profile, priorities, equipment and load grids to next_week", () => {
    const completedId = logPlannedSession(sessions[0], "completed")
    const partialId = logPlannedSession(sessions[1], "partial")
    const exerciseId = sessions
      .flatMap((session) => session.exerciseIds)
      .find(
        (id) =>
          trainingIndex().byId.get(id)?.metadata.tracking === "external_load"
      )!
    expect(exerciseId).toBeTruthy()

    useTrainingProfile.getState().updateProfile({
      age: 41,
      goal: "hypertrophy",
      trainingExperience: "advanced",
      preferredSessionDurationMinutes: 45,
    })
    useTrainingProfile
      .getState()
      .setMusclePriority("chest", "specialization")
    records().saveLoadConfiguration({
      exerciseId,
      stationId: "Dumbbells A",
      basis: "per_implement",
      grid: { incrementKg: 2.5 },
    })

    const expectedHistory = records().getTrainingHistory()
    const adapt = vi.spyOn(engine, "adaptTrainingProgram")
    const result = createNextTrainingWeek({
      days: [1, 4],
      sourceProgramId: sessions[0].programId,
      now: NEXT_NOW,
    })
    expect(result.status).toBe("created")

    const input = adapt.mock.calls[0][0]
    expect(input.mode).toBe("next_week")
    expect(input.previousProgram.id).toBe(sessions[0].programId)
    expect(input.request.schedule).toEqual({
      weekStart: "2026-09-21T00:00:00.000Z",
      days: [1, 4],
      durationWeeks: 1,
    })
    expect(input.request.history).toEqual(expectedHistory)
    expect(
      input.request.history.sessions.filter((session) =>
        [completedId, partialId].includes(session.id)
      )
    ).toMatchObject([
      { id: completedId, status: "completed" },
      { id: partialId, status: "partial" },
    ])
    expect(input.request.profile).toMatchObject({
      age: 41,
      trainingExperience: "advanced",
      health: { status: "healthy" },
    })
    expect(input.request.preferences).toMatchObject({
      goal: "hypertrophy",
      preferredSessionDurationMinutes: 45,
      priorityMuscles: [
        { muscleId: "chest", level: "specialization" },
      ],
      availableEquipment: expect.arrayContaining(["dumbbell", "bench"]),
      loadContexts: {
        [exerciseId]: {
          stationId: "Dumbbells A",
          basis: "per_implement",
        },
      },
      loadGrids: { [exerciseId]: { incrementKg: 2.5 } },
    })
  })

  it("keeps the source byte-identical, archives it, and creates new lineage and identities on selected dates", () => {
    const source = activeProgramRecord()!
    const sourceBytes = JSON.stringify(source.snapshot)
    const sourceSessionIds = new Set(
      source.snapshot.weeks.flatMap((week) =>
        week.sessions.map((session) => session.id)
      )
    )
    const sourceSetIds = new Set(
      source.snapshot.weeks.flatMap((week) =>
        week.sessions.flatMap((session) =>
          session.exercises.flatMap((exercise) =>
            [...exercise.workingSets, ...exercise.warmupSets].map(
              (set) => set.id
            )
          )
        )
      )
    )

    const result = createNextTrainingWeek({
      days: [1, 4],
      sourceProgramId: source.id,
      now: NEXT_NOW,
    })
    expect(result.status).toBe("created")
    if (result.status !== "created") return

    expect(result.sessions.map((session) => session.date)).toEqual([
      "2026-09-22",
      "2026-09-25",
    ])
    const persistedSource = records().data.programs.find(
      (program) => program.id === source.id
    )!
    expect(JSON.stringify(persistedSource.snapshot)).toBe(sourceBytes)
    expect(persistedSource.lifecycle).toBe("archived")

    const active = activeProgramRecord()!
    expect(active).toMatchObject({
      id: result.programId,
      lifecycle: "active",
      revision: {
        sourceProgramId: source.id,
        reason: "next_week",
        asOf: NEXT_NOW,
      },
      snapshot: {
        adaptation: {
          sourceProgramId: source.id,
          mode: "next_week",
          asOf: NEXT_NOW,
        },
      },
    })
    expect(active.id).not.toBe(source.id)
    for (const session of active.snapshot.weeks.flatMap((week) => week.sessions)) {
      expect(sourceSessionIds.has(session.id)).toBe(false)
      for (const set of session.exercises.flatMap((exercise) => [
        ...exercise.workingSets,
        ...exercise.warmupSets,
      ]))
        expect(sourceSetIds.has(set.id)).toBe(false)
    }
  })

  it("uses real reps, RIR and a per-implement increment for progression", () => {
    const source = activeProgramRecord()!
    const exercise = source.snapshot.weeks[0].sessions
      .flatMap((session) => session.exercises)
      .find(
        (item) =>
          trainingIndex().byId.get(item.exerciseId)?.metadata.tracking ===
          "external_load"
      )!
    expect(exercise).toBeTruthy()
    const view = sessions.find((session) =>
      session.exerciseIds.includes(exercise.exerciseId)
    )!
    records().saveLoadConfiguration({
      exerciseId: exercise.exerciseId,
      stationId: "Dumbbells A",
      basis: "per_implement",
      grid: { incrementKg: 2.5 },
    })
    logPlannedSession(view, "completed", {
      exerciseId: exercise.exerciseId,
      sets: exercise.workingSets.length,
      reps: Math.max(13, exercise.workingSets[0].targetReps.max),
      rir: exercise.workingSets[0].targetRir,
      loadKg: 40,
      stationId: "Dumbbells A",
      basis: "per_implement",
    })

    const result = createNextTrainingWeek({
      days: [0, 2, 4],
      sourceProgramId: source.id,
      now: NEXT_NOW,
    })
    expect(result.status).toBe("created")
    const next = activeProgramRecord()!.snapshot.weeks
      .flatMap((week) => week.sessions)
      .flatMap((session) => session.exercises)
      .find((item) => item.exerciseId === exercise.exerciseId)!
    expect(next.progression.action).toBe("increase_load")
    expect(next.progression.resistance).toMatchObject({
      type: "external_load",
      kg: 42.5,
      stationId: "Dumbbells A",
      basis: "per_implement",
    })
    expect(next.workingSets[0].resistance).toMatchObject({
      kg: 42.5,
      basis: "per_implement",
    })
  })

  it("keeps missing load performance unknown instead of inventing progression", () => {
    const source = activeProgramRecord()!
    const result = createNextTrainingWeek({
      days: [0, 2, 4],
      sourceProgramId: source.id,
      now: NEXT_NOW,
    })
    expect(result.status).toBe("created")
    const next = activeProgramRecord()!.snapshot.weeks
      .flatMap((week) => week.sessions)
      .flatMap((session) => session.exercises)
      .find(
        (item) =>
          trainingIndex().byId.get(item.exerciseId)?.metadata.tracking ===
          "external_load"
      )!
    expect(next.progression.action).toBe("calibrate")
    expect(next.progression.resistance).toEqual({ type: "unknown" })
    expect(next.workingSets[0].resistance).toEqual({ type: "unknown" })
  })

  it("keeps missed source projections as unperformed history but makes the archived plan non-startable", () => {
    const sourceId = sessions[0].programId
    const missed = structuredClone(plannedWorkoutFor(sessions[2])!)
    const history = structuredClone(records().data.sessions)
    expect(missed.completion).toBeNull()

    const result = createNextTrainingWeek({
      days: [1, 4],
      sourceProgramId: sourceId,
      now: NEXT_NOW,
    })
    expect(result.status).toBe("created")
    expect(records().data.sessions).toEqual(history)
    expect(plannedWorkoutFor(sessions[2])).toEqual(missed)
    expect(() =>
      records().startPlannedWorkout(sourceId, sessions[2].sessionId)
    ).toThrow(/no longer active/)
  })

  it("is idempotent across repeated calls and reload", async () => {
    const sourceId = sessions[0].programId
    const result = createNextTrainingWeek({
      days: [1, 4],
      sourceProgramId: sourceId,
      now: NEXT_NOW,
    })
    expect(result.status).toBe("created")
    expect(
      createNextTrainingWeek({
        days: [1, 4],
        sourceProgramId: sourceId,
        now: NEXT_NOW,
      })
    ).toMatchObject({ status: "blocked", reason: "already_planned" })

    await useTrainingRecords.persist.rehydrate()
    await useWorkouts.persist.rehydrate()
    expect(records().data.programs).toHaveLength(2)
    expect(
      createNextTrainingWeek({
        days: [1, 4],
        sourceProgramId: sourceId,
        now: NEXT_NOW,
      })
    ).toMatchObject({ status: "blocked", reason: "already_planned" })
    expect(nextWeekEligibility(undefined, NEXT_NOW)).toMatchObject({
      status: "blocked",
      reason: "future",
    })
  })

  it("rolls projections and program state back when persistence fails", () => {
    const sourceId = sessions[0].programId
    const before = structuredClone(records().data)
    const workouts = structuredClone(useWorkouts.getState().workouts)
    const disk = localStorage.getItem(TRAINING_STORAGE_KEY)
    const write = localStorage.setItem.bind(localStorage)
    const failure = vi
      .spyOn(localStorage, "setItem")
      .mockImplementation((key, value) => {
        if (key === TRAINING_STORAGE_KEY) throw new Error("Device full")
        write(key, value)
      })

    expect(
      createNextTrainingWeek({
        days: [1, 4],
        sourceProgramId: sourceId,
        now: NEXT_NOW,
      })
    ).toMatchObject({ status: "blocked", reason: "persistence" })
    expect(records().data).toEqual(before)
    expect(useWorkouts.getState().workouts).toEqual(workouts)
    expect(localStorage.getItem(TRAINING_STORAGE_KEY)).toBe(disk)
    failure.mockRestore()
    expect(nextWeekEligibility(undefined, NEXT_NOW).status).toBe("eligible")
  })

  it("returns a controlled refusal without changing the active program", () => {
    const before = structuredClone(records().data)
    vi.spyOn(engine, "adaptTrainingProgram").mockReturnValue({
      status: "infeasible",
      issues: [{ code: "VOLUME_LIMIT" }],
      suggestions: [],
    })
    expect(
      createNextTrainingWeek({
        days: [1, 4],
        sourceProgramId: sessions[0].programId,
        now: NEXT_NOW,
      })
    ).toMatchObject({
      status: "blocked",
      reason: "engine",
      message: "I couldn't build next week from these settings.",
    })
    expect(records().data).toEqual(before)
  })
})
