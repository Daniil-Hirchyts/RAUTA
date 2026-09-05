import { expect, it } from "vitest"
import {
  adaptLegacyWorkout,
  analyzeTrainingState,
  createExerciseIndex,
  DEFAULT_POLICY,
  generateTrainingProgram,
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
const index = createExerciseIndex(request().exercises)
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
