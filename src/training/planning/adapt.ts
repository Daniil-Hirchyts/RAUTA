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
  calculateHistoryExerciseFrequency,
  calculateHistoryFrequency,
  calculateHistoryVolume,
  calculateSessionVolume,
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
    fingerprint(previousProgram.policy) !==
      fingerprint(request.policy ?? previousProgram.policy)
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
  const authoritativeRequest: ProgramGenerationRequest = {
    ...request,
    policy: request.policy ?? previousProgram.policy,
  }
  const base = preparation(authoritativeRequest, previousProgram)
  const actual = calculateHistoryVolume(
    request.history,
    base.index,
    base.policy,
    Date.parse(request.schedule.weekStart),
    Date.parse(request.now),
    true
  )
  const actualFrequency =
    mode === "remaining_week"
      ? calculateHistoryFrequency(
          request.history,
          base.index,
          base.policy,
          Date.parse(request.schedule.weekStart),
          Date.parse(request.now),
          true
        )
      : undefined
  const actualSpecificFrequency =
    mode === "remaining_week"
      ? calculateHistoryExerciseFrequency(
          request.history,
          base.policy,
          Date.parse(request.schedule.weekStart),
          Date.parse(request.now),
          true
        )
      : {}
  const completedSets =
    mode === "remaining_week"
      ? request.history.sessions
          .filter(
            (s) =>
              Date.parse(s.completedAt) >=
                Date.parse(request.schedule.weekStart) &&
              Date.parse(s.completedAt) <= Date.parse(request.now)
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
  const remainingMuscleVolumeBounds =
    mode === "remaining_week"
      ? request.preferences.muscleVolumeBounds?.map((b) => ({
          ...b,
          minimum: Math.max(0, (b.minimum ?? 0) - actual[b.muscleId].effective),
          maximum:
            b.maximum === undefined
              ? undefined
              : Math.max(0, b.maximum - actual[b.muscleId].effective),
        }))
      : undefined
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
    preferredExposures: Math.max(
      0,
      t.preferredExposures -
        (mode === "remaining_week" ? (actualFrequency?.[t.muscleId] ?? 0) : 0)
    ),
  }))
  const remainingSpecificTargets = new Map(
    (request.preferences.strengthExerciseIds ?? []).map((exerciseId) => {
      const planned = source.sessions.filter((s) =>
        s.exercises.some((e) => e.exerciseId === exerciseId)
      ).length
      return [
        exerciseId,
        Math.max(
          0,
          planned -
            (mode === "remaining_week"
              ? (actualSpecificFrequency[exerciseId] ?? 0)
              : 0)
        ),
      ] as const
    })
  )
  const input: OptimizationInput = {
    ...base,
    request: authoritativeRequest,
    targets,
    continuityIds: source.sessions.flatMap((s) =>
      s.exercises.map((e) => e.exerciseId)
    ),
    adaptation:
      mode === "remaining_week"
        ? {
            baselineCompletedWorkingSets: completedSets,
            baselineMuscleVolume: Object.fromEntries(
              Object.entries(actual).map(([muscleId, volume]) => [
                muscleId,
                volume.effective,
              ])
            ),
            remainingWorkingSetBudget: remainingBudget,
            remainingMuscleVolumeBounds,
          }
        : undefined,
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
  const plannedMuscleExposures = (candidate: TrainingWeek, muscleId: string) =>
    candidate.sessions.filter(
      (s) =>
        calculateSessionVolume(s, input.index, input.policy)[
          muscleId as keyof ReturnType<typeof calculateSessionVolume>
        ].effective >= input.policy.meaningfulExposureSets
    ).length
  const plannedSpecificExposures = (candidate: TrainingWeek, exerciseId: string) =>
    candidate.sessions.filter((s) =>
      s.exercises.some((e) => e.exerciseId === exerciseId)
    ).length
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
        exclusionReasons(e, authoritativeRequest.preferences, input.policy).length
      ) {
        const preferred = input.index.byId.get(old.exerciseId)
        e = [...input.index.byId.values()]
          .filter(
            (e) =>
              !session.exercises.some((p) => p.exerciseId === e.exercise.id) &&
              !exclusionReasons(e, authoritativeRequest.preferences, input.policy)
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
      const needsFrequency = e.metadata.setRoles.some(
        (r) =>
          r.role === "direct" &&
          plannedMuscleExposures(week, r.muscleId) <
            (targets.find((t) => t.muscleId === r.muscleId)
              ?.preferredExposures ?? 0)
      )
      const needsSpecificity =
        plannedSpecificExposures(week, e.exercise.id) <
        (remainingSpecificTargets.get(e.exercise.id) ?? 0)
      if (
        !needsWork &&
        !needsFrequency &&
        !needsSpecificity &&
        mode === "remaining_week"
      )
        continue
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
  // Reschedule explicit strength-lift occurrences that were missed earlier in the
  // week when a future slot remains. One lift occurrence is never stacked twice
  // into the same session.
  for (const [exerciseId, desired] of remainingSpecificTargets) {
    const e = input.index.byId.get(exerciseId)
    if (
      !e ||
      exclusionReasons(e, authoritativeRequest.preferences, input.policy).length
    )
      continue
    const template = source.sessions
      .flatMap((s) => s.exercises)
      .find((p) => p.exerciseId === exerciseId)
    while (
      plannedSpecificExposures(week, exerciseId) < desired &&
      plannedSpecificExposures(week, exerciseId) < week.sessions.length
    ) {
      const existingTimes = week.sessions
        .filter((s) => s.exercises.some((p) => p.exerciseId === exerciseId))
        .map((s) => Date.parse(s.scheduledAt))
      const candidates = week.sessions
        .filter((s) => !s.exercises.some((p) => p.exerciseId === exerciseId))
        .sort((a, b) => {
          const spacing = (s: typeof a) =>
            existingTimes.length
              ? Math.min(
                  ...existingTimes.map((time) =>
                    Math.abs(Date.parse(s.scheduledAt) - time)
                  )
                )
              : Infinity
          return spacing(b) - spacing(a) || compareIds(a.id, b.id)
        })
      const session = candidates[0]
      if (!session) break
      const count = Math.min(
        input.policy.maxSetsPerExercise,
        Math.max(
          1,
          week.phase === "reduced_volume"
            ? (template?.workingSets.length ?? 1) - 1
            : (template?.workingSets.length ?? 1)
        )
      )
      const prescription = prescribeExercise(
        e,
        count,
        session.id,
        scoreExercise(e, session, week, input),
        input
      )
      week = {
        ...week,
        sessions: week.sessions.map((s) =>
          s.id === session.id
            ? {
                ...s,
                exercises: [
                  ...s.exercises,
                  { ...prescription, order: s.exercises.length },
                ],
              }
            : s
        ),
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
                          ? [
                              {
                                ...prescribeExercise(
                                  input.index.byId.get(e.exerciseId)!,
                                  e.workingSets.length - 1,
                                  s.id,
                                  e.rationale,
                                  input
                                ),
                                order: e.order,
                              },
                            ]
                          : []
                    ),
                  }
            ),
          }
          return [{ candidate, score: scoreWeek(candidate, input).total }]
        })
      )
      .filter(({ candidate }) =>
        [...remainingSpecificTargets].every(
          ([exerciseId, desired]) =>
            plannedSpecificExposures(candidate, exerciseId) >=
            Math.min(desired, candidate.sessions.length)
        )
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
  const result = generateTrainingProgram(
    authoritativeRequest,
    {
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
    },
    {
      sourceProgramId: previousProgram.id,
      asOf: request.now,
      mode,
    }
  )
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
    if (mode === "remaining_week") {
      const sourceVolume = Object.fromEntries(
        targets.map((t) => [
          t.muscleId,
          source.sessions.reduce(
            (sum, session) =>
              sum +
              calculateSessionVolume(session, input.index, input.policy)[
                t.muscleId
              ].effective,
            0
          ),
        ])
      ) as Record<(typeof targets)[number]["muscleId"], number>
      const adaptedVolume = weekVolume(week, input)
      const dropped = targets.some(
        (t) =>
          Math.max(0, sourceVolume[t.muscleId] - actual[t.muscleId].effective) >
          (adaptedVolume[t.muscleId] ?? 0) + 1e-6
      )
      if (dropped) result.issues.push({ code: "MISSED_VOLUME_DROPPED" })
    }
    const missingSpecific = [...remainingSpecificTargets]
      .filter(
        ([exerciseId, desired]) =>
          plannedSpecificExposures(week, exerciseId) < desired
      )
      .map(([exerciseId]) => exerciseId)
    if (missingSpecific.length)
      result.issues.push({
        code: "SPECIFICITY_UNAVAILABLE",
        context: { exerciseIds: missingSpecific },
      })
    if (week.phase === "reduced_volume")
      result.issues.push({ code: "REDUCED_VOLUME" })
    result.program.diagnostics.warnings = result.issues
  }
  return result
}
