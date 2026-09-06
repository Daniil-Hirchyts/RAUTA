import type {
  ExerciseIndex,
  OptimizationInput,
  PlannedExercise,
  PlanningIssue,
  ProgramGenerationRequest,
  Score,
  TrainingProgram,
  TrainingProgramValidationContext,
} from "../domain/types"
import { finite, fingerprint, isRecord, validIso, DAY_MS } from "../numeric"
import { createExerciseIndex, exclusionReasons } from "../data/exercises"
import {
  calculateHistoryVolume,
  calculateProgramFrequency,
  calculateProgramVolume,
  completedWorkingSetUnits,
} from "../analysis/volume"
import { estimateSessionDuration } from "../planning/duration"
import { isAchievableLoad } from "../progression/progression"
import { analyzeTrainingState } from "../analysis/state"
import { deriveProgramTargets } from "../planning/targets"
import { DEFAULT_POLICY, ENGINE_VERSION } from "../policy"
import { prescribeExercise } from "../planning/prescribe"
import { generateSplitCandidates } from "../planning/optimizer"
import { orderExercises, scoreWeek } from "../scoring/scores"
import { MUSCLE_IDS } from "../../types"
import {
  planningEligibility,
  validResistance,
  validateGenerationRequest,
  validatePolicy,
} from "./input"
export function validateTrainingProgram(
  value: unknown,
  request: ProgramGenerationRequest,
  suppliedIndex?: ExerciseIndex,
  validationContext: TrainingProgramValidationContext = {}
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
  const validScore = (value: unknown, path: string): value is Score => {
    if (
      !isRecord(value) ||
      typeof value.total !== "number" ||
      !Number.isFinite(value.total) ||
      !Array.isArray(value.contributions)
    ) {
      fail(path)
      return false
    }
    const factors = new Set<string>()
    let numerator = 0
    let denominator = 0
    for (const contribution of value.contributions) {
      if (
        !isRecord(contribution) ||
        typeof contribution.factor !== "string" ||
        !contribution.factor ||
        factors.has(contribution.factor) ||
        typeof contribution.rawValue !== "number" ||
        !Number.isFinite(contribution.rawValue) ||
        contribution.rawValue < 0 ||
        contribution.rawValue > 1 ||
        typeof contribution.weight !== "number" ||
        !Number.isFinite(contribution.weight) ||
        typeof contribution.contribution !== "number" ||
        !Number.isFinite(contribution.contribution) ||
        Math.abs(
          contribution.contribution -
            contribution.rawValue * contribution.weight
        ) > 1e-9
      ) {
        fail(path)
        return false
      }
      factors.add(contribution.factor)
      numerator += contribution.contribution
      denominator += Math.abs(contribution.weight)
    }
    const expected = denominator ? numerator / denominator : 0
    if (Math.abs(value.total - expected) > 1e-9) {
      fail(path)
      return false
    }
    return true
  }
  if (
    !isRecord(value) ||
    !Array.isArray(value.weeks) ||
    !value.weeks.length ||
    value.weeks.length > 12 ||
    validatePolicy(value.policy).length
  )
    return { valid: false, issues: [{ code: "INVALID_PROGRAM" }], warnings }
  const program = value as TrainingProgram
  const authoritativePolicy = request.policy ??
    (program.adaptation ? undefined : DEFAULT_POLICY)
  if (
    !validIso(program.generatedAt) ||
    program.generatedAt !== request.now ||
    program.engineVersion !== ENGINE_VERSION ||
    program.policyVersion !== program.policy.version ||
    program.durationWeeks !== program.weeks.length ||
    program.weeks.length !== request.schedule.durationWeeks ||
    program.goal !== request.preferences.goal ||
    program.datasetFingerprint !== index.fingerprint
  )
    fail("program.header")
  if (
    authoritativePolicy &&
    fingerprint(program.policy) !== fingerprint(authoritativePolicy)
  )
    fail("program.policy")
  if (
    program.adaptation &&
    (!program.adaptation.sourceProgramId ||
      !validIso(program.adaptation.asOf) ||
      program.adaptation.asOf !== request.now ||
      !["remaining_week", "next_week"].includes(program.adaptation.mode))
  )
    fail("program.adaptation")
  if (program.adaptation && validationContext.sourceProgram) {
    const sourceProgram = validationContext.sourceProgram
    if (
      sourceProgram.id !== program.adaptation.sourceProgramId ||
      validatePolicy(sourceProgram.policy).length ||
      sourceProgram.policyVersion !== program.policyVersion ||
      fingerprint(sourceProgram.policy) !== fingerprint(program.policy) ||
      sourceProgram.datasetFingerprint !== program.datasetFingerprint ||
      !Array.isArray(sourceProgram.weeks) ||
      !sourceProgram.weeks.length
    ) {
      fail("program.adaptation.source")
    } else {
      const adaptedWeek = program.weeks[0]
      const sourceWeek =
        program.adaptation.mode === "remaining_week"
          ? sourceProgram.weeks.find((week) => week.start === adaptedWeek?.start)
          : sourceProgram.weeks.at(-1)
      if (!adaptedWeek || !sourceWeek) {
        fail("program.adaptation.lineage")
      } else {
        const asOf = Date.parse(program.adaptation.asOf)
        const sourceStart = Date.parse(sourceWeek.start)
        const adaptedStart = Date.parse(adaptedWeek.start)
        if (
          program.adaptation.mode === "remaining_week"
            ? adaptedStart !== sourceStart ||
              asOf < sourceStart ||
              asOf >= sourceStart + 7 * DAY_MS ||
              adaptedWeek.sessions.some(
                (session) => Date.parse(session.scheduledAt) <= asOf
              )
            : adaptedStart !== sourceStart + 7 * DAY_MS || asOf >= adaptedStart
        )
          fail("program.adaptation.lineage")

        const sourceSessions = new Map(
          sourceWeek.sessions.map((session) => [session.id, session])
        )
        for (const completed of request.history.sessions) {
          if (!completed.plannedSessionId) continue
          const completedAt = Date.parse(completed.completedAt)
          if (
            completedAt < sourceStart ||
            completedAt >= sourceStart + 7 * DAY_MS
          )
            continue
          const plannedSession = sourceSessions.get(completed.plannedSessionId)
          if (!plannedSession) {
            fail("program.adaptation.completedLineage")
            continue
          }
          for (const completedExercise of completed.exercises) {
            const plannedExercise = plannedSession.exercises.find(
              (exercise) => exercise.exerciseId === completedExercise.exerciseId
            )
            for (const completedSet of completedExercise.sets) {
              if (!completedSet.plannedSetId) continue
              const plannedSets = plannedExercise
                ? [...plannedExercise.workingSets, ...plannedExercise.warmupSets]
                : []
              if (!plannedSets.some((set) => set.id === completedSet.plannedSetId))
                fail("program.adaptation.completedLineage")
            }
          }
        }
      }
    }
  }
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
  const semanticRequest: ProgramGenerationRequest = {
    ...request,
    policy: program.policy,
  }
  const initialState = analyzeTrainingState(
    semanticRequest,
    index,
    [],
    program.policy
  )
  const semanticTargets = deriveProgramTargets(
    semanticRequest,
    initialState,
    program.policy
  )
  const semanticState = analyzeTrainingState(
    semanticRequest,
    index,
    semanticTargets,
    program.policy
  )
  const semanticInput: OptimizationInput = {
    request: semanticRequest,
    index,
    state: semanticState,
    targets: semanticTargets,
    policy: program.policy,
  }
  const expectedPhase = program.adaptation
    ? request.readiness?.perceivedReadiness === "low" &&
      Object.values(semanticState.exercises).filter((e) => e.trend === "declining")
        .length >= 2
      ? "reduced_volume"
      : "base"
    : "base"
  const initialSplitCandidates = !program.adaptation
    ? generateSplitCandidates(semanticInput)
    : []
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
    if (w.phase !== expectedPhase) fail(`weeks.${wi}.phase`)
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
      const sessionIssueStart = issues.length
      if (
        !isRecord(session) ||
        !Array.isArray(session.focus) ||
        !session.focus.length ||
        session.focus.some(
          (muscleId) =>
            typeof muscleId !== "string" ||
            !MUSCLE_IDS.includes(muscleId as (typeof MUSCLE_IDS)[number])
        ) ||
        new Set(session.focus).size !== session.focus.length ||
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
        if (!validScore(e.rationale, path + ".rationale")) continue
        if (
          exercises.has(e.exerciseId) ||
          e.order !== ei ||
          e.workingSets.length < 1 ||
          e.workingSets.length > program.policy.maxSetsPerExercise ||
          !finite(e.restSeconds, 30, 900)
        )
          fail(path + ".exercise")
        exercises.add(e.exerciseId)
        const expectedPrescription = prescribeExercise(
          record,
          e.workingSets.length,
          session.id,
          e.rationale,
          { ...semanticInput, targets: w.targets }
        )
        const prescriptionSemantics = (planned: PlannedExercise) => {
          return {
            exerciseId: planned.exerciseId,
            workingSets: planned.workingSets,
            warmupSets: planned.warmupSets,
            restSeconds: planned.restSeconds,
            targetMuscles: planned.targetMuscles,
            progression: planned.progression,
          }
        }
        if (
          fingerprint(prescriptionSemantics(e as PlannedExercise)) !==
          fingerprint(prescriptionSemantics(expectedPrescription))
        )
          fail(path + ".prescription")
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
      if (issues.length === sessionIssueStart) {
        const expectedOrder = orderExercises(
          session.exercises.map((exercise, order) => ({ ...exercise, order })),
          { ...semanticInput, targets: w.targets }
        ).map((exercise) => exercise.exerciseId)
        if (
          fingerprint(expectedOrder) !==
          fingerprint(session.exercises.map((exercise) => exercise.exerciseId))
        )
          fail(path + ".order")
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
    if (!program.adaptation) {
      const focus = w.sessions.map((session) => session.focus)
      const matchingSplits = initialSplitCandidates.filter(
        (candidate) =>
          fingerprint(candidate.sessions.map((session) => session.focus)) ===
          fingerprint(focus)
      )
      if (!matchingSplits.length) fail(`weeks.${wi}.focus`)
      if (
        wi === 0 &&
        !matchingSplits.some(
          (candidate) => candidate.name === program.diagnostics.selectedSplit
        )
      )
        fail("program.diagnostics.selectedSplit")
    }
  }
  if (!issues.length && !program.adaptation) {
    const initial = analyzeTrainingState(request, index, [], program.policy)
    const expectedTargets = deriveProgramTargets(request, initial, program.policy)
    for (const [wi, week] of program.weeks.entries()) {
      if (week.targets.length !== expectedTargets.length) {
        fail(`weeks.${wi}.targets`)
        continue
      }
      for (const expected of expectedTargets) {
        const actual = week.targets.find((t) => t.muscleId === expected.muscleId)
        if (
          !actual ||
          actual.minimum !== expected.minimum ||
          actual.preferred !== expected.preferred ||
          actual.upperGuideline !== expected.upperGuideline ||
          actual.importance !== expected.importance ||
          actual.preferredExposures !== expected.preferredExposures
        )
          fail(`weeks.${wi}.targets.${expected.muscleId}`)
      }
    }
  }
  if (!issues.length) {
    if (!validScore(program.diagnostics.score, "program.diagnostics.score")) {
      // Shape failure is already recorded above.
    } else {
      const expectedScore = scoreWeek(program.weeks[0], {
        ...semanticInput,
        targets: program.weeks[0].targets,
      })
      if (fingerprint(program.diagnostics.score) !== fingerprint(expectedScore))
        fail("program.diagnostics.score")
    }
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
