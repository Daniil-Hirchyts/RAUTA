import { describe, expect, it } from "vitest"
import {
  createExerciseIndex,
  DEFAULT_POLICY,
  effectiveSetCredit,
  calculateHistoryVolume,
  epleyEstimator,
  brzyckiEstimator,
  roundLoad,
  recommendProgression,
  observedRir,
} from "../index"
import { analyzeExercisePerformance } from "../analysis/strength"
import { analyzeTrainingState } from "../analysis/state"
import { request, set, history } from "./fixtures"
import { DAY_MS } from "../numeric"
import { prescribeExercise } from "../planning/prescribe"
import { preparation } from "../planning/generate"
import { estimateSessionDuration } from "../planning/duration"
const index = createExerciseIndex(request().exercises)
const bench = index.byId.get("0025")!
const progression = (h = history([[12, 12, 12]])) => ({
  exercise: bench,
  history: h,
  now: "2026-08-12T12:00:00.000Z",
  reps: { min: 8, max: 12 },
  rir: 2,
  requiredSets: 3,
  loadGrid: { incrementKg: 2.5 },
  loadContext: { stationId: "bench-A", basis: "total" as const },
  policy: DEFAULT_POLICY,
})
describe("effective volume accounting", () => {
  it("separates direct and indirect from editorial weights", () => {
    expect(effectiveSetCredit(bench, "chest", DEFAULT_POLICY).effective).toBe(1)
    expect(effectiveSetCredit(bench, "triceps", DEFAULT_POLICY).effective).toBe(
      0.5
    )
    expect(
      effectiveSetCredit(bench, "deltoids", DEFAULT_POLICY).effective
    ).toBe(0.5)
    expect(effectiveSetCredit(bench, "forearm", DEFAULT_POLICY).effective).toBe(
      0
    )
    expect(
      effectiveSetCredit(bench, "triceps", {
        ...DEFAULT_POLICY,
        indirectCredit: 0,
      }).effective
    ).toBe(0)
  })
  it("excludes incomplete sets, warmups, drops and counts single sides as half", () => {
    const h = history([[10]])
    h.sessions[0].exercises[0].sets = [
      set({ id: "a" }),
      set({ id: "b", setType: "warmup" }),
      set({ id: "c", completed: false }),
      set({ id: "d", side: "left" }),
      set({ id: "e", side: "right" }),
      set({ id: "f", setType: "drop" }),
    ]
    expect(
      calculateHistoryVolume(h, index, DEFAULT_POLICY, 0, Infinity).chest
        .effective
    ).toBe(2)
  })
  it("uses open rolling start and closed end, distinct from microcycle", () => {
    const h = history([[10]])
    const time = Date.parse(h.sessions[0].completedAt)
    expect(
      calculateHistoryVolume(h, index, DEFAULT_POLICY, time, time + DAY_MS)
        .chest.effective
    ).toBe(0)
    expect(
      calculateHistoryVolume(h, index, DEFAULT_POLICY, time, time, true).chest
        .effective
    ).toBe(1)
    expect(
      calculateHistoryVolume(h, index, DEFAULT_POLICY, time - DAY_MS, time)
        .chest.effective
    ).toBe(1)
  })
  it("reports decayed workload, no invented recovery; decays to half after 48h", () => {
    const h = history([[10]])
    const r = request({ history: h, now: h.sessions[0].completedAt })
    const s1 = analyzeTrainingState(r, index, [], DEFAULT_POLICY)
    const s2 = analyzeTrainingState(
      { ...r, now: new Date(Date.parse(r.now) + 2 * DAY_MS).toISOString() },
      index,
      [],
      DEFAULT_POLICY
    )
    expect(s1.muscles.chest.decayedWorkload).toBe(1)
    expect(s2.muscles.chest.decayedWorkload).toBeCloseTo(0.5)
    expect(s1.muscles.chest.effectiveSetsCurrentWeek).toBe(0)
    expect(s1.muscles.chest.rolling7DaySets).toBe(1)
  })
})
describe("strength and progression", () => {
  it("estimates only appropriate external-load sets", () => {
    expect(
      epleyEstimator.estimate(set({ reps: 5 }))?.estimated1RMKg
    ).toBeCloseTo(81.6667)
    expect(
      brzyckiEstimator.estimate(set({ reps: 5 }))?.estimated1RMKg
    ).toBeCloseTo(78.75)
    expect(
      epleyEstimator.estimate(set({ reps: 1, rir: 0 }))?.estimated1RMKg
    ).toBe(70)
    for (const s of [
      set(),
      set({ reps: 5, rir: undefined }),
      set({ reps: 5, resistance: { type: "bodyweight" } }),
      set({
        reps: 5,
        resistance: {
          type: "assistance",
          kg: 20,
          basis: "total",
          stationId: "A",
        },
      }),
      set({ reps: 5, completed: false }),
    ])
      expect(epleyEstimator.estimate(s)).toBeUndefined()
  })
  it("converts the RIR-based 0–10 RPE convention", () => {
    expect(observedRir({ rpe: 8 })).toBe(2)
    expect(observedRir({})).toBeUndefined()
  })
  it("rounds increment grids and nonuniform stacks in both directions", () => {
    expect(roundLoad(72.37, { incrementKg: 2.5 })).toBe(72.5)
    expect(roundLoad(72, { availableLoadsKg: [60, 70, 75] }, "up")).toBe(75)
    expect(roundLoad(72, { availableLoadsKg: [60, 70, 75] }, "down")).toBe(70)
    expect(
      roundLoad(1, { incrementKg: 2.5, minimumKg: 20 }, "down")
    ).toBeUndefined()
    expect(roundLoad(Infinity, { incrementKg: 2.5 })).toBeUndefined()
  })
  it("implements the specified 70kg → 72.5kg example", () => {
    const r = recommendProgression(progression())
    expect(r.action).toBe("increase_load")
    expect(r.resistance).toMatchObject({ kg: 72.5 })
  })
  it("holds incomplete or unknown-effort exposures", () => {
    expect(recommendProgression(progression(history([[12, 12]]))).action).toBe(
      "hold"
    )
    const h = history([[12, 12, 12]])
    h.sessions[0].exercises[0].sets[0].rir = undefined
    expect(recommendProgression(progression(h)).reasons).toContain(
      "missing_effort"
    )
  })
  it("does not reduce from one bad session; reduces after two", () => {
    expect(recommendProgression(progression(history([[5, 5, 5]]))).action).toBe(
      "hold"
    )
    expect(
      recommendProgression({
        ...progression(
          history([
            [5, 5, 5],
            [5, 5, 5],
          ])
        ),
        now: "2026-08-15T12:00:00.000Z",
      }).action
    ).toBe("decrease_load")
  })
  it("rejects station transfer and missing grids, routes excessive increments through coarse-grid progression, and rejects stale history", () => {
    expect(
      recommendProgression({
        ...progression(),
        loadContext: { stationId: "other", basis: "total" },
      }).action
    ).toBe("calibrate")
    expect(
      recommendProgression({ ...progression(), loadGrid: undefined }).action
    ).toBe("calibrate")
    const coarse = recommendProgression({
      ...progression(),
      loadGrid: { incrementKg: 70 },
    })
    expect(coarse.action).toBe("increase_reps")
    expect(coarse.reasons).toContain("coarse_load_grid")
    expect(
      recommendProgression({
        ...progression(),
        now: "2026-10-01T00:00:00.000Z",
      }).action
    ).toBe("calibrate")
  })
  it("reduces assistance to increase difficulty", () => {
    const h = history([[12, 12, 12]])
    h.sessions[0].exercises[0].sets.forEach((s) => {
      s.resistance = {
        type: "assistance",
        kg: 30,
        stationId: "bench-A",
        basis: "total",
      }
    })
    const p = progression(h)
    const r = recommendProgression({
      ...p,
      exercise: {
        ...bench,
        metadata: { ...bench.metadata, tracking: "assistance" },
      },
    })
    expect(r.action).toBe("reduce_assistance")
    expect(r.resistance).toMatchObject({ kg: 27.5 })
  })
  it("requires six comparable estimates to derive a trend", () => {
    expect(
      analyzeExercisePerformance(
        history([[5], [6]]),
        "0025",
        request().now,
        DEFAULT_POLICY
      ).trend
    ).toBe("insufficient_data")
    expect(
      analyzeExercisePerformance(
        history([[5], [5], [5], [8], [8], [8]]),
        "0025",
        request().now,
        DEFAULT_POLICY
      ).trend
    ).toBe("improving")
  })
})
it("duration includes warmups, setup, transitions, rests and both unilateral sides", () => {
  const input = preparation(request())
  const p = prescribeExercise(
    bench,
    3,
    "s",
    { total: 0, contributions: [] },
    input
  )
  const d = estimateSessionDuration({ exercises: [p] }, index, DEFAULT_POLICY)
  expect(d.totalSeconds).toBe(
    d.generalWarmupSeconds +
      d.specificWarmupSeconds +
      d.workingSetSeconds +
      d.restSeconds +
      d.transitionSeconds
  )
  expect(d.restSeconds).toBe(240)
  expect(d.specificWarmupSeconds).toBe(80)
  const row = index.byId.get("0292")!
  const q = prescribeExercise(
    row,
    3,
    "s",
    { total: 0, contributions: [] },
    input
  )
  expect(
    estimateSessionDuration({ exercises: [q] }, index, DEFAULT_POLICY)
      .workingSetSeconds
  ).toBe(3 * 12 * 4 * 2)
})
