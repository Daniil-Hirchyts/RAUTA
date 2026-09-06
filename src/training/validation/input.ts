import { MUSCLE_IDS } from "../../types"
import type {
  PlanningIssue,
  ProgramGenerationRequest,
  TrainingPolicy,
} from "../domain/types"
import { finite, isRecord, validIso } from "../numeric"
import { DEFAULT_POLICY } from "../policy"
import { validateExerciseData } from "../data/exercises"
const choices = (v: unknown, allowed: readonly unknown[]) => allowed.includes(v)
const strings = (v: unknown) =>
  Array.isArray(v) &&
  v.every((x) => typeof x === "string" && x.length > 0) &&
  new Set(v).size === v.length
const integer = (v: unknown, min: number, max: number) =>
  finite(v, min, max) && Number.isInteger(v)
const optional = (v: unknown, check: (v: unknown) => boolean) =>
  v === undefined || check(v)
export function validResistance(r: unknown): boolean {
  if (!isRecord(r)) return false
  if (r.type === "unknown" || r.type === "bodyweight") return true
  return (
    choices(r.type, ["external_load", "assistance"]) &&
    finite(r.kg, 0, 2000) &&
    choices(r.basis, ["total", "per_implement"]) &&
    typeof r.stationId === "string" &&
    r.stationId.length > 0
  )
}
export function validatePolicy(value: unknown): PlanningIssue[] {
  const issues: PlanningIssue[] = []
  function walk(v: unknown, reference: unknown, path: string) {
    if (typeof reference === "number") {
      if (!finite(v, -100, 10000)) issues.push({ code: "INVALID_INPUT", path })
    } else if (typeof reference === "string") {
      if (typeof v !== "string" || !v)
        issues.push({ code: "INVALID_INPUT", path })
    } else if (Array.isArray(reference)) {
      if (
        !Array.isArray(v) ||
        !v.length ||
        v.length > 5 ||
        v.some((n) => !finite(n, 0, 100))
      )
        issues.push({ code: "INVALID_INPUT", path })
    } else if (isRecord(reference)) {
      if (!isRecord(v)) issues.push({ code: "INVALID_INPUT", path })
      else
        for (const [key, child] of Object.entries(reference))
          walk(v[key], child, `${path}.${key}`)
    }
  }
  walk(value, DEFAULT_POLICY, "policy")
  if (issues.length) return issues
  const p = value as TrainingPolicy
  for (const key of [
    "beamWidth",
    "candidateLimit",
    "maxExercisesPerSession",
    "maxSetsPerExercise",
    "localIterations",
  ] as const)
    if (!integer(p[key], 1, key === "localIterations" ? 100 : 30))
      issues.push({ code: "INVALID_INPUT", path: `policy.${key}` })
  for (const goal of Object.values(p.goals))
    if (!(
      goal.volume.minimum >= 0 &&
      goal.volume.minimum <= goal.volume.preferred &&
      goal.volume.preferred <= goal.volume.upperGuideline &&
      goal.volume.upperGuideline <= 40 &&
      goal.compoundRest >= 30 &&
      goal.isolationRest >= 30 &&
      goal.rir >= 0 &&
      goal.rir <= 5 &&
      goal.specificityWeight >= 0 &&
      [goal.compoundReps, goal.isolationReps].every(
        (r) => integer(r.min, 1, 50) && integer(r.max, r.min, 50)
      )
    ))
      issues.push({ code: "INVALID_INPUT", path: "policy.goals" })
  if (
    p.workloadHalfLifeHours <= 0 ||
    p.staleAfterDays <= 0 ||
    p.secondsPerRep <= 0 ||
    p.sessionMuscleGuideline <= 0 ||
    p.meaningfulExposureSets <= 0 ||
    p.indirectCredit < 0 ||
    p.indirectCredit > 1 ||
    p.minimumClassificationConfidence < 0 ||
    p.minimumClassificationConfidence > 1 ||
    p.reductionFraction < 0 ||
    p.reductionFraction > 0.5 ||
    p.maxLoadIncreaseFraction <= 0 ||
    p.maxLoadIncreaseFraction > 0.2 ||
    p.coarseGridMaxLoadIncreaseFraction <= p.maxLoadIncreaseFraction ||
    p.coarseGridMaxLoadIncreaseFraction > 1 ||
    !integer(p.coarseGridMaxExtraReps, 0, 20) ||
    !integer(p.coarseGridRequiredTopExposures, 1, 10) ||
    !integer(p.progressionEvidenceSets, 1, 10) ||
    p.maxWeeklyVolumeIncrease < 0 ||
    p.maxWeeklyVolumeIncrease > 4 ||
    p.warmupFractions.length !== p.warmupReps.length ||
    p.warmupFractions.some((f) => f <= 0 || f >= 1) ||
    p.warmupReps.some((r) => !integer(r, 1, 10)) ||
    p.generalWarmupSeconds < 0 ||
    p.transitionSeconds < 0 ||
    p.warmupRestSeconds < 0 ||
    p.rirTolerance < 0 ||
    p.rirTolerance > 2 ||
    p.trendThreshold < 0 ||
    !integer(p.maxBodyweightReps, 1, 50) ||
    p.historyMinSessions < 1 ||
    !Object.values(p.priorityMultipliers).every((x) => x > 0 && x <= 2)
  )
    issues.push({ code: "INVALID_INPUT", path: "policy" })
  if (
    !finite(p.adherenceReductionThreshold, 0, 1) ||
    !finite(p.beginnerRir, 0, 5) ||
    !integer(p.heavyWarmupMaxReps, 1, 20) ||
    Object.values(p.orderingWeights).some((n) => n < 0) ||
    Object.values(p.similarityWeights).some((n) => n < 0) ||
    Math.abs(
      Object.values(p.similarityWeights).reduce((n, w) => n + w, 0) - 1
    ) > 1e-6
  )
    issues.push({ code: "INVALID_INPUT", path: "policy.scoring" })
  return issues
}
export function validateGenerationRequest(value: unknown): PlanningIssue[] {
  const issues: PlanningIssue[] = []
  const active = new WeakSet<object>()
  let nodes = 0
  const serializable = (v: unknown, depth = 0): boolean => {
    if (
      ++nodes > 5_000_000 ||
      depth > 30 ||
      typeof v === "function" ||
      typeof v === "symbol" ||
      typeof v === "bigint"
    )
      return false
    if (!v || typeof v !== "object") return true
    if (active.has(v)) return false
    active.add(v)
    const valid = Object.values(v).every((child) =>
      serializable(child, depth + 1)
    )
    active.delete(v)
    return valid
  }
  if (!serializable(value))
    return [{ code: "INVALID_INPUT", path: "request.serialization" }]
  const check = (valid: boolean, path: string) => {
    if (!valid) issues.push({ code: "INVALID_INPUT", path })
  }
  if (!isRecord(value)) return [{ code: "INVALID_INPUT", path: "request" }]
  const { profile: p, preferences: prefs, schedule: s, history: h } = value
  if (!isRecord(p) || !isRecord(prefs) || !isRecord(s) || !isRecord(h))
    return [{ code: "INVALID_INPUT", path: "request" }]
  check(finite(p.age, 0, 120), "profile.age")
  check(
    choices(p.trainingExperience, ["beginner", "intermediate", "advanced"]),
    "profile.trainingExperience"
  )
  check(
    optional(p.bodyWeightKg, (n) => finite(n, 20, 500)) &&
      optional(p.heightCm, (n) => finite(n, 50, 260)) &&
      optional(p.trainingAgeMonths, (n) => finite(n, 0, 1200)),
    "profile.demographics"
  )
  check(
    isRecord(p.health) &&
      (p.health.status === "healthy" ||
        (p.health.status === "unsupported" &&
          Array.isArray(p.health.reasons) &&
          p.health.reasons.length > 0 &&
          p.health.reasons.every((r) =>
            choices(r, [
              "medical_condition",
              "active_injury",
              "rehabilitation",
              "pregnancy",
              "other",
            ])
          ))),
    "profile.health"
  )
  check(
    choices(prefs.goal, [...Object.keys(DEFAULT_POLICY.goals), "power"]),
    "preferences.goal"
  )
  check(strings(prefs.availableEquipment), "preferences.availableEquipment")
  for (const key of [
    "preferredExerciseIds",
    "dislikedExerciseIds",
    "excludedExerciseIds",
    "strengthExerciseIds",
    "excludedPatterns",
  ])
    check(optional(prefs[key], strings), `preferences.${key}`)
  check(
    finite(prefs.maxSessionDurationMinutes, 1, 300),
    "preferences.maxSessionDurationMinutes"
  )
  check(
    optional(prefs.preferredSessionDurationMinutes, (n) =>
      finite(n, 1, Number(prefs.maxSessionDurationMinutes))
    ),
    "preferences.preferredSessionDurationMinutes"
  )
  check(
    optional(prefs.maxWeeklyWorkingSets, (n) => integer(n, 1, 500)),
    "preferences.maxWeeklyWorkingSets"
  )
  for (const key of ["priorityMuscles", "muscleVolumeBounds"])
    if (prefs[key] !== undefined) {
      const values = prefs[key]
      check(
        Array.isArray(values) &&
          values.every(
            (x) =>
              isRecord(x) &&
              MUSCLE_IDS.includes(x.muscleId as never) &&
              (key === "priorityMuscles"
                ? choices(x.level, ["low", "normal", "high", "specialization"])
                : optional(x.minimum, (n) => finite(n, 0, 40)) &&
                  optional(x.maximum, (n) => finite(n, 0, 40)) &&
                  Number(x.minimum ?? 0) <= Number(x.maximum ?? 40))
          ) &&
          new Set(values.map((x) => (isRecord(x) ? x.muscleId : undefined)))
            .size === values.length,
        `preferences.${key}`
      )
    }
  if (prefs.loadContexts !== undefined)
    check(
      isRecord(prefs.loadContexts) &&
        Object.values(prefs.loadContexts).every(
          (v) =>
            isRecord(v) &&
            typeof v.stationId === "string" &&
            !!v.stationId &&
            choices(v.basis, ["total", "per_implement"])
        ),
      "preferences.loadContexts"
    )
  if (prefs.loadGrids !== undefined)
    check(
      isRecord(prefs.loadGrids) &&
        Object.values(prefs.loadGrids).every(
          (g) =>
            isRecord(g) &&
            (Array.isArray(g.availableLoadsKg)
              ? g.availableLoadsKg.length > 0 &&
                g.availableLoadsKg.length <= 1000 &&
                g.availableLoadsKg.every((n) => finite(n, 0, 2000))
              : finite(g.incrementKg, 0.001, 100) &&
                optional(g.minimumKg, (n) => finite(n, 0, 2000)) &&
                optional(g.maximumKg, (n) =>
                  finite(n, Number(g.minimumKg ?? 0), 2000)
                ))
        ),
      "preferences.loadGrids"
    )
  check(validIso(value.now), "now")
  check(
    validIso(s.weekStart) && String(s.weekStart).includes("T00:00:00"),
    "schedule.weekStart"
  )
  check(
    Array.isArray(s.days) &&
      s.days.length >= 1 &&
      s.days.length <= 7 &&
      s.days.every((d) => integer(d, 0, 6)) &&
      new Set(s.days).size === s.days.length,
    "schedule.days"
  )
  check(integer(s.durationWeeks, 1, 12), "schedule.durationWeeks")
  check(
    choices(h.coverage, ["complete", "unknown"]) &&
      (h.coverage !== "complete" || validIso(h.coverageStart)) &&
      optional(
        h.coverageStart,
        (v) => validIso(v) && Date.parse(v) <= Date.parse(String(value.now))
      ),
    "history.coverage"
  )
  if (value.readiness !== undefined) {
    const r = value.readiness
    check(
      isRecord(r) &&
        optional(r.pain, (v) => typeof v === "boolean") &&
        optional(r.perceivedReadiness, (v) => choices(v, ["normal", "low"])) &&
        optional(
          r.soreness,
          (v) =>
            Array.isArray(v) &&
            v.every(
              (x) =>
                isRecord(x) &&
                MUSCLE_IDS.includes(x.muscleId as never) &&
                choices(x.level, ["none", "mild", "high"])
            )
        ),
      "readiness"
    )
  }
  if (value.policy !== undefined) issues.push(...validatePolicy(value.policy))
  issues.push(...validateExerciseData(value.exercises))
  check(
    Array.isArray(value.exercises) && value.exercises.length <= 10000,
    "exercises"
  )
  if (value.metadata !== undefined)
    check(
      Array.isArray(value.metadata) && value.metadata.every(isRecord),
      "metadata"
    )
  if (!Array.isArray(h.sessions) || h.sessions.length > 10000)
    return [...issues, { code: "INVALID_INPUT", path: "history.sessions" }]
  const sessionIds = new Set<string>()
  const setIds = new Set<string>()
  const plannedSessions = new Set<string>()
  const plannedSets = new Map<
    string,
    { sides: string[]; exerciseId: string; sessionId: string }
  >()
  const exerciseIds = new Set(
    Array.isArray(value.exercises)
      ? value.exercises.filter(isRecord).map((e) => e.id)
      : []
  )
  for (const [i, session] of h.sessions.entries()) {
    const path = `history.sessions.${i}`
    if (
      !isRecord(session) ||
      typeof session.id !== "string" ||
      !session.id ||
      !validIso(session.startedAt) ||
      !validIso(session.completedAt) ||
      !Array.isArray(session.exercises)
    ) {
      check(false, path)
      continue
    }
    check(!sessionIds.has(session.id), path + ".id")
    sessionIds.add(session.id)
    check(
      Date.parse(session.startedAt) <= Date.parse(session.completedAt) &&
        Date.parse(session.completedAt) <= Date.parse(String(value.now)),
      path + ".time"
    )
    check(
      choices(session.status, ["completed", "partial"]) &&
        optional(session.durationSeconds, (v) => finite(v, 0, 86400)),
      path
    )
    if (session.plannedSessionId !== undefined) {
      check(
        typeof session.plannedSessionId === "string" &&
          !plannedSessions.has(String(session.plannedSessionId)),
        path + ".plannedSessionId"
      )
      plannedSessions.add(String(session.plannedSessionId))
    }
    const perSessionIds = new Set<string>()
    for (const e of session.exercises) {
      if (
        !isRecord(e) ||
        typeof e.exerciseId !== "string" ||
        !Array.isArray(e.sets) ||
        e.sets.length > 100
      ) {
        check(false, path + ".exercises")
        continue
      }
      check(!perSessionIds.has(e.exerciseId), path + ".exerciseId")
      perSessionIds.add(e.exerciseId)
      if (!exerciseIds.has(e.exerciseId))
        issues.push({
          code: "UNKNOWN_EXERCISE",
          path,
          context: { exerciseId: e.exerciseId },
        })
      for (const set of e.sets) {
        if (!isRecord(set)) {
          check(false, path + ".sets")
          continue
        }
        check(
          typeof set.id === "string" && !!set.id && !setIds.has(String(set.id)),
          path + ".set.id"
        )
        setIds.add(String(set.id))
        check(
          integer(set.reps, set.completed ? 1 : 0, 1000) &&
            typeof set.completed === "boolean" &&
            choices(set.setType, [
              "warmup",
              "working",
              "backoff",
              "drop",
              "other",
            ]) &&
            choices(set.side, ["both", "left", "right"]) &&
            validResistance(set.resistance),
          path + ".set"
        )
        check(
          optional(set.rir, (n) => finite(n, 0, 10)) &&
            optional(set.rpe, (n) => finite(n, 0, 10)) &&
            !(
              finite(set.rir) &&
              finite(set.rpe) &&
              Math.abs(set.rir + set.rpe - 10) > 1
            ),
          path + ".set.effort"
        )
        check(
          optional(
            set.timestamp,
            (v) =>
              validIso(v) &&
              Date.parse(v) >= Date.parse(String(session.startedAt)) &&
              Date.parse(v) <= Date.parse(String(session.completedAt))
          ),
          path + ".set.timestamp"
        )
        if (set.plannedSetId !== undefined) {
          const prior = plannedSets.get(String(set.plannedSetId))
          check(
            typeof set.plannedSetId === "string" &&
              (!prior ||
                (prior.exerciseId === e.exerciseId &&
                  prior.sessionId === session.id &&
                  !prior.sides.includes(String(set.side)) &&
                  !prior.sides.includes("both") &&
                  set.side !== "both")),
            path + ".plannedSetId"
          )
          plannedSets.set(String(set.plannedSetId), {
            sides: [...(prior?.sides ?? []), String(set.side)],
            exerciseId: e.exerciseId,
            sessionId: session.id,
          })
        }
      }
    }
  }
  return issues
}
export function planningEligibility(
  request: ProgramGenerationRequest
): PlanningIssue[] {
  if (
    request.profile.age < 18 ||
    request.profile.health.status !== "healthy" ||
    request.readiness?.pain
  )
    return [{ code: "UNSUPPORTED_POPULATION" }]
  if (request.preferences.goal === "power")
    return [{ code: "UNSUPPORTED_GOAL", context: { goal: "power" } }]
  return []
}
