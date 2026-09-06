import { expect, it } from "vitest"
import {
  adaptLegacyWorkout,
  analyzeTrainingState,
  createExerciseIndex,
  DEFAULT_POLICY,
  evaluateTrainingProgram,
  generateTrainingProgram,
  plannerSupportsExercise,
  plannerSupportsTracking,
  recommendProgression,
  validateGenerationRequest,
  validateMetadata,
  validateTrainingProgram,
} from "../index"
import { request, history, set } from "./fixtures"
import { prescribeExercise } from "../planning/prescribe"
import { preparation } from "../planning/generate"
import { orderExercises } from "../scoring/scores"
import { adaptTrainingProgram } from "../planning/adapt"
import { confidenceAtLeast } from "../numeric"
import { calculateSessionVolume } from "../analysis/volume"
const index = createExerciseIndex(request().exercises)
it("keeps automatic planner capabilities aligned with supported tracking semantics", () => {
  for (const tracking of [
    "external_load",
    "assistance",
    "bodyweight",
    "band_resistance",
  ] as const)
    expect(plannerSupportsTracking(tracking)).toBe(true)
  for (const tracking of [
    "repetition_only",
    "timed",
    "distance",
    "unknown",
  ] as const)
    expect(plannerSupportsTracking(tracking)).toBe(false)

  const base = index.byId.get("0025")!.metadata
  for (const tracking of ["repetition_only", "timed", "distance"] as const) {
    const metadata = {
      ...structuredClone(base),
      tracking,
      automaticProgramming: "allowed" as const,
    }
    expect(plannerSupportsExercise(metadata)).toBe(false)
    expect(validateMetadata(metadata, index.byId.get("0025")!.exercise)).toHaveLength(
      1
    )
  }
})
it("prescribes band resistance explicitly without inventing kilograms", () => {
  const r = request()
  const input = preparation(r)
  const band = index.byId.get("3236")!
  expect(band.metadata.tracking).toBe("band_resistance")
  expect(plannerSupportsExercise(band.metadata)).toBe(true)
  const prescribed = prescribeExercise(
    band,
    3,
    "band-test",
    { total: 0, contributions: [] },
    input
  )
  expect(prescribed.workingSets[0].resistance).toEqual({
    type: "band_resistance",
  })
  expect(prescribed.workingSets[0].loadAcquisition).toBe("band_resistance")
  expect(prescribed.warmupSets).toEqual([])
})
it("old ID-only completion never fabricates sets, load or effective volume", () => {
  const session = adaptLegacyWorkout({
    id: "old",
    completion: {
      startedAt: "2026-09-01T10:00:00.000Z",
      completedAt: "2026-09-01T10:30:00.000Z",
      durationMs: 1_800_000,
      completedExerciseIds: ["0025"],
    },
  })!
  expect(session.exercises[0].sets).toEqual([])
  const state = analyzeTrainingState(
    request({ history: { sessions: [session], coverage: "unknown" } })
  )
  expect(state.muscles.chest.rolling7DaySets).toBe(0)
  expect(state.exercises["0025"].recentEstimated1RM).toBeUndefined()
})
it("bodyweight top-range performance changes the prescribed rep range without kg", () => {
  const h = history([[20, 20, 20]], "0662")
  h.sessions[0].exercises[0].sets.forEach((s) => {
    s.resistance = { type: "bodyweight" }
  })
  const r = request({ history: h, now: "2026-08-12T12:00:00.000Z" })
  const input = preparation(r)
  const p = prescribeExercise(
    index.byId.get("0662")!,
    3,
    "s",
    { total: 0, contributions: [] },
    input
  )
  expect(p.progression.action).toBe("increase_reps")
  expect(p.workingSets[0].targetReps).toEqual({ min: 11, max: 21 })
  expect(p.workingSets[0].resistance).toEqual({ type: "bodyweight" })
})
it("large downward grid steps do not make aggressive reductions", () => {
  const h = history([
    [2, 2, 2],
    [2, 2, 2],
  ])
  const p = recommendProgression({
    exercise: index.byId.get("0025")!,
    history: h,
    now: "2026-08-15T12:00:00.000Z",
    reps: { min: 8, max: 12 },
    rir: 2,
    requiredSets: 3,
    loadGrid: { incrementKg: 70 },
    loadContext: { stationId: "bench-A", basis: "total" },
    policy: DEFAULT_POLICY,
  })
  expect(p.action).toBe("hold")
  expect(p.reasons).toContain("increment_too_large")
})
it("coarse load grids progress after repeated success at the extended rep ceiling", () => {
  const h = history([
    [16, 16, 16],
    [16, 16, 16],
  ])
  const p = recommendProgression({
    exercise: index.byId.get("0025")!,
    history: h,
    now: "2026-08-15T12:00:00.000Z",
    reps: { min: 8, max: 12 },
    rir: 2,
    requiredSets: 3,
    loadGrid: { availableLoadsKg: [70, 90] },
    loadContext: { stationId: "bench-A", basis: "total" },
    policy: DEFAULT_POLICY,
  })
  expect(p).toMatchObject({
    action: "increase_load",
    resistance: { type: "external_load", kg: 90 },
    confidence: "medium",
  })
  expect(p.reasons).toContain("coarse_load_grid")
})
it("coarse grids above normal load limits extend reps, then either advance safely or return a structured alternative", () => {
  const cases = [
    { current: 10, next: 12.5, eventual: "increase_load" },
    { current: 5, next: 7.5, eventual: "coarse_grid_progression" },
    { current: 2.5, next: 5, eventual: "coarse_grid_progression" },
  ] as const
  for (const { current, next, eventual } of cases) {
    const first = history([[12, 12, 12]])
    first.sessions[0].exercises[0].sets.forEach((s) => {
      s.resistance = {
        type: "external_load",
        kg: current,
        stationId: "bench-A",
        basis: "total",
      }
    })
    const extending = recommendProgression({
      exercise: index.byId.get("0025")!,
      history: first,
      now: "2026-08-12T12:00:00.000Z",
      reps: { min: 8, max: 12 },
      rir: 2,
      requiredSets: 3,
      loadGrid: { availableLoadsKg: [current, next] },
      loadContext: { stationId: "bench-A", basis: "total" },
      policy: DEFAULT_POLICY,
    })
    expect(extending.action, `${current}->${next}`).toBe("increase_reps")
    expect(extending.targetReps.max, `${current}->${next}`).toBeGreaterThan(12)

    const ceiling = history([
      [16, 16, 16],
      [16, 16, 16],
    ])
    ceiling.sessions.forEach((session) =>
      session.exercises[0].sets.forEach((s) => {
        s.resistance = {
          type: "external_load",
          kg: current,
          stationId: "bench-A",
          basis: "total",
        }
      })
    )
    const outcome = recommendProgression({
      exercise: index.byId.get("0025")!,
      history: ceiling,
      now: "2026-08-15T12:00:00.000Z",
      reps: { min: 8, max: 12 },
      rir: 2,
      requiredSets: 3,
      loadGrid: { availableLoadsKg: [current, next] },
      loadContext: { stationId: "bench-A", basis: "total" },
      policy: DEFAULT_POLICY,
    })
    expect(outcome.action, `${current}->${next}`).toBe(eventual)
    if (eventual === "increase_load") {
      expect(outcome.resistance).toMatchObject({ kg: next })
      expect(outcome.reasons).toContain("coarse_load_grid")
    } else {
      expect(outcome.resistance).toMatchObject({ kg: current })
      expect(outcome.reasons).toContain(
        "coarse_grid_requires_alternative_progression"
      )
      expect(outcome.suggestedStrategies).toEqual([
        "continue_repetition_progression",
        "use_smaller_increment_if_available",
        "use_different_variation",
      ])
    }
  }
})
it("coarse assistance grids preserve the inverse difficulty direction and never make an unsafe giant reduction", () => {
  const h = history([
    [16, 16, 16],
    [16, 16, 16],
  ])
  h.sessions.forEach((session) =>
    session.exercises[0].sets.forEach((s) => {
      s.resistance = {
        type: "assistance",
        kg: 10,
        stationId: "assist-A",
        basis: "total",
      }
    })
  )
  const outcome = recommendProgression({
    exercise: {
      ...index.byId.get("0025")!,
      metadata: { ...index.byId.get("0025")!.metadata, tracking: "assistance" },
    },
    history: h,
    now: "2026-08-15T12:00:00.000Z",
    reps: { min: 8, max: 12 },
    rir: 2,
    requiredSets: 3,
    loadGrid: { availableLoadsKg: [5, 10] },
    loadContext: { stationId: "assist-A", basis: "total" },
    policy: DEFAULT_POLICY,
  })
  expect(outcome.action).toBe("coarse_grid_progression")
  expect(outcome.resistance).toMatchObject({ type: "assistance", kg: 10 })
  expect(outcome.reasons).toContain(
    "coarse_grid_requires_alternative_progression"
  )
})
it("confidence ordering treats high as satisfying at-least-medium requirements", () => {
  expect(confidenceAtLeast("high", "medium")).toBe(true)
  expect(confidenceAtLeast("medium", "medium")).toBe(true)
  expect(confidenceAtLeast("low", "medium")).toBe(false)
})
it("priority isolation can precede non-priority compounds", () => {
  const r = request()
  r.preferences.priorityMuscles = [
    { muscleId: "biceps", level: "specialization" },
  ]
  const input = preparation(r)
  const curl = [...index.byId.values()].find(
    (e) =>
      e.metadata.mechanics === "isolation" &&
      e.metadata.setRoles.some(
        (r) => r.role === "direct" && r.muscleId === "biceps"
      )
  )!
  const bench = prescribeExercise(
    index.byId.get("0025")!,
    3,
    "s",
    { total: 0, contributions: [] },
    input
  )
  const accessory = prescribeExercise(
    curl,
    3,
    "s",
    { total: 0, contributions: [] },
    input
  )
  // Specialization importance 1.5 ties compounds at 3; high enough custom priority can override.
  input.targets.find((t) => t.muscleId === "biceps")!.importance = 2
  expect(orderExercises([bench, accessory], input)[0].exerciseId).toBe(
    curl.exercise.id
  )
})
it("malformed metadata roles and cyclic requests return validation issues", () => {
  const meta = structuredClone(index.byId.get("0025")!.metadata)
  Object.assign(meta, { setRoles: [null] })
  expect(validateMetadata(meta, index.byId.get("0025")!.exercise)).toHaveLength(
    1
  )
  const r = request()
  Object.assign(r, { cycle: r })
  expect(generateTrainingProgram(r).status).toBe("invalid")
})
it("rejects future sessions, duplicate observations and contradictory effort", () => {
  const r = request({ history: history([[8]]) })
  r.history.sessions[0].completedAt = "2027-01-01T00:00:00.000Z"
  expect(validateGenerationRequest(r).length).toBeGreaterThan(0)
  r.history = history([[8]])
  r.history.sessions.push(r.history.sessions[0])
  expect(validateGenerationRequest(r).length).toBeGreaterThan(0)
  r.history = history([[8]])
  r.history.sessions[0].exercises[0].sets[0].rpe = 2
  expect(validateGenerationRequest(r).length).toBeGreaterThan(0)
})
it("independent validation includes actual work in remaining-week volume ceilings", () => {
  const r = request()
  r.policy = {
    ...structuredClone(DEFAULT_POLICY),
    beamWidth: 1,
    candidateLimit: 3,
  }
  const result = generateTrainingProgram(r)
  if (!("program" in result)) throw new Error("fixture infeasible")
  const next = request({
    policy: r.policy,
    now: "2026-09-08T12:00:00.000Z",
    schedule: { ...r.schedule, days: [2, 4] },
  })
  next.preferences.maxWeeklyWorkingSets = 100
  next.history = {
    coverage: "complete",
    coverageStart: "2026-08-01T00:00:00.000Z",
    sessions: [
      {
        id: "actual",
        startedAt: "2026-09-07T10:00:00.000Z",
        completedAt: "2026-09-07T10:30:00.000Z",
        status: "partial",
        exercises: [
          { exerciseId: "0025", sets: [set({ id: "a" }), set({ id: "b" })] },
        ],
      },
    ],
  }
  const adapted = adaptTrainingProgram({
    previousProgram: result.program,
    request: next,
    mode: "remaining_week",
  })
  expect("program" in adapted).toBe(true)
  if ("program" in adapted) {
    expect(validateTrainingProgram(adapted.program, next, index).valid).toBe(
      true
    )
    const planned = adapted.program.weeks[0].sessions.reduce(
      (n, s) => n + s.exercises.reduce((n, e) => n + e.workingSets.length, 0),
      0
    )
    next.preferences.maxWeeklyWorkingSets = planned + 1
    expect(
      validateTrainingProgram(adapted.program, next, index).issues.some(
        (i) => i.code === "VOLUME_LIMIT"
      )
    ).toBe(true)
  }
}, 30_000)
it("remaining-week generation keeps the original 20-set cap authoritative while optimizing against the residual 12-set budget", () => {
  const baseRequest = request()
  const previous = generateTrainingProgram(baseRequest)
  if (!("program" in previous)) throw new Error("fixture infeasible")
  const next = request({
    now: "2026-09-08T12:00:00.000Z",
    schedule: { ...baseRequest.schedule, days: [2, 4] },
  })
  next.preferences.maxWeeklyWorkingSets = 20
  next.history = {
    coverage: "complete",
    coverageStart: "2026-08-01T00:00:00.000Z",
    sessions: [
      {
        id: "eight-completed",
        startedAt: "2026-09-07T10:00:00.000Z",
        completedAt: "2026-09-07T11:00:00.000Z",
        status: "completed",
        exercises: [
          {
            exerciseId: "0025",
            sets: Array.from({ length: 8 }, (_, i) =>
              set({ id: `completed-${i}` })
            ),
          },
        ],
      },
    ],
  }
  const adapted = adaptTrainingProgram({
    previousProgram: previous.program,
    request: next,
    mode: "remaining_week",
  })
  expect("program" in adapted).toBe(true)
  if ("program" in adapted) {
    const future = adapted.program.weeks[0].sessions.reduce(
      (n, session) =>
        n +
        session.exercises.reduce((m, exercise) => m + exercise.workingSets.length, 0),
      0
    )
    expect(future).toBeLessThanOrEqual(12)
    expect(
      validateTrainingProgram(adapted.program, next, index, {
        sourceProgram: previous.program,
      }).valid
    ).toBe(true)
  }
}, 30_000)
it("remaining-week muscle bounds optimize against the residual maximum and validate completed plus future volume against the original bound", () => {
  const baseRequest = request()
  const previous = generateTrainingProgram(baseRequest)
  if (!("program" in previous)) throw new Error("fixture infeasible")
  const next = request({
    now: "2026-09-08T12:00:00.000Z",
    schedule: { ...baseRequest.schedule, days: [2, 4] },
  })
  next.preferences.maxWeeklyWorkingSets = 20
  next.preferences.muscleVolumeBounds = [{ muscleId: "chest", maximum: 14 }]
  next.history = {
    coverage: "complete",
    coverageStart: "2026-08-01T00:00:00.000Z",
    sessions: [
      {
        id: "eight-chest",
        startedAt: "2026-09-07T10:00:00.000Z",
        completedAt: "2026-09-07T11:00:00.000Z",
        status: "completed",
        exercises: [
          {
            exerciseId: "0025",
            sets: Array.from({ length: 8 }, (_, i) =>
              set({ id: `chest-${i}` })
            ),
          },
        ],
      },
    ],
  }
  const adapted = adaptTrainingProgram({
    previousProgram: previous.program,
    request: next,
    mode: "remaining_week",
  })
  expect("program" in adapted).toBe(true)
  if ("program" in adapted) {
    const futureChest = adapted.program.weeks[0].sessions.reduce(
      (sum, session) =>
        sum + calculateSessionVolume(session, index, adapted.program.policy).chest.effective,
      0
    )
    // Eight completed direct chest sets leave a six-set optimization ceiling.
    expect(futureChest).toBeLessThanOrEqual(6)
    const valid = validateTrainingProgram(adapted.program, next, index, {
      sourceProgram: previous.program,
    })
    expect(valid.valid).toBe(true)

    // The independent validator must use the original weekly bound, not the
    // residual optimizer bound. Put the boundary exactly at completed + future.
    const exactBoundary = structuredClone(next)
    exactBoundary.preferences.muscleVolumeBounds = [
      { muscleId: "chest", maximum: 8 + futureChest },
    ]
    expect(
      validateTrainingProgram(adapted.program, exactBoundary, index, {
        sourceProgram: previous.program,
      }).issues.some((issue) => issue.code === "VOLUME_LIMIT")
    ).toBe(false)

    const tighter = structuredClone(next)
    tighter.preferences.muscleVolumeBounds = [
      { muscleId: "chest", maximum: 8 + futureChest - 0.5 },
    ]
    expect(
      validateTrainingProgram(adapted.program, tighter, index, {
        sourceProgram: previous.program,
      }).issues.some((issue) => issue.code === "VOLUME_LIMIT")
    ).toBe(true)
  }
}, 30_000)
it("policy is immutable and all important divisors reject zero", () => {
  expect(Object.isFrozen(DEFAULT_POLICY)).toBe(true)
  expect(Object.isFrozen(DEFAULT_POLICY.goals.hypertrophy)).toBe(true)
  for (const key of [
    "workloadHalfLifeHours",
    "secondsPerRep",
    "sessionMuscleGuideline",
    "meaningfulExposureSets",
  ]) {
    const r = request({
      policy: { ...structuredClone(DEFAULT_POLICY), [key]: 0 },
    })
    expect(generateTrainingProgram(r).status).toBe("invalid")
  }
})
it("adaptation requires the exact source policy fingerprint", () => {
  const baseRequest = request({
    policy: {
      ...structuredClone(DEFAULT_POLICY),
      beamWidth: 1,
      candidateLimit: 3,
    },
  })
  const generated = generateTrainingProgram(baseRequest)
  if (!("program" in generated)) throw new Error("fixture infeasible")
  const next = request({
    policy: structuredClone(generated.program.policy),
    now: "2026-09-13T12:00:00.000Z",
    schedule: {
      ...baseRequest.schedule,
      weekStart: "2026-09-14T00:00:00.000Z",
      durationWeeks: 1,
    },
  })
  expect(
    adaptTrainingProgram({
      previousProgram: generated.program,
      request: next,
      mode: "next_week",
    }).status
  ).toMatch(/success|partial/)

  next.policy = {
    ...structuredClone(generated.program.policy),
    indirectCredit: generated.program.policy.indirectCredit + 0.01,
  }
  expect(
    adaptTrainingProgram({
      previousProgram: generated.program,
      request: next,
      mode: "next_week",
    }).status
  ).toBe("invalid")

  next.policy = {
    ...structuredClone(generated.program.policy),
    version: "different-version",
  }
  expect(
    adaptTrainingProgram({
      previousProgram: generated.program,
      request: next,
      mode: "next_week",
    }).status
  ).toBe("invalid")
}, 30_000)
it("stored-program evaluation uses the embedded policy and rejects explicit mismatches", () => {
  const generationRequest = request({
    policy: {
      ...structuredClone(DEFAULT_POLICY),
      beamWidth: 1,
      candidateLimit: 3,
      indirectCredit: 0.37,
    },
  })
  const generated = generateTrainingProgram(generationRequest)
  if (!("program" in generated)) throw new Error("fixture infeasible")

  const withoutPolicy = request()
  expect(evaluateTrainingProgram(generated.program, withoutPolicy).valid).toBe(true)

  const mismatch = request({
    policy: {
      ...structuredClone(generated.program.policy),
      indirectCredit: generated.program.policy.indirectCredit + 0.01,
    },
  })
  const evaluated = evaluateTrainingProgram(generated.program, mismatch)
  expect(evaluated.valid).toBe(false)
  expect(evaluated.issues).toContainEqual({
    code: "INVALID_PROGRAM",
    path: "program.policy",
  })
}, 30_000)
it("specific strength histories select and prescribe the actual squat, bench and deadlift", () => {
  const r = request()
  r.preferences.goal = "strength"
  r.preferences.strengthExerciseIds = ["0025", "0032", "0043"]
  r.schedule.days = [0, 1, 3, 4]
  const h = history([[6, 6, 6]])
  h.sessions[0].startedAt = "2026-09-04T10:00:00.000Z"
  h.sessions[0].completedAt = "2026-09-04T11:00:00.000Z"
  h.sessions[0].exercises = r.preferences.strengthExerciseIds.map(
    (exerciseId) => ({
      exerciseId,
      sets: [0, 1, 2].map((i) =>
        set({
          id: exerciseId + i,
          reps: 6,
          resistance: {
            type: "external_load",
            kg: 70,
            stationId: exerciseId,
            basis: "total",
          },
        })
      ),
    })
  )
  r.history = h
  r.preferences.loadGrids = Object.fromEntries(
    r.preferences.strengthExerciseIds.map((id) => [id, { incrementKg: 2.5 }])
  )
  r.preferences.loadContexts = Object.fromEntries(
    r.preferences.strengthExerciseIds.map((id) => [
      id,
      { stationId: id, basis: "total" as const },
    ])
  )
  const result = generateTrainingProgram(r)
  expect("program" in result).toBe(true)
  if ("program" in result) {
    const selected = result.program.weeks[0].sessions.flatMap(
      (s) => s.exercises
    )
    for (const id of r.preferences.strengthExerciseIds) {
      const lift = selected.find((e) => e.exerciseId === id)
      expect(lift, id).toBeDefined()
      expect(lift?.workingSets[0].resistance).toMatchObject({ kg: 72.5 })
      expect(lift?.workingSets[0].targetReps).toEqual({ min: 3, max: 6 })
    }
  }
}, 30_000)
it("reactive reduced volume requires persistent decline and low readiness", () => {
  const r = request()
  r.policy = {
    ...structuredClone(DEFAULT_POLICY),
    beamWidth: 1,
    candidateLimit: 3,
  }
  const base = generateTrainingProgram(r)
  if (!("program" in base)) throw new Error("fixture infeasible")
  const h = history([
    [10, 10, 10],
    [10, 10, 10],
    [10, 10, 10],
    [5, 5, 5],
    [5, 5, 5],
    [5, 5, 5],
  ])
  for (const s of h.sessions) {
    s.startedAt = new Date(
      Date.parse(s.startedAt) + 11 * 86400000
    ).toISOString()
    s.completedAt = new Date(
      Date.parse(s.completedAt) + 11 * 86400000
    ).toISOString()
    s.exercises.push({
      exerciseId: "0032",
      sets: s.exercises[0].sets.map((set) => ({
        ...set,
        id: set.id + "/deadlift",
      })),
    })
  }
  const next = request({
    policy: r.policy,
    history: h,
    now: "2026-09-13T12:00:00.000Z",
    schedule: { ...r.schedule, weekStart: "2026-09-14T00:00:00.000Z" },
    readiness: { perceivedReadiness: "low" },
  })
  const result = adaptTrainingProgram({
    previousProgram: base.program,
    request: next,
    mode: "next_week",
  })
  expect("program" in result).toBe(true)
  if ("program" in result)
    expect(result.program.weeks[0].phase).toBe("reduced_volume")
}, 30_000)
it("malformed source programs cannot crash adaptation", () => {
  for (const value of [
    null,
    {},
    { weeks: [null] },
    { weeks: [{ sessions: [null] }], policy: DEFAULT_POLICY },
  ]) {
    const input = {
      previousProgram: value,
      request: request(),
      mode: "remaining_week",
    }
    expect(
      adaptTrainingProgram(
        input as unknown as Parameters<typeof adaptTrainingProgram>[0]
      ).status
    ).toBe("invalid")
  }
})
it("separate sides share one planned reference, earn paired volume and require both sides for progression", () => {
  const h = history([[12, 12, 12]])
  h.sessions[0].exercises[0].sets = [0, 1, 2].flatMap((i) => [
    set({ id: `left-${i}`, plannedSetId: `planned-${i}`, side: "left" }),
    set({ id: `right-${i}`, plannedSetId: `planned-${i}`, side: "right" }),
  ])
  const r = request({ history: h, now: "2026-08-12T12:00:00.000Z" })
  expect(validateGenerationRequest(r)).toEqual([])
  expect(analyzeTrainingState(r, index).muscles.chest.rolling7DaySets).toBe(3)
  const input = {
    exercise: index.byId.get("0025")!,
    history: h,
    now: r.now,
    reps: { min: 8, max: 12 },
    rir: 2,
    requiredSets: 3,
    loadGrid: { incrementKg: 2.5 },
    loadContext: { stationId: "bench-A", basis: "total" as const },
    policy: DEFAULT_POLICY,
  }
  expect(recommendProgression(input).action).toBe("increase_load")
  h.sessions[0].exercises[0].sets = h.sessions[0].exercises[0].sets.filter(
    (s) => s.side === "left"
  )
  expect(recommendProgression(input).action).toBe("hold")
  expect(analyzeTrainingState(r, index).muscles.chest.rolling7DaySets).toBe(1.5)
  h.sessions[0].exercises[0].sets.push(
    set({ id: "repeated-left", plannedSetId: "planned-0", side: "left" })
  )
  expect(
    validateGenerationRequest(r).some((i) => i.path?.endsWith("plannedSetId"))
  ).toBe(true)
})
it("added weight on bodyweight exercises is not treated as total resistance for e1RM", () => {
  const h = history([[5, 5, 5]], "0662")
  const r = request({ history: h, now: "2026-08-12T12:00:00.000Z" })
  const state = analyzeTrainingState(r, index)
  expect(state.exercises["0662"].recentEstimated1RM).toBeUndefined()
  expect(state.exercises["0662"].recentResistance).toMatchObject({
    type: "external_load",
    kg: 70,
  })
})
