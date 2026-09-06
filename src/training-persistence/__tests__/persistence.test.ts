import { beforeEach, describe, expect, it } from "vitest"

import exercises from "../../data/exercises.generated.json"
import { useTrainingRecords } from "../../store/use-training-records"
import { useWorkouts } from "../../store/use-workouts"
import {
  calculateHistoryVolume,
  createExerciseIndex,
  DEFAULT_POLICY,
  ENGINE_VERSION,
  evaluateTrainingProgram,
  generateTrainingProgram,
} from "../../training"
import { request } from "../../training/__tests__/fixtures"
import type {
  ExerciseSummary,
  TrainingPolicy,
  TrainingProgram,
} from "../../training/domain/types"
import { toEngineLoadPreferences, toTrainingHistory } from "../history"
import {
  createPersistedProgramRecord,
  toEngineProgramSnapshot,
  toPersistedProgramSnapshot,
} from "../program"
import {
  createEmptyPersistedTrainingState,
  type PersistedCompletedSession,
  type PersistedResistance,
  type PersistedTrainingStateLatest,
} from "../schema"
import {
  migratePersistedTrainingState,
  recoverPersistedTrainingState,
  serializePersistedTrainingState,
  validatePersistedTrainingState,
} from "../validation"
import {
  addUnplannedSet,
  completeWorkoutDraft,
  createActiveWorkoutFromPlannedSession,
  createFreeWorkoutDraft,
  recordSetObservation,
  substituteDraftExercise,
} from "../workout"

function fixtureProgram(id = "program-a"): TrainingProgram {
  const policy = structuredClone(DEFAULT_POLICY)
  return {
    id,
    engineVersion: ENGINE_VERSION,
    policyVersion: policy.version,
    policy,
    datasetFingerprint: "dataset-a",
    generatedAt: "2026-09-06T10:00:00.000Z",
    goal: "strength",
    durationWeeks: 1,
    weeks: [
      {
        id: `${id}/week-0`,
        start: "2026-09-07T00:00:00.000Z",
        phase: "base",
        targets: [
          {
            muscleId: "chest",
            minimum: 4,
            preferred: 6,
            upperGuideline: 8,
            importance: 1,
            preferredExposures: 2,
          },
        ],
        sessions: [
          {
            id: `${id}/week-0/day-0`,
            scheduledAt: "2026-09-07T10:00:00.000Z",
            focus: ["chest"],
            duration: {
              generalWarmupSeconds: 300,
              specificWarmupSeconds: 0,
              workingSetSeconds: 120,
              restSeconds: 360,
              transitionSeconds: 30,
              totalSeconds: 810,
              confidence: "high",
            },
            exercises: [
              {
                exerciseId: "0025",
                order: 0,
                workingSets: [0, 1, 2].map((index) => ({
                  id: `${id}/week-0/day-0/bench/set-${index}`,
                  setType: "working" as const,
                  targetReps: { min: 8, max: 12 },
                  targetRir: 2,
                  resistance: {
                    type: "external_load" as const,
                    kg: 80,
                    basis: "total" as const,
                    stationId: "bench-a",
                  },
                  loadAcquisition: "history" as const,
                  side: "both" as const,
                })),
                warmupSets: [],
                restSeconds: 180,
                targetMuscles: ["chest"],
                rationale: { total: 1, contributions: [] },
                progression: {
                  action: "hold",
                  resistance: {
                    type: "external_load",
                    kg: 80,
                    basis: "total",
                    stationId: "bench-a",
                  },
                  targetReps: { min: 8, max: 12 },
                  confidence: "high",
                  reasons: ["within_range"],
                },
              },
            ],
          },
        ],
      },
    ],
    diagnostics: {
      splits: [{ name: "full_body", score: 1, valid: true }],
      candidateCount: 1,
      optimizerIterations: 1,
      selectedSplit: "full_body",
      score: { total: 1, contributions: [] },
      warnings: [],
    },
  }
}

function idFactory(prefix = "id") {
  let next = 0
  return (kind: "exercise" | "set") => `${prefix}-${kind}-${next++}`
}

