import { beforeEach, describe, expect, it, vi } from "vitest"
import {
  useTrainingRecords,
  TRAINING_STORAGE_KEY,
} from "@/store/use-training-records"
import { useWorkouts } from "@/store/use-workouts"
import { createEmptyPersistedTrainingState } from "../schema"
import {
  generateAndSavePlan,
  nextPerformance,
  planningEquipment,
  trainingIndex,
} from "@/lib/training-workflow"
import { toEngineProgramSnapshot } from "../program"
import { validateTrainingProgram, validateGenerationRequest } from "@/training"

const store = () => useTrainingRecords.getState()
beforeEach(() => {
  localStorage.clear()
  useTrainingRecords.setState({ data: createEmptyPersistedTrainingState() })
  useWorkouts.setState({ workouts: [] })
})

describe("workout application workflow", () => {
  it("feeds partial actual work into a validated future revision while retaining A and its lineage", async () => {
    const setup = {
      age: 32,
      experience: "intermediate" as const,
      goal: "hypertrophy" as const,
      equipment: planningEquipment,
    }
    const a = generateAndSavePlan(setup, "2026-09-06T10:00:00.000Z").result
      .program
    const original = JSON.parse(JSON.stringify(store().data.programs[0]))
    const session = a.weeks[0].sessions[0]
    store().startPlannedWorkout(a.id, session.id, "2026-09-07T10:00:00.000Z")
    const draft = store().data.activeWorkout!
    const exercise = draft.exercises[0]
    const set = exercise.sets.find((s) => s.setType === "working")!
    store().recordSet({
      exerciseEntryId: exercise.id,
      setDraftId: set.id,
      observation: {
        reps: 13,
        rir: 2,
        resistance: {
          type: "external_load",
          kg: 40,
          stationId: "Station A",
          basis: "total",
        },
        completed: true,
        timestamp: "2026-09-07T10:02:00.000Z",
      },
    })
    store().completeWorkout("partial", "2026-09-07T10:10:00.000Z")
    await useTrainingRecords.persist.rehydrate()
    const saved = store().data.sessions[0]
    expect(saved.exercises[0].sets).toHaveLength(1)
    expect(saved.exercises[0].sets[0].plannedSetId).toBe(set.plannedSetId)
    expect(store().getTrainingHistory().coverage).toBe("unknown")
    const source = store().data.programs[0]
    const { result, request } = generateAndSavePlan(
      setup,
      "2026-09-08T10:00:00.000Z",
      source
    )
    expect(validateGenerationRequest(request)).toEqual([])
    expect(request.history.sessions[0].exercises[0].sets[0]).toMatchObject({
      reps: 13,
      resistance: { kg: 40 },
    })
    expect(
      validateTrainingProgram(result.program, request, trainingIndex(), {
        sourceProgram: a,
      })
    ).toMatchObject({ valid: true, issues: [] })
    expect(result.program.id).not.toBe(a.id)
    expect(
      result.program.weeks
        .flatMap((w) => w.sessions)
        .every((s) => Date.parse(s.scheduledAt) > Date.parse(request.now))
    ).toBe(true)
    expect(store().data.programs.find((p) => p.id === a.id)!.snapshot).toEqual(
      original.snapshot
    )
    expect(store().data.programs.find((p) => p.id === a.id)!.lifecycle).toBe(
      "archived"
    )
    expect(store().data.activeProgramId).toBe(result.program.id)
    expect(store().data.sessions[0].plannedProgramId).toBe(a.id)
    expect(store().data.sessions[0].plannedSessionId).toBe(session.id)
    expect(
      toEngineProgramSnapshot(
        store().data.programs.find((p) => p.id === result.program.id)!.snapshot
      )
    ).toEqual(result.program)
    // Removing performed work without recalculating the revision must fail its independent validation.
    const withoutActual = {
      ...request,
      history: { ...request.history, sessions: [] },
    }
    expect(
      validateTrainingProgram(result.program, withoutActual, trainingIndex(), {
        sourceProgram: a,
      }).valid
    ).toBe(false)
  }, 30000)

  it("uses persisted external-load exposures for progression, never legacy empty sets", async () => {
    store().saveLoadConfiguration({
      exerciseId: "0025",
      stationId: "Bench A",
      basis: "total",
      grid: { incrementKg: 2.5 },
    })
    for (const day of [1, 4]) {
      store().startFreeWorkout(["0025"], `2026-09-0${day}T10:00:00.000Z`)
      const exercise = store().data.activeWorkout!.exercises[0]
      for (let n = 0; n < 3; n++) {
        const id = store().addUnplannedSet({
          exerciseEntryId: exercise.id,
          setType: "working",
          side: "both",
        })
        store().recordSet({
          exerciseEntryId: exercise.id,
          setDraftId: id,
          observation: {
            reps: 12,
            rir: 2,
            resistance: {
              type: "external_load",
              kg: 80,
              stationId: "Bench A",
              basis: "total",
            },
            completed: true,
          },
        })
      }
      store().completeWorkout("completed", `2026-09-0${day}T10:30:00.000Z`)
    }
    await useTrainingRecords.persist.rehydrate()
    const last = store().data.sessions.at(-1)!.exercises[0]
    const result = nextPerformance(
      {
        ...last,
        sets: last.sets.map((s) => ({
          id: s.id,
          setType: s.setType,
          side: s.side,
        })),
      },
      "2026-09-06T12:00:00.000Z"
    )
    expect(result).toMatchObject({
      action: "increase_load",
      resistance: {
        type: "external_load",
        kg: 82.5,
        stationId: "Bench A",
        basis: "total",
      },
    })
  })

  it("rolls back completion if device storage fails and can retry without duplication", () => {
    store().startFreeWorkout(["0025"])
    const e = store().data.activeWorkout!.exercises[0]
    store().addUnplannedSet({
      exerciseEntryId: e.id,
      setType: "working",
      side: "both",
      observation: {
        reps: 8,
        resistance: { type: "bodyweight" },
        completed: true,
      },
    })
    const before = structuredClone(store().data)
    const disk = localStorage.getItem(TRAINING_STORAGE_KEY)
    const failing = vi.spyOn(localStorage, "setItem").mockImplementation(() => {
      throw new Error("Device storage is full")
    })
    expect(() => store().completeWorkout()).toThrow("Device storage is full")
    expect(store().data).toEqual(before)
    expect(localStorage.getItem(TRAINING_STORAGE_KEY)).toBe(disk)
    failing.mockRestore()
    store().completeWorkout()
    store().completeWorkout()
    expect(store().data.sessions).toHaveLength(1)
  })

  it("protects observed substitutions, planned set removal, and duplicate planned starts", () => {
    const a = generateAndSavePlan(
      {
        age: 30,
        experience: "beginner",
        goal: "general_fitness",
        equipment: planningEquipment,
      },
      "2026-09-06T10:00:00.000Z"
    ).result.program
    store().startPlannedWorkout(a.id, a.weeks[0].sessions[0].id)
    const e = store().data.activeWorkout!.exercises[0]
    expect(() => store().removeUnplannedSet(e.id, e.sets[0].id)).toThrow()
    store().substituteExercise(e.id, "0025")
    expect(store().data.activeWorkout!.exercises[0].plannedExerciseId).toBe(
      e.plannedExerciseId
    )
    store().recordSet({
      exerciseEntryId: e.id,
      setDraftId: e.sets[0].id,
      observation: {
        reps: 9,
        resistance: { type: "bodyweight" },
        completed: true,
      },
    })
    expect(() => store().substituteExercise(e.id, "0001")).toThrow(
      /recorded exercise/
    )
    store().completeWorkout("partial")
    expect(() =>
      store().startPlannedWorkout(a.id, a.weeks[0].sessions[0].id)
    ).toThrow(/already been recorded/)
  })
})
