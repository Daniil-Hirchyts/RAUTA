import type {
  CompletedSet,
  ExercisePerformanceState,
  StrengthEstimator,
  TrainingHistory,
  TrainingPolicy,
} from "../domain/types"
import { compareIds, DAY_MS, median } from "../numeric"
import { isWorkingSet } from "./volume"
export function observedRir(
  set: Pick<CompletedSet, "rir" | "rpe">
): number | undefined {
  return set.rir ?? (set.rpe === undefined ? undefined : 10 - set.rpe)
}
function makeEstimator(name: "epley" | "brzycki"): StrengthEstimator {
  return {
    name,
    estimate(set) {
      const rir = observedRir(set)
      if (
        !isWorkingSet(set) ||
        set.side !== "both" ||
        set.resistance.type !== "external_load" ||
        !Number.isFinite(set.resistance.kg) ||
        set.resistance.kg <= 0 ||
        !Number.isInteger(set.reps) ||
        set.reps < 1 ||
        set.reps > 10 ||
        rir === undefined ||
        rir < 0 ||
        rir > 2
      )
        return undefined
      const actual = set.reps === 1 && rir === 0
      return {
        estimated1RMKg: actual
          ? set.resistance.kg
          : name === "epley"
            ? set.resistance.kg * (1 + set.reps / 30)
            : (set.resistance.kg * 36) / (37 - set.reps),
        confidence: actual ? "high" : "low",
        estimator: name,
        source: actual ? "actual_1rm" : "estimated_from_set",
      }
    },
  }
}
export const epleyEstimator = makeEstimator("epley")
export const brzyckiEstimator = makeEstimator("brzycki")
export function exerciseExposures(
  history: TrainingHistory,
  exerciseId: string,
  now: string
) {
  return history.sessions
    .filter((s) => Date.parse(s.completedAt) <= Date.parse(now))
    .flatMap((s) => {
      const e = s.exercises.find((e) => e.exerciseId === exerciseId)
      return e && e.sets.some(isWorkingSet)
        ? [{ session: s, sets: e.sets.filter(isWorkingSet), allSets: e.sets }]
        : []
    })
    .sort(
      (a, b) =>
        Date.parse(a.session.completedAt) - Date.parse(b.session.completedAt) ||
        compareIds(a.session.id, b.session.id)
    )
}
export function analyzeExercisePerformance(
  history: TrainingHistory,
  exerciseId: string,
  now: string,
  policy: TrainingPolicy,
  allowStrengthEstimates = true
): ExercisePerformanceState {
  const exposures = exerciseExposures(history, exerciseId, now)
  const latest = exposures.at(-1)
  const latestLoad = latest?.sets.at(-1)?.resistance
  const estimates = exposures.flatMap((x) => {
    if (!allowStrengthEstimates) return []
    if (
      Date.parse(now) - Date.parse(x.session.completedAt) >
      policy.staleAfterDays * DAY_MS
    )
      return []
    const values = x.sets
      .filter(
        (s) =>
          s.resistance.type === "external_load" &&
          latestLoad?.type === "external_load" &&
          s.resistance.stationId === latestLoad.stationId &&
          s.resistance.basis === latestLoad.basis
      )
      .flatMap((s) => {
        const e = epleyEstimator.estimate(s)
        return e ? [e.estimated1RMKg] : []
      })
    return values.length ? [median(values)!] : []
  })
  const recent = median(estimates.slice(-3))
  const previous =
    estimates.length >= 6 ? median(estimates.slice(-6, -3)) : undefined
  const relativeChange =
    previous && recent ? (recent - previous) / previous : undefined
  return {
    exerciseId,
    exposureCount: exposures.length,
    lastPerformedAt: latest?.session.completedAt,
    bestEstimated1RM: estimates.length ? Math.max(...estimates) : undefined,
    recentEstimated1RM: recent,
    recentResistance: latestLoad ? { ...latestLoad } : undefined,
    recentRepPerformance: latest
      ? median(latest.sets.map((s) => s.reps))
      : undefined,
    recentRir: latest
      ? median(
          latest.sets.flatMap((s) =>
            observedRir(s) === undefined ? [] : [observedRir(s)!]
          )
        )
      : undefined,
    relativeChange,
    trend:
      relativeChange === undefined
        ? "insufficient_data"
        : relativeChange > policy.trendThreshold
          ? "improving"
          : relativeChange < -policy.trendThreshold
            ? "declining"
            : "stable",
    confidence:
      estimates.length >= 6 ? "medium" : estimates.length ? "low" : "none",
  }
}
