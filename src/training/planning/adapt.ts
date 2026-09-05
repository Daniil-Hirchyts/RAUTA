import type {
  OptimizationInput,
  ProgramGenerationRequest,
  ProgramGenerationResult,
  TrainingProgram,
  TrainingWeek,
} from "../domain/types"
import {
  addDays,
  compareIds,
  DAY_MS,
  finite,
  fingerprint,
  isRecord,
  validIso,
} from "../numeric"
import { exclusionReasons } from "../data/exercises"
import {
  calculateHistoryVolume,
  completedWorkingSetUnits,
} from "../analysis/volume"
import {
  generateTrainingProgram,
  namespaceProgramIds,
  preparation,
} from "./generate"
import { generateSplitCandidates, hardConstructionChecks } from "./optimizer"
import {
  orderExercises,
  scoreExercise,
  scoreWeek,
  weekVolume,
} from "../scoring/scores"
import { prescribeExercise } from "./prescribe"
import { estimateSessionDuration } from "./duration"
import {
  planningEligibility,
  validateGenerationRequest,
  validatePolicy,
  validResistance,
} from "../validation/input"
export type AdaptationRequest = {
  previousProgram: TrainingProgram
  request: ProgramGenerationRequest
  mode: "remaining_week" | "next_week"
}
function validSource(value: unknown): value is TrainingProgram {
  if (
    !isRecord(value) ||
    typeof value.id !== "string" ||
    !value.id ||
    validatePolicy(value.policy).length ||
    !Array.isArray(value.weeks) ||
    !value.weeks.length ||
    value.weeks.length > 12
  )
    return false
  return value.weeks.every(
    (w) =>
      isRecord(w) &&
      validIso(w.start) &&
      Array.isArray(w.sessions) &&
      w.sessions.length > 0 &&
      w.sessions.length <= 7 &&
      w.sessions.every(
        (s) =>
          isRecord(s) &&
          typeof s.id === "string" &&
          validIso(s.scheduledAt) &&
          Array.isArray(s.focus) &&
          Array.isArray(s.exercises) &&
          s.exercises.length > 0 &&
          s.exercises.every(
            (e) =>
              isRecord(e) &&
              typeof e.exerciseId === "string" &&
              Array.isArray(e.targetMuscles) &&
              Array.isArray(e.workingSets) &&
              e.workingSets.length > 0 &&
              e.workingSets.length <= 30 &&
              Array.isArray(e.warmupSets) &&
              [...e.workingSets, ...e.warmupSets].every(
                (set) =>
                  isRecord(set) &&
                  typeof set.id === "string" &&
                  isRecord(set.targetReps) &&
                  finite(set.targetReps.min, 1, 50) &&
                  finite(set.targetReps.max, set.targetReps.min, 50) &&
                  validResistance(set.resistance)
              )
          )
      )
  )
}
/** Returns a revision for requested FUTURE slots. Completed/past sessions remain in the source program. */
export function adaptTrainingProgram({
  previousProgram,
  request,
  mode,
}: AdaptationRequest): ProgramGenerationResult {
  const invalid = validateGenerationRequest(request)
  if (invalid.length)
    return { status: "invalid", issues: invalid, suggestions: ["review_input"] }
  const eligibility = planningEligibility(request)
  if (eligibility.length)
    return {
      status: "unsupported",
      issues: eligibility,
      suggestions: ["review_input"],
    }
  if (
    !validSource(previousProgram) ||
    !["remaining_week", "next_week"].includes(mode) ||
    previousProgram.policyVersion !==
      (request.policy ?? previousProgram.policy).version
  )
    return {
      status: "invalid",
      issues: [
        { code: "INVALID_PROGRAM", context: { reason: "incompatible_source" } },
      ],
      suggestions: ["review_input"],
    }
  const source =
    mode === "remaining_week"
      ? previousProgram.weeks.find(
          (w) => w.start === request.schedule.weekStart
        )
      : previousProgram.weeks.at(-1)
  if (!source || request.schedule.durationWeeks !== 1)
    return {
      status: "invalid",
      issues: [{ code: "INVALID_INPUT", path: "adaptation.schedule" }],
      suggestions: ["review_input"],
    }
  const futureDays = request.schedule.days.filter(
    (day) =>
      Date.parse(addDays(request.schedule.weekStart, day)) >
      Date.parse(request.now)
  )
  if (futureDays.length !== request.schedule.days.length || !futureDays.length)
    return {
      status: "invalid",
      issues: [{ code: "INVALID_INPUT", path: "adaptation.futureDays" }],
      suggestions: ["review_input"],
    }
  const base = preparation(
    { ...request, policy: request.policy ?? previousProgram.policy },
    previousProgram
  )
  const actual = calculateHistoryVolume(
    request.history,
    base.index,
    base.policy,
    Date.parse(request.schedule.weekStart),
    Date.parse(request.now),
    true
  )
  const completedSets =
    mode === "remaining_week"
      ? request.history.sessions
          .filter(
            (s) =>
              Date.parse(s.completedAt) >=
              Date.parse(request.schedule.weekStart)
          )
          .reduce(
            (sum, s) =>
              sum +
              s.exercises.reduce(
                (n, e) =>
                  n +
                  e.sets.reduce(
                    (sum, set) => sum + completedWorkingSetUnits(set),
                    0
                  ),
                0
              ),
            0
          )
      : 0
  if (
    mode === "remaining_week" &&
    request.preferences.muscleVolumeBounds?.some(
      (b) => b.maximum !== undefined && actual[b.muscleId].effective > b.maximum
    )
  )
    return {
      status: "infeasible",
      issues: [
        {
          code: "VOLUME_LIMIT",
          context: { reason: "completed_work_already_exceeds_bound" },
        },
      ],
      suggestions: ["relax_volume_bounds"],
    }
  const remainingBudget =
    request.preferences.maxWeeklyWorkingSets === undefined
      ? undefined
      : Math.floor(request.preferences.maxWeeklyWorkingSets - completedSets)
  if (remainingBudget !== undefined && remainingBudget < futureDays.length)
    return {
      status: "infeasible",
      issues: [{ code: "VOLUME_LIMIT" }],
      suggestions: ["relax_volume_bounds"],
    }
  const adjustedRequest: ProgramGenerationRequest = {
    ...request,
    policy: base.policy,
    preferences: {
      ...request.preferences,
      maxWeeklyWorkingSets: remainingBudget,
      muscleVolumeBounds: request.preferences.muscleVolumeBounds?.map((b) => ({
        ...b,
        minimum: Math.max(
          0,
          (b.minimum ?? 0) -
            (mode === "remaining_week" ? actual[b.muscleId].effective : 0)
        ),
        maximum:
          b.maximum === undefined
            ? undefined
            : Math.max(
                0,
                b.maximum -
                  (mode === "remaining_week" ? actual[b.muscleId].effective : 0)
              ),
      })),
    },
  }
  const targets = base.targets.map((t) => ({
    ...t,
    minimum: Math.max(
      0,
      t.minimum - (mode === "remaining_week" ? actual[t.muscleId].effective : 0)
    ),
    preferred: Math.max(
      0,
      t.preferred -
        (mode === "remaining_week" ? actual[t.muscleId].effective : 0)
    ),
  }))
  const input: OptimizationInput = {
    ...base,
    request: adjustedRequest,
    targets,
    continuityIds: source.sessions.flatMap((s) =>
      s.exercises.map((e) => e.exerciseId)
    ),
  }
  let week: TrainingWeek = {
    id: "week-0",
    start: request.schedule.weekStart,
    phase:
      request.readiness?.perceivedReadiness === "low" &&
      Object.values(base.state.exercises).filter((e) => e.trend === "declining")
        .length >= 2
        ? "reduced_volume"
        : "base",
    targets,
    sessions: generateSplitCandidates(input)[0].sessions,
  }
  for (let si = 0; si < week.sessions.length; si++) {
    const day = futureDays.slice().sort((a, b) => a - b)[si]
    const prior =
      source.sessions.find(
        (s) =>
          (Date.parse(s.scheduledAt) - Date.parse(source.start)) / DAY_MS ===
          day
      ) ?? source.sessions[si % source.sessions.length]
    let session = {
      ...week.sessions[si],
      focus: [...prior.focus],
      exercises: [] as typeof prior.exercises,
    }
    for (const old of prior.exercises) {
      let e = input.index.byId.get(old.exerciseId)
      if (
        !e ||
        exclusionReasons(e, adjustedRequest.preferences, input.policy).length
      ) {
        const preferred = input.index.byId.get(old.exerciseId)
        e = [...input.index.byId.values()]
          .filter(
            (e) =>
              !session.exercises.some((p) => p.exerciseId === e.exercise.id) &&
              !exclusionReasons(e, adjustedRequest.preferences, input.policy)
                .length &&
              e.metadata.setRoles.some(
                (r) =>
                  r.role === "direct" && old.targetMuscles.includes(r.muscleId)
              )
          )
          .sort(
            (a, b) =>
              Number(
                b.metadata.movementPatterns.some((p) =>
                  preferred?.metadata.movementPatterns.includes(p)
                )
              ) -
                Number(
                  a.metadata.movementPatterns.some((p) =>
                    preferred?.metadata.movementPatterns.includes(p)
                  )
                ) || compareIds(a.exercise.id, b.exercise.id)
          )[0]
      }
      if (!e || session.exercises.some((p) => p.exerciseId === e.exercise.id))
        continue
      const current = weekVolume(week, input)
      const needsWork = e.metadata.setRoles.some(
        (r) =>
          r.role === "direct" &&
          current[r.muscleId] <
            (targets.find((t) => t.muscleId === r.muscleId)?.preferred ?? 0)
      )
      if (!needsWork && mode === "remaining_week") continue
      const count =
        week.phase === "reduced_volume"
          ? Math.max(1, old.workingSets.length - 1)
          : old.workingSets.length
      const prescription = prescribeExercise(
        e,
        count,
        session.id,
        scoreExercise(e, session, week, input),
        input
      )
      session = {
        ...session,
        exercises: [
          ...session.exercises,
          { ...prescription, order: session.exercises.length },
        ],
      }
      week = {
        ...week,
        sessions: week.sessions.map((s, i) => (i === si ? session : s)),
      }
    }
  }
  // Trim lowest-cost work until new time/volume constraints fit, without reducing rest.
  const maximumTrims = week.sessions.reduce(
    (n, s) => n + s.exercises.reduce((n, e) => n + e.workingSets.length, 0),
    0
  )
  for (
    let step = 0;
    step < maximumTrims && !hardConstructionChecks(week, input);
    step++
  ) {
    const removals = week.sessions
      .flatMap((s, si) =>
        s.exercises.flatMap((e, ei) => {
          if (s.exercises.length === 1 && e.workingSets.length === 1) return []
          const candidate = {
            ...week,
            sessions: week.sessions.map((s, i) =>
              i !== si
                ? s
                : {
                    ...s,
                    exercises: s.exercises.flatMap((e, j) =>
                      j !== ei
                        ? [e]
                        : e.workingSets.length > 1
                          ? [{ ...e, workingSets: e.workingSets.slice(0, -1) }]
                          : []
                    ),
                  }
            ),
          }
          return [{ candidate, score: scoreWeek(candidate, input).total }]
        })
      )
      .sort((a, b) => b.score - a.score)
    if (!removals.length) break
    week = removals[0].candidate
  }
  week = {
    ...week,
    sessions: week.sessions.map((s) => {
      const ordered = { ...s, exercises: orderExercises(s.exercises, input) }
      return {
        ...ordered,
        duration: estimateSessionDuration(ordered, input.index, input.policy),
      }
    }),
  }
  if (!hardConstructionChecks(week, input, true))
    return {
      status: "infeasible",
      issues: [{ code: "SESSION_DURATION_INFEASIBLE" }],
      suggestions: ["increase_duration", "relax_volume_bounds"],
    }
  const result = generateTrainingProgram(adjustedRequest, {
    optimize: () => ({
      week,
      split: "preserved_structure",
      candidates: input.index.byId.size,
      iterations: maximumTrims,
      splits: [
        {
          name: "preserved_structure",
          score: scoreWeek(week, input).total,
          valid: true,
        },
      ],
    }),
  })
  if ("program" in result) {
    result.program.adaptation = {
      sourceProgramId: previousProgram.id,
      asOf: request.now,
      mode,
    }
    namespaceProgramIds(
      result.program,
      "adaptation-" + fingerprint({ source: previousProgram.id, request, week })
    )
    if (mode === "remaining_week")
      result.issues.push({ code: "MISSED_VOLUME_DROPPED" })
    if (week.phase === "reduced_volume")
      result.issues.push({ code: "REDUCED_VOLUME" })
    result.program.diagnostics.warnings = result.issues
  }
  return result
}
