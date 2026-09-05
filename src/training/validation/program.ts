import type {
  ExerciseIndex,
  PlanningIssue,
  ProgramGenerationRequest,
  TrainingProgram,
} from "../domain/types"
import { finite, isRecord, validIso, DAY_MS } from "../numeric"
import { createExerciseIndex, exclusionReasons } from "../data/exercises"
import {
  calculateHistoryVolume,
  calculateProgramFrequency,
  calculateProgramVolume,
  completedWorkingSetUnits,
} from "../analysis/volume"
import { estimateSessionDuration } from "../planning/duration"
import { isAchievableLoad } from "../progression/progression"
import {
  planningEligibility,
  validResistance,
  validateGenerationRequest,
  validatePolicy,
} from "./input"
export function validateTrainingProgram(
  value: unknown,
  request: ProgramGenerationRequest,
  suppliedIndex?: ExerciseIndex
): { valid: boolean; issues: PlanningIssue[]; warnings: PlanningIssue[] } {
  const invalid = validateGenerationRequest(request)
  if (invalid.length) return { valid: false, issues: invalid, warnings: [] }
  const eligibility = planningEligibility(request)
  if (eligibility.length)
    return { valid: false, issues: eligibility, warnings: [] }
  const index =
    suppliedIndex ?? createExerciseIndex(request.exercises, request.metadata)
  if (index.issues.length)
    return { valid: false, issues: index.issues, warnings: [] }
  const issues: PlanningIssue[] = []
  const warnings: PlanningIssue[] = []
  const fail = (path: string) => issues.push({ code: "INVALID_PROGRAM", path })
  if (
    !isRecord(value) ||
    !Array.isArray(value.weeks) ||
    !value.weeks.length ||
    value.weeks.length > 12 ||
    validatePolicy(value.policy).length
  )
    return { valid: false, issues: [{ code: "INVALID_PROGRAM" }], warnings }
  const program = value as TrainingProgram
  if (
    !validIso(program.generatedAt) ||
    program.policyVersion !== program.policy.version ||
    program.durationWeeks !== program.weeks.length ||
    program.weeks.length !== request.schedule.durationWeeks ||
    program.goal !== request.preferences.goal ||
    program.datasetFingerprint !== index.fingerprint
  )
    fail("program.header")
  // Scan all numeric payload fields, including diagnostics, without trusting generator output.
  const seenObjects = new Set<object>()
  function numbers(v: unknown, path: string) {
    if (typeof v === "number" && !Number.isFinite(v)) fail(path)
    else if (v && typeof v === "object") {
      if (seenObjects.has(v)) return
      seenObjects.add(v)
      for (const [k, child] of Object.entries(v)) numbers(child, `${path}.${k}`)
    }
  }
  numbers(program, "program")
  const ids = new Set<string>()
  const unique = (id: unknown, path: string) => {
    if (typeof id !== "string" || !id || ids.has(id)) fail(path)
    else ids.add(id)
  }
  unique(program.id, "program.id")
  for (const [wi, w] of program.weeks.entries()) {
    if (
      !isRecord(w) ||
      !Array.isArray(w.sessions) ||
      !Array.isArray(w.targets)
    ) {
      fail(`weeks.${wi}`)
      continue
    }
    unique(w.id, `weeks.${wi}.id`)
    if (
      !validIso(w.start) ||
      Date.parse(w.start) !==
        Date.parse(request.schedule.weekStart) + wi * 7 * DAY_MS ||
      w.sessions.length !== request.schedule.days.length
    )
      fail(`weeks.${wi}.schedule`)
    const dates = new Set<string>()
    for (const [si, session] of w.sessions.entries()) {
      const path = `weeks.${wi}.sessions.${si}`
      if (
        !isRecord(session) ||
        !Array.isArray(session.exercises) ||
        !session.exercises.length
      ) {
        fail(path)
        continue
      }
      unique(session.id, path + ".id")
      if (
        !validIso(session.scheduledAt) ||
        dates.has(session.scheduledAt) ||
        !request.schedule.days.includes(
          (Date.parse(session.scheduledAt) - Date.parse(w.start)) / DAY_MS
        )
      )
        fail(path + ".scheduledAt")
      dates.add(session.scheduledAt)
      const exercises = new Set<string>()
      for (const [ei, e] of session.exercises.entries()) {
        if (
          !isRecord(e) ||
          typeof e.exerciseId !== "string" ||
          !Array.isArray(e.targetMuscles) ||
          !Array.isArray(e.workingSets) ||
          !Array.isArray(e.warmupSets)
        ) {
          fail(path + ".exercises")
          continue
        }
        const record = index.byId.get(e.exerciseId)
        if (!record) {
          issues.push({ code: "UNKNOWN_EXERCISE", path })
          continue
        }
        issues.push(
          ...exclusionReasons(record, request.preferences, program.policy)
        )
        if (
          exercises.has(e.exerciseId) ||
          e.order !== ei ||
          e.workingSets.length < 1 ||
          e.workingSets.length > program.policy.maxSetsPerExercise ||
          !finite(e.restSeconds, 30, 900)
        )
          fail(path + ".exercise")
        exercises.add(e.exerciseId)
        for (const [kind, sets] of [
          ["working", e.workingSets],
          ["warmup", e.warmupSets],
        ] as const)
          for (const set of sets) {
            if (!isRecord(set) || !isRecord(set.targetReps)) {
              fail(path + ".set")
              continue
            }
            unique(set.id, path + ".set.id")
            if (
              !finite(set.targetReps.min, 1, 50) ||
              !Number.isInteger(set.targetReps.min) ||
              !finite(set.targetReps.max, Number(set.targetReps.min), 50) ||
              !Number.isInteger(set.targetReps.max) ||
              !finite(set.targetRir, 0, 10) ||
              !validResistance(set.resistance) ||
              set.side !== "both" ||
              (kind === "warmup"
                ? set.setType !== "warmup"
                : set.setType !== "working" && set.setType !== "backoff")
            ) {
              fail(path + ".set")
              continue
            }
            const resistance =
              set.resistance as import("../domain/types").ResistanceValue
            if (
              resistance.type === "external_load" ||
              resistance.type === "assistance"
            ) {
              const grid = request.preferences.loadGrids?.[e.exerciseId]
              const context = request.preferences.loadContexts?.[e.exerciseId]
              if (
                !grid ||
                !isAchievableLoad(resistance.kg, grid) ||
                !context ||
                context.stationId !== resistance.stationId ||
                context.basis !== resistance.basis ||
                record.metadata.tracking !== resistance.type
              )
                fail(path + ".load")
            }
          }
      }
      // Only evaluate well-shaped prescriptions. Never derive through malformed unknown input.
      if (!issues.length) {
        const duration = estimateSessionDuration(session, index, program.policy)
        if (
          !isRecord(session.duration) ||
          duration.totalSeconds !== session.duration.totalSeconds ||
          !finite(duration.totalSeconds)
        )
          fail(path + ".duration")
        if (
          duration.totalSeconds >
          request.preferences.maxSessionDurationMinutes * 60
        )
          issues.push({
            code: "SESSION_DURATION_INFEASIBLE",
            path,
            context: { seconds: duration.totalSeconds },
          })
      }
    }
  }
  if (!issues.length) {
    const volumes = calculateProgramVolume(program, index)
    const frequencies = calculateProgramFrequency(program, index)
    for (const [wi, w] of program.weeks.entries()) {
      const baseline =
        program.adaptation?.mode === "remaining_week"
          ? calculateHistoryVolume(
              request.history,
              index,
              program.policy,
              Date.parse(w.start),
              Date.parse(program.adaptation.asOf),
              true
            )
          : undefined
      const completedSets =
        program.adaptation?.mode === "remaining_week"
          ? request.history.sessions
              .filter(
                (s) =>
                  Date.parse(s.completedAt) >= Date.parse(w.start) &&
                  Date.parse(s.completedAt) <=
                    Date.parse(program.adaptation!.asOf)
              )
              .reduce(
                (n, s) =>
                  n +
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
      const sets =
        completedSets +
        w.sessions.reduce(
          (n, s) =>
            n + s.exercises.reduce((n, e) => n + e.workingSets.length, 0),
          0
        )
      if (sets > (request.preferences.maxWeeklyWorkingSets ?? Infinity))
        issues.push({ code: "VOLUME_LIMIT", path: `weeks.${wi}` })
      for (const bound of request.preferences.muscleVolumeBounds ?? []) {
        const v =
          volumes[wi].muscles[bound.muscleId].effective +
          (baseline?.[bound.muscleId].effective ?? 0)
        if (
          v < (bound.minimum ?? 0) - 1e-6 ||
          v > (bound.maximum ?? Infinity) + 1e-6
        )
          issues.push({
            code: "VOLUME_LIMIT",
            context: { muscleId: bound.muscleId, volume: v },
          })
      }
      for (const t of w.targets) {
        if (!isRecord(t)) {
          fail(`weeks.${wi}.targets`)
          continue
        }
        if (
          !finite(t.minimum) ||
          !finite(t.preferred, t.minimum) ||
          !finite(t.upperGuideline, t.preferred) ||
          !volumes[wi].muscles[t.muscleId]
        ) {
          fail(`weeks.${wi}.targets`)
          continue
        }
        const volume = volumes[wi].muscles[t.muscleId].effective
        if (volume < t.preferred - 1e-6)
          warnings.push({
            code: "VOLUME_BELOW_TARGET",
            path: `weeks.${wi}`,
            context: {
              muscleId: t.muscleId,
              preferred: t.preferred,
              actual: volume,
            },
          })
        if (volume > t.upperGuideline + 1e-6)
          warnings.push({
            code: "VOLUME_LIMIT",
            path: `weeks.${wi}`,
            context: {
              muscleId: t.muscleId,
              upperGuideline: t.upperGuideline,
              actual: volume,
            },
          })
        if (frequencies[wi].muscles[t.muscleId] < t.preferredExposures)
          warnings.push({
            code: "FREQUENCY_BELOW_TARGET",
            context: { muscleId: t.muscleId },
          })
      }
    }
  }
  return { valid: issues.length === 0, issues, warnings }
}
