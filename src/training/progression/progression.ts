import type {
  LoadGrid,
  ProgressionInput,
  ProgressionRecommendation,
  ProgressionStrategy,
  ResistanceValue,
} from "../domain/types"
import { DAY_MS, round } from "../numeric"
import { completedPairs } from "../analysis/volume"
import { exerciseExposures, observedRir } from "../analysis/strength"

export function roundLoad(
  load: number,
  grid: LoadGrid,
  direction: "nearest" | "up" | "down" = "nearest"
): number | undefined {
  if (!Number.isFinite(load) || load < 0) return undefined
  if ("availableLoadsKg" in grid) {
    const loads = [...new Set(grid.availableLoadsKg)]
      .filter((n) => Number.isFinite(n) && n >= 0)
      .sort((a, b) => a - b)
    const allowed = loads.filter((n) =>
      direction === "up"
        ? n >= load - 1e-6
        : direction === "down"
          ? n <= load + 1e-6
          : true
    )
    return allowed.sort(
      (a, b) => Math.abs(a - load) - Math.abs(b - load) || a - b
    )[0]
  }
  if (!Number.isFinite(grid.incrementKg) || grid.incrementKg <= 0)
    return undefined
  const minimum = grid.minimumKg ?? 0
  const steps = (load - minimum) / grid.incrementKg
  const value = round(
    minimum +
      (direction === "up"
        ? Math.ceil(steps - 1e-8)
        : direction === "down"
          ? Math.floor(steps + 1e-8)
          : Math.round(steps)) *
        grid.incrementKg
  )
  return value < minimum || value > (grid.maximumKg ?? Infinity)
    ? undefined
    : value
}
export function isAchievableLoad(load: number, grid: LoadGrid): boolean {
  const rounded = roundLoad(load, grid)
  return rounded !== undefined && Math.abs(rounded - load) < 1e-6
}
function adjacentLoad(load: number, grid: LoadGrid, up: boolean) {
  if ("availableLoadsKg" in grid)
    return [...grid.availableLoadsKg]
      .sort((a, b) => (up ? a - b : b - a))
      .find((n) => (up ? n > load + 1e-6 : n < load - 1e-6))
  return roundLoad(
    load + (up ? grid.incrementKg : -grid.incrementKg),
    grid,
    up ? "up" : "down"
  )
}
function recommendation(
  i: ProgressionInput,
  patch: Partial<ProgressionRecommendation>
): ProgressionRecommendation {
  return {
    action: "calibrate",
    resistance:
      i.exercise.metadata.tracking === "bodyweight"
        ? { type: "bodyweight" }
        : { type: "unknown" },
    targetReps: { ...i.reps },
    confidence: "none",
    reasons: ["no_history"],
    ...patch,
  }
}
function recentPerformance(i: ProgressionInput) {
  const exposures = exerciseExposures(i.history, i.exercise.exercise.id, i.now)
  return { exposures, latest: exposures.at(-1) }
}
export const repProgression: ProgressionStrategy = {
  recommend(i) {
    const { latest } = recentPerformance(i)
    if (!latest) return recommendation(i, {})
    if (
      Date.parse(i.now) - Date.parse(latest.session.completedAt) >
      i.policy.staleAfterDays * DAY_MS
    )
      return recommendation(i, { reasons: ["stale_history"] })
    const top =
      completedPairs(latest.sets) >= i.requiredSets &&
      latest.sets.every(
        (s) =>
          s.reps >= i.reps.max &&
          (observedRir(s) ?? -1) >= i.rir - i.policy.rirTolerance
      )
    const progress = top && i.reps.max < i.policy.maxBodyweightReps
    return recommendation(i, {
      action: progress ? "increase_reps" : "hold",
      targetReps: progress
        ? { min: i.reps.min + 1, max: i.reps.max + 1 }
        : { ...i.reps },
      confidence: "low",
      reasons: [top ? "top_of_range" : "within_range"],
    })
  },
}
export const doubleProgression: ProgressionStrategy = {
  recommend(i) {
    const { exposures, latest } = recentPerformance(i)
    if (!latest) return recommendation(i, {})
    if (
      Date.parse(i.now) - Date.parse(latest.session.completedAt) >
      i.policy.staleAfterDays * DAY_MS
    )
      return recommendation(i, { reasons: ["stale_history"] })
    const load = latest.sets[0].resistance
    if (
      load.type !== i.exercise.metadata.tracking ||
      (load.type !== "external_load" && load.type !== "assistance")
    )
      return recommendation(i, { reasons: ["context_changed"] })
    if (
      !i.loadContext ||
      i.loadContext.stationId !== load.stationId ||
      i.loadContext.basis !== load.basis
    )
      return recommendation(i, { reasons: ["context_changed"] })
    if (!i.loadGrid || !isAchievableLoad(load.kg, i.loadGrid))
      return recommendation(i, { reasons: ["grid_unavailable"] })
    const same = (r: ResistanceValue) =>
      r.type === load.type &&
      (r.type === "external_load" || r.type === "assistance") &&
      r.stationId === load.stationId &&
      r.basis === load.basis &&
      r.kg === load.kg
    const hold = (reason: ProgressionRecommendation["reasons"][number]) =>
      recommendation(i, {
        action: "hold",
        resistance: { ...load },
        confidence: "low",
        reasons: [reason],
      })
    if (
      completedPairs(latest.sets) < i.requiredSets ||
      latest.allSets.some((s) => !s.completed && s.setType === "working") ||
      !latest.sets.every((s) => same(s.resistance))
    )
      return hold("incomplete_sets")
    if (latest.sets.some((s) => observedRir(s) === undefined))
      return hold("missing_effort")
    const top = latest.sets.every(
      (s) =>
        s.reps >= i.reps.max && observedRir(s)! >= i.rir - i.policy.rirTolerance
    )
    const repeatedLow =
      exposures.slice(-2).length === 2 &&
      exposures
        .slice(-2)
        .every(
          (x) =>
            Date.parse(i.now) - Date.parse(x.session.completedAt) <=
              i.policy.staleAfterDays * DAY_MS &&
            completedPairs(x.sets) >= i.requiredSets &&
            x.sets.every((s) => same(s.resistance)) &&
            x.sets.filter(
              (s) => s.reps < i.reps.min && (observedRir(s) ?? 10) <= i.rir
            ).length >
              x.sets.length / 2
        )
    if (!top && !repeatedLow) return hold("within_range")
    const assistance = load.type === "assistance"
    const next = adjacentLoad(
      load.kg,
      i.loadGrid,
      top ? !assistance : assistance
    )
    if (next === undefined) return hold("grid_unavailable")
    if (
      Math.abs(next - load.kg) >
      Math.max(load.kg, 1) *
        (top ? i.policy.maxLoadIncreaseFraction : i.policy.reductionFraction)
    )
      return hold("increment_too_large")
    return recommendation(i, {
      action: top
        ? assistance
          ? "reduce_assistance"
          : "increase_load"
        : assistance
          ? "increase_assistance"
          : "decrease_load",
      resistance: { ...load, kg: next },
      confidence: "medium",
      reasons: [top ? "top_of_range" : "repeated_underperformance"],
    })
  },
}
export function recommendProgression(
  input: ProgressionInput,
  strategy?: ProgressionStrategy
): ProgressionRecommendation {
  return (
    strategy ??
    (input.exercise.metadata.tracking === "external_load" ||
    input.exercise.metadata.tracking === "assistance"
      ? doubleProgression
      : repProgression)
  ).recommend(input)
}