function sessionFixture(
  id: string,
  resistance: PersistedResistance = { type: "bodyweight" },
  side: "both" | "left" | "right" = "both"
): PersistedCompletedSession {
  return {
    id,
    startedAt: "2026-09-07T10:00:00.000Z",
    completedAt: "2026-09-07T11:00:00.000Z",
    durationSeconds: 3600,
    status: "completed",
    exercises: [
      {
        id: `${id}-exercise`,
        exerciseId: "0025",
        sets: [
          {
            id: `${id}-set`,
            reps: 10,
            resistance,
            rir: 2,
            completed: true,
            setType: "working",
            side,
            timestamp: "2026-09-07T10:15:00.000Z",
          },
        ],
      },
    ],
  }
}

function stateWithProgram(program = fixtureProgram()): PersistedTrainingStateLatest {
  const state = createEmptyPersistedTrainingState()
  state.programs = [createPersistedProgramRecord(program)]
  state.activeProgramId = program.id
  return state
}

function deepFreeze<T>(value: T): T {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value)
    Object.values(value as object).forEach(deepFreeze)
  }
  return value
}

describe("versioned training persistence", () => {
  beforeEach(() => {
    localStorage.clear()
    useWorkouts.setState({ workouts: [] })
    useTrainingRecords.setState({
      data: createEmptyPersistedTrainingState(),
      persistenceIssues: [],
    })
  })

  it("validates the latest schema and deterministically migrates V0 without claiming coverage", () => {
    const latest = createEmptyPersistedTrainingState()
    expect(validatePersistedTrainingState(latest)).toEqual([])

    const input = deepFreeze({
      schemaVersion: 0 as const,
      sessions: [sessionFixture("b"), sessionFixture("a")],
      programs: [],
      settings: { loadConfigurations: [] },
    })
    const first = migratePersistedTrainingState(input)
    const second = migratePersistedTrainingState(input)
    expect(first).toEqual(second)
    expect(first.settings.historyCoverage).toEqual({ status: "unknown" })
    expect(first.sessions.map((session) => session.id)).toEqual(["a", "b"])
    expect(input.schemaVersion).toBe(0)
    expect(() => migratePersistedTrainingState({ schemaVersion: 99 })).toThrow()
  })

  it("rejects corrupt schema values instead of coercing them", () => {
    const mutations: ((state: PersistedTrainingStateLatest) => void)[] = [
      (state) => {
        state.sessions[0].completedAt = "not-a-timestamp"
      },
      (state) => {
        ;(state.sessions[0].exercises[0].sets[0].resistance as { kg: number }).kg = Number.NaN
      },
      (state) => {
        ;(state.sessions[0].exercises[0].sets[0].resistance as { kg: number }).kg = Number.POSITIVE_INFINITY
      },
      (state) => {
        ;(state.sessions[0].exercises[0].sets[0] as { side: string }).side = "center"
      },
      (state) => {
        ;(state.sessions[0].exercises[0].sets[0] as { setType: string }).setType = "failure"
      },
      (state) => {
        state.sessions.push(structuredClone(state.sessions[0]))
      },
      (state) => {
        state.sessions[0].exercises[0].sets.push(
          structuredClone(state.sessions[0].exercises[0].sets[0])
        )
      },
    ]
    for (const mutate of mutations) {
      const state = createEmptyPersistedTrainingState()
      state.sessions = [
        sessionFixture("session", {
          type: "external_load",
          kg: 80,
          basis: "total",
          stationId: "bench-a",
        }),
      ]
      mutate(state)
      expect(validatePersistedTrainingState(state).length).toBeGreaterThan(0)
    }
  })

  it("keeps legacy workouts as identity/time observations with zero fictional sets", () => {
    const legacy = deepFreeze({
      id: "legacy-1",
      completion: {
        startedAt: "2026-08-01T10:00:00.000Z",
        completedAt: "2026-08-01T10:30:00.000Z",
        durationMs: 1_800_000,
        completedExerciseIds: ["0025"],
      },
    })
    const history = toTrainingHistory(createEmptyPersistedTrainingState(), [legacy])
    expect(history).toEqual({
      coverage: "unknown",
      sessions: [
        {
          id: "legacy-1",
          startedAt: "2026-08-01T10:00:00.000Z",
          completedAt: "2026-08-01T10:30:00.000Z",
          durationSeconds: 1800,
          status: "completed",
          exercises: [{ exerciseId: "0025", sets: [] }],
        },
      ],
    })
    expect(legacy.completion.completedExerciseIds).toEqual(["0025"])
  })

  it("includes the existing legacy workout store by default without fabricating sets", () => {
    useWorkouts.setState({
      workouts: [
        {
          id: "legacy-store-1",
          name: "Old push day",
          date: "2026-08-01",
          exerciseIds: ["0025"],
          completion: {
            startedAt: "2026-08-01T10:00:00.000Z",
            completedAt: "2026-08-01T10:30:00.000Z",
            durationMs: 1_800_000,
            completedExerciseIds: ["0025"],
            activeCalories: 120,
            healthSyncStatus: "not-requested",
          },
          createdAt: "2026-08-01T09:00:00.000Z",
          updatedAt: "2026-08-01T10:30:00.000Z",
        },
      ],
    })

    const history = useTrainingRecords.getState().getTrainingHistory()
    expect(history.coverage).toBe("unknown")
    expect(history.sessions).toHaveLength(1)
    expect(history.sessions[0]).toMatchObject({
      id: "legacy-store-1",
      durationSeconds: 1800,
      exercises: [{ exerciseId: "0025", sets: [] }],
    })
  })

  it("roundtrips a planned three-set bench session using only actual observations", () => {
    const program = fixtureProgram()
    const plannedSession = program.weeks[0].sessions[0]
    let draft = createActiveWorkoutFromPlannedSession({
      draftId: "draft-1",
      programId: program.id,
      session: plannedSession,
      startedAt: "2026-09-07T10:00:00.000Z",
      makeId: idFactory("draft"),
    })
    for (const [index, set] of draft.exercises[0].sets.entries())
      draft = recordSetObservation(draft, {
        exerciseEntryId: draft.exercises[0].id,
        setDraftId: set.id,
        observation: {
          reps: [10, 9, 8][index],
          resistance: {
            type: "external_load",
            kg: 77.5,
            basis: "total",
            stationId: "bench-a",
          },
          rir: 2,
          completed: true,
          timestamp: `2026-09-07T10:${15 + index}:00.000Z`,
        },
      })
    const session = completeWorkoutDraft(draft, {
      sessionId: "completed-session-1",
      completedAt: "2026-09-07T10:30:00.000Z",
      status: "completed",
      makeId: idFactory("completed"),
    })
    const state = stateWithProgram(program)
    state.sessions = [session]
    expect(validatePersistedTrainingState(state)).toEqual([])

    const restored = migratePersistedTrainingState(
      JSON.parse(serializePersistedTrainingState(state))
    )
    const history = toTrainingHistory(restored)
    const sets = history.sessions[0].exercises[0].sets
    expect(sets.map((set) => set.reps)).toEqual([10, 9, 8])
    expect(sets.map((set) => set.plannedSetId)).toEqual(
      plannedSession.exercises[0].workingSets.map((set) => set.id)
    )
    expect(sets.every((set) => set.id !== set.plannedSetId)).toBe(true)
    expect(sets[0]).toMatchObject({
      resistance: {
        type: "external_load",
        kg: 77.5,
        basis: "total",
        stationId: "bench-a",
      },
      rir: 2,
      side: "both",
      setType: "working",
    })
  })

  it("supports a free workout with no program lineage", () => {
    let draft = createFreeWorkoutDraft({
      draftId: "free-draft",
      startedAt: "2026-09-07T10:00:00.000Z",
      exerciseIds: ["0025"],
      makeId: idFactory("free"),
    })
    draft = addUnplannedSet(draft, {
      exerciseEntryId: draft.exercises[0].id,
      setDraftId: "free-set-draft",
      setType: "working",
      side: "both",
      observation: {
        reps: 12,
        resistance: { type: "bodyweight" },
        completed: true,
      },
    })
    const session = completeWorkoutDraft(draft, {
      sessionId: "free-session",
      completedAt: "2026-09-07T10:10:00.000Z",
      status: "completed",
      makeId: idFactory("free-completed"),
    })
    expect(session.plannedProgramId).toBeUndefined()
    expect(session.plannedSessionId).toBeUndefined()
    expect(session.exercises[0].sets[0].plannedSetId).toBeUndefined()
  })

  it("preserves only performed work when a planned session ends partial", () => {
    const program = fixtureProgram()
    let draft = createActiveWorkoutFromPlannedSession({
      draftId: "partial-draft",
      programId: program.id,
      session: program.weeks[0].sessions[0],
      startedAt: "2026-09-07T10:00:00.000Z",
      makeId: idFactory("partial"),
    })
    const first = draft.exercises[0].sets[0]
    draft = recordSetObservation(draft, {
      exerciseEntryId: draft.exercises[0].id,
      setDraftId: first.id,
      observation: {
        reps: 9,
        resistance: { type: "bodyweight" },
        completed: true,
      },
    })
    const session = completeWorkoutDraft(draft, {
      sessionId: "partial-session",
      completedAt: "2026-09-07T10:15:00.000Z",
      status: "partial",
      makeId: idFactory("partial-completed"),
    })
    expect(session.status).toBe("partial")
    expect(session.exercises[0].sets).toHaveLength(1)
    expect(session.exercises[0].sets[0].reps).toBe(9)
  })

  it("represents substitutions without rewriting the historical program", () => {
    const program = fixtureProgram()
    const originalSnapshot = toPersistedProgramSnapshot(program)
    let draft = createActiveWorkoutFromPlannedSession({
      draftId: "sub-draft",
      programId: program.id,
      session: program.weeks[0].sessions[0],
      startedAt: "2026-09-07T10:00:00.000Z",
      makeId: idFactory("sub"),
    })
    draft = substituteDraftExercise(draft, {
      exerciseEntryId: draft.exercises[0].id,
      exerciseId: "0036",
    })
    draft = recordSetObservation(draft, {
      exerciseEntryId: draft.exercises[0].id,
      setDraftId: draft.exercises[0].sets[0].id,
      observation: {
        reps: 10,
        resistance: { type: "bodyweight" },
        completed: true,
      },
    })
    const session = completeWorkoutDraft(draft, {
      sessionId: "sub-session",
      completedAt: "2026-09-07T10:10:00.000Z",
      status: "partial",
      makeId: idFactory("sub-completed"),
    })
    expect(session.exercises[0]).toMatchObject({
      exerciseId: "0036",
      plannedExerciseId: "0025",
    })
    expect(toPersistedProgramSnapshot(program)).toEqual(originalSnapshot)
  })

  it("preserves station and basis and never treats different machines as one active load context", () => {
    const state = createEmptyPersistedTrainingState()
    state.sessions = [
      sessionFixture("machine-a", {
        type: "external_load",
        kg: 80,
        basis: "total",
        stationId: "gym-a-bench",
      }),
      {
        ...sessionFixture("machine-b", {
          type: "external_load",
          kg: 40,
          basis: "per_implement",
          stationId: "gym-b-dumbbells",
        }),
        startedAt: "2026-09-08T10:00:00.000Z",
        completedAt: "2026-09-08T11:00:00.000Z",
      },
    ]
    state.settings.loadConfigurations = [
      {
        id: "grid-a",
        exerciseId: "0025",
        stationId: "gym-a-bench",
        basis: "total",
        grid: { incrementKg: 2.5, minimumKg: 20, maximumKg: 200 },
      },
      {
        id: "grid-b",
        exerciseId: "0025",
        stationId: "gym-b-dumbbells",
        basis: "per_implement",
        grid: { availableLoadsKg: [20, 22.5, 25, 27.5, 30, 40] },
      },
    ]
    const history = toTrainingHistory(state)
    expect(history.sessions[0].exercises[0].sets[0].resistance).toMatchObject({
      stationId: "gym-a-bench",
      basis: "total",
    })
    expect(history.sessions[1].exercises[0].sets[0].resistance).toMatchObject({
      stationId: "gym-b-dumbbells",
      basis: "per_implement",
    })
    expect(toEngineLoadPreferences(state.settings, ["grid-a"])).toEqual({
      loadContexts: { "0025": { stationId: "gym-a-bench", basis: "total" } },
      loadGrids: {
        "0025": { incrementKg: 2.5, minimumKg: 20, maximumKg: 200 },
      },
    })
    expect(() => toEngineLoadPreferences(state.settings, ["grid-a", "grid-b"])).toThrow()
  })

  it.each([
    ["band", { type: "band_resistance" } as const],
    ["bodyweight", { type: "bodyweight" } as const],
    [
      "assistance",
      {
        type: "assistance",
        kg: 25,
        basis: "total",
        stationId: "assist-a",
      } as const,
    ],
  ])("roundtrips %s resistance without inventing another load representation", (_name, resistance) => {
    const state = createEmptyPersistedTrainingState()
    state.sessions = [sessionFixture("resistance-session", resistance)]
    const actual = toTrainingHistory(
      migratePersistedTrainingState(JSON.parse(serializePersistedTrainingState(state)))
    ).sessions[0].exercises[0].sets[0].resistance
    expect(actual).toEqual(resistance)
    if (resistance.type === "band_resistance" || resistance.type === "bodyweight")
      expect("kg" in actual).toBe(false)
  })

  it("preserves unilateral side and the engine's half-set accounting", () => {
    const state = createEmptyPersistedTrainingState()
    const session = sessionFixture("sides")
    session.exercises[0].sets = [
      { ...session.exercises[0].sets[0], id: "left", side: "left" },
      { ...session.exercises[0].sets[0], id: "right", side: "right" },
      { ...session.exercises[0].sets[0], id: "both", side: "both" },
    ]
    state.sessions = [session]
    const history = toTrainingHistory(state)
    expect(history.sessions[0].exercises[0].sets.map((set) => set.side)).toEqual([
      "left",
      "right",
      "both",
    ])
    const index = createExerciseIndex(exercises as ExerciseSummary[])
    const volume = calculateHistoryVolume(
      history,
      index,
      DEFAULT_POLICY,
      Date.parse("2026-09-01T00:00:00.000Z"),
      Date.parse("2026-09-10T00:00:00.000Z"),
      true
    )
    expect(volume.chest.direct).toBe(2)
  })

  it("preserves program revision lineage and planned references across reload", () => {
    const a = fixtureProgram("program-a")
    const b = fixtureProgram("program-b")
    b.generatedAt = "2026-09-08T10:00:00.000Z"
    b.adaptation = {
      sourceProgramId: a.id,
      asOf: "2026-09-08T10:00:00.000Z",
      mode: "remaining_week",
    }
    const state = createEmptyPersistedTrainingState()
    state.programs = [
      createPersistedProgramRecord(a, { lifecycle: "archived" }),
      createPersistedProgramRecord(b),
    ]
    state.activeProgramId = b.id
    const session = sessionFixture("revision-session")
    session.plannedProgramId = b.id
    session.plannedSessionId = b.weeks[0].sessions[0].id
    session.exercises[0].plannedExerciseId = "0025"
    session.exercises[0].sets[0].plannedSetId =
      b.weeks[0].sessions[0].exercises[0].workingSets[0].id
    state.sessions = [session]
    const restored = migratePersistedTrainingState(
      JSON.parse(serializePersistedTrainingState(state))
    )
    expect(restored.programs.find((program) => program.id === b.id)?.revision).toMatchObject({
      sourceProgramId: a.id,
      reason: "remaining_week",
    })
    expect(restored.sessions[0]).toMatchObject({
      plannedProgramId: b.id,
      plannedSessionId: b.weeks[0].sessions[0].id,
    })
  })

  it("restores the exact historical policy and dataset fingerprint", () => {
    const policy: TrainingPolicy = structuredClone(DEFAULT_POLICY)
    policy.version = "persistence-policy-test"
    policy.indirectCredit = 0.35
    const generationRequest = request({ policy })
    const generated = generateTrainingProgram(generationRequest)
    expect("program" in generated).toBe(true)
    if (!("program" in generated)) throw new Error("fixture generation failed")
    const snapshot = toPersistedProgramSnapshot(generated.program)
    const restored = toEngineProgramSnapshot(snapshot)
    expect(restored.policy).toEqual(policy)
    expect(restored.datasetFingerprint).toBe(generated.program.datasetFingerprint)
    expect(evaluateTrainingProgram(restored, generationRequest).valid).toBe(true)
  }, 30_000)

  it("does not mutate frozen program, history, or migration inputs", () => {
    const program = deepFreeze(fixtureProgram())
    const snapshot = toPersistedProgramSnapshot(program)
    deepFreeze(snapshot)
    expect(() => toEngineProgramSnapshot(snapshot)).not.toThrow()

    const state = deepFreeze({
      ...createEmptyPersistedTrainingState(),
      sessions: [sessionFixture("frozen")],
    })
    expect(() => toTrainingHistory(state)).not.toThrow()
    expect(() => migratePersistedTrainingState(state)).not.toThrow()
  })

  it("recovers safely from one corrupt stored record without inventing data", () => {
    const valid = sessionFixture("valid")
    const corrupt = sessionFixture("corrupt")
    corrupt.exercises[0].sets[0].reps = Number.NaN
    const raw = {
      ...createEmptyPersistedTrainingState(),
      sessions: [valid, corrupt],
    }
    const recovered = recoverPersistedTrainingState(raw)
    expect(recovered.issues.length).toBeGreaterThan(0)
    expect(recovered.state.sessions.map((session) => session.id)).toEqual(["valid"])
  })

  it("persists an active draft for reload and completes it in one draft-to-history transition", async () => {
    const program = fixtureProgram()
    useTrainingRecords.getState().saveProgram(program)
    useTrainingRecords
      .getState()
      .startPlannedWorkout(
        program.id,
        program.weeks[0].sessions[0].id,
        "2026-09-07T10:00:00.000Z"
      )
    let draft = useTrainingRecords.getState().data.activeWorkout!
    useTrainingRecords.getState().recordSet({
      exerciseEntryId: draft.exercises[0].id,
      setDraftId: draft.exercises[0].sets[0].id,
      observation: {
        reps: 10,
        resistance: {
          type: "external_load",
          kg: 77.5,
          basis: "total",
          stationId: "bench-a",
        },
        rir: 2,
        completed: true,
      },
    })
    draft = structuredClone(useTrainingRecords.getState().data.activeWorkout!)
    const stored = localStorage.getItem("gym-lib-training")
    expect(stored).toBeTruthy()

    useTrainingRecords.setState({
      data: createEmptyPersistedTrainingState(),
      persistenceIssues: [],
    })
    localStorage.setItem("gym-lib-training", stored!)
    await useTrainingRecords.persist.rehydrate()
    expect(useTrainingRecords.getState().data.activeWorkout).toEqual(draft)
    expect(useTrainingRecords.getState().data.sessions).toEqual([])

    const completedId = useTrainingRecords
      .getState()
      .completeWorkout("partial", "2026-09-07T10:20:00.000Z")
    expect(completedId).toBeTruthy()
    expect(useTrainingRecords.getState().data.activeWorkout).toBeNull()
    expect(useTrainingRecords.getState().data.sessions).toHaveLength(1)
    expect(useTrainingRecords.getState().data.sessions[0].exercises[0].sets[0]).toMatchObject({
      reps: 10,
      plannedSetId: program.weeks[0].sessions[0].exercises[0].workingSets[0].id,
    })
  })
})
