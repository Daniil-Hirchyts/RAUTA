import { DEFAULT_POLICY } from "../policy"
import { createExerciseIndex } from "../data/exercises"
import { MUSCLE_IDS } from "../../types"
import type {
  DerivedTrainingState,
  ExerciseIndex,
  MuscleTarget,
  MuscleTrainingState,
  ProgramGenerationRequest,
  TrainingPolicy,
  TrainingProgram,
} from "../domain/types"
import { DAY_MS, clamp, mean } from "../numeric"
import { analyzeExercisePerformance } from "./strength"
import {
  calculateHistoryVolume,
  effectiveSetCredit,
  isWorkingSet,
  completedWorkingSetUnits,
} from "./volume"
export function analyzeTrainingState(
  request: ProgramGenerationRequest,
  index: ExerciseIndex = createExerciseIndex(
    request.exercises,
    request.metadata
  ),
  targets: MuscleTarget[] = [],
  policy: TrainingPolicy = request.policy ?? DEFAULT_POLICY,
  previousProgram?: TrainingProgram
): DerivedTrainingState {
  const now = Date.parse(request.now)
  const start = Date.parse(request.schedule.weekStart)
  const windows = [7, 14, 28].map((days) =>
    calculateHistoryVolume(
      request.history,
      index,
      policy,
      now - days * DAY_MS,
      now
    )
  )
  const week = calculateHistoryVolume(
    request.history,
    index,
    policy,
    start,
    Math.min(start + 7 * DAY_MS - 1, now),
    true
  )
  const knownHistory =
    request.history.coverage === "complete" &&
    !!request.history.coverageStart &&
    Date.parse(request.history.coverageStart) <= now - 28 * DAY_MS
  const muscles = Object.fromEntries(
    MUSCLE_IDS.map((muscleId) => {
      const target = targets.find((t) => t.muscleId === muscleId)
      let decayedWorkload = 0
      let lastMeaningfulTrainingAt: string | undefined
      let recentSessionCount = 0
      for (const session of request.history.sessions) {
        let exposure = 0
        for (const exercise of session.exercises) {
          const e = index.byId.get(exercise.exerciseId)
          if (!e) continue
          const credit = effectiveSetCredit(e, muscleId, policy).effective
          for (const set of exercise.sets) {
            const at = set.timestamp ?? session.completedAt
            const time = Date.parse(at)
            const hours = (now - time) / 3_600_000
            if (!isWorkingSet(set) || hours < 0) continue
            const value = credit * (set.side === "both" ? 1 : 0.5)
            decayedWorkload +=
              value *
              Math.exp((-Math.LN2 * hours) / policy.workloadHalfLifeHours)
            if (hours < 28 * 24) exposure += value
            if (
              value > 0 &&
              (!lastMeaningfulTrainingAt ||
                time > Date.parse(lastMeaningfulTrainingAt))
            )
              lastMeaningfulTrainingAt = at
          }
        }
        if (exposure >= policy.meaningfulExposureSets) recentSessionCount++
      }
      const preferred = target?.preferred ?? 0
      const effective = week[muscleId].effective
      const earlier =
        windows[2][muscleId].effective - windows[1][muscleId].effective
      const state: MuscleTrainingState = {
        muscleId,
        targetWeeklyEffectiveSets: preferred,
        effectiveSetsCurrentWeek: effective,
        directSetsCurrentWeek: week[muscleId].direct,
        indirectSetsCurrentWeek: week[muscleId].indirect,
        rolling7DaySets: windows[0][muscleId].effective,
        rolling14DaySets: windows[1][muscleId].effective,
        rolling28DaySets: windows[2][muscleId].effective,
        recentSessionCount,
        lastMeaningfulTrainingAt,
        decayedWorkload,
        volumeTargetDeficit: Math.max(0, preferred - effective),
        workloadTrend:
          knownHistory && earlier > 0
            ? (windows[1][muscleId].effective - earlier) / earlier
            : undefined,
        priorityScore:
          (target?.importance ?? 1) *
          (preferred ? clamp((preferred - effective) / preferred) : 0),
        status:
          !target || (!knownHistory && !recentSessionCount)
            ? "unknown"
            : effective < target.minimum
              ? "under_target"
              : effective > target.upperGuideline
                ? "over_target"
                : "on_target",
        confidence: knownHistory
          ? recentSessionCount >= policy.historyMinSessions
            ? "medium"
            : "low"
          : recentSessionCount
            ? "low"
            : "none",
      }
      return [muscleId, state]
    })
  ) as DerivedTrainingState["muscles"]
  const ids = [
    ...new Set(
      request.history.sessions.flatMap((s) =>
        s.exercises.map((e) => e.exerciseId)
      )
    ),
  ].filter((id) => index.byId.has(id))
  const exercises = Object.fromEntries(
    ids.map((id) => [
      id,
      analyzeExercisePerformance(
        request.history,
        id,
        request.now,
        policy,
        index.byId.get(id)?.metadata.tracking === "external_load"
      ),
    ])
  )
  const adherence: DerivedTrainingState["adherence"] = {}
  if (
    previousProgram &&
    request.history.coverage === "complete" &&
    request.history.coverageStart
  ) {
    const planned = previousProgram.weeks
      .flatMap((w) => w.sessions)
      .filter(
        (s) =>
          Date.parse(s.scheduledAt) < now &&
          Date.parse(s.scheduledAt) >=
            Date.parse(request.history.coverageStart!)
      )
    if (planned.length) {
      const matched = planned.map((p) => ({
        p,
        actual: request.history.sessions.find(
          (s) => s.plannedSessionId === p.id
        ),
      }))
      adherence.sessionCompletion =
        matched.filter((x) => x.actual?.status === "completed").length /
        planned.length
      const plannedSets = planned
        .flatMap((s) => s.exercises.flatMap((e) => e.workingSets))
        .map((s) => s.id)
      const completedUnits = new Map<string, number>()
      for (const { p, actual } of matched)
        for (const e of actual?.exercises ?? [])
          for (const set of e.sets) {
            if (
              set.plannedSetId &&
              p.exercises.some(
                (planned) =>
                  planned.exerciseId === e.exerciseId &&
                  planned.workingSets.some((s) => s.id === set.plannedSetId)
              )
            )
              completedUnits.set(
                set.plannedSetId,
                Math.min(
                  1,
                  (completedUnits.get(set.plannedSetId) ?? 0) +
                    completedWorkingSetUnits(set)
                )
              )
          }
      adherence.setCompletion = plannedSets.length
        ? plannedSets.reduce((n, id) => n + (completedUnits.get(id) ?? 0), 0) /
          plannedSets.length
        : undefined
      const plannedExercises = matched.flatMap((x) =>
        x.p.exercises.map((e) => ({ id: e.exerciseId, actual: x.actual }))
      )
      adherence.exerciseCompletion = plannedExercises.length
        ? plannedExercises.filter((x) =>
            x.actual?.exercises.some(
              (e) => e.exerciseId === x.id && e.sets.some(isWorkingSet)
            )
          ).length / plannedExercises.length
        : undefined
      const ratios = matched.flatMap((x) =>
        x.actual?.durationSeconds !== undefined && x.p.duration.totalSeconds > 0
          ? [x.actual.durationSeconds / x.p.duration.totalSeconds]
          : []
      )
      adherence.durationRatio = ratios.length ? mean(ratios) : undefined
    }
  }
  return {
    muscles,
    exercises,
    adherence,
    confidence: knownHistory ? "medium" : ids.length ? "low" : "none",
    issues:
      request.history.coverage === "unknown"
        ? [{ code: "INCOMPLETE_HISTORY" }]
        : [],
  }
}
