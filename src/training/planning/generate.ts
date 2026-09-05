import type {
  ExerciseIndex,
  OptimizationInput,
  ProgramGenerationRequest,
  ProgramGenerationResult,
  ProgramOptimizer,
  TrainingProgram,
  TrainingWeek,
} from "../domain/types"
import { DEFAULT_POLICY, ENGINE_VERSION } from "../policy"
import { addDays, compareIds, fingerprint, mean } from "../numeric"
import { createExerciseIndex } from "../data/exercises"
import { analyzeTrainingState } from "../analysis/state"
import { deriveProgramTargets } from "./targets"
import {
  planningEligibility,
  validateGenerationRequest,
} from "../validation/input"
import { validateTrainingProgram } from "../validation/program"
import { beamOptimizer } from "./optimizer"
import { scoreWeek } from "../scoring/scores"
export function preparation(
  request: ProgramGenerationRequest,
  previous?: TrainingProgram,
  index?: ExerciseIndex
): OptimizationInput {
  const policy = structuredClone(request.policy ?? DEFAULT_POLICY)
  const exerciseIndex =
    index ?? createExerciseIndex(request.exercises, request.metadata)
  const initial = analyzeTrainingState(
    request,
    exerciseIndex,
    [],
    policy,
    previous
  )
  const targets = deriveProgramTargets(request, initial, policy)
  const state = analyzeTrainingState(
    request,
    exerciseIndex,
    targets,
    policy,
    previous
  )
  return { request, index: exerciseIndex, state, targets, policy }
}
export function replicateWeek(
  week: TrainingWeek,
  number: number
): TrainingWeek {
  const replace = (id: string) => id.replace(/^week-\d+/, `week-${number}`)
  return {
    ...structuredClone(week),
    id: `week-${number}`,
    start: addDays(week.start, number * 7),
    sessions: week.sessions.map((s) => ({
      ...structuredClone(s),
      id: replace(s.id),
      scheduledAt: addDays(s.scheduledAt, number * 7),
      exercises: s.exercises.map((e) => ({
        ...structuredClone(e),
        workingSets: e.workingSets.map((set) => ({
          ...structuredClone(set),
          id: replace(set.id),
        })),
        warmupSets: e.warmupSets.map((set) => ({
          ...structuredClone(set),
          id: replace(set.id),
        })),
      })),
    })),
  }
}
export function generateTrainingProgram(
  request: ProgramGenerationRequest,
  optimizer: ProgramOptimizer = beamOptimizer
): ProgramGenerationResult {
  const invalid = validateGenerationRequest(request)
  if (invalid.length)
    return { status: "invalid", issues: invalid, suggestions: ["review_input"] }
  const unsupported = planningEligibility(request)
  if (unsupported.length)
    return {
      status: "unsupported",
      issues: unsupported,
      suggestions: ["review_input"],
    }
  const input = preparation(request)
  if (input.index.issues.length)
    return {
      status: "invalid",
      issues: input.index.issues,
      suggestions: ["curate_metadata"],
    }
  const result = optimizer.optimize(input)
  if (!result.week)
    return {
      status: "infeasible",
      issues: [
        {
          code: result.candidates
            ? request.preferences.muscleVolumeBounds?.length ||
              request.preferences.maxWeeklyWorkingSets
              ? "VOLUME_LIMIT"
              : "SESSION_DURATION_INFEASIBLE"
            : "NO_VALID_EXERCISES",
          context: { candidates: result.candidates },
        },
      ],
      suggestions: [
        "add_equipment",
        "increase_duration",
        "relax_volume_bounds",
      ],
    }
  const weeks = Array.from({ length: request.schedule.durationWeeks }, (_, n) =>
    replicateWeek(result.week!, n)
  )
  const program: TrainingProgram = {
    id:
      "program-" +
      fingerprint({
        request: {
          ...request,
          exercises: undefined,
          metadata: undefined,
          schedule: {
            ...request.schedule,
            days: [...request.schedule.days].sort((a, b) => a - b),
          },
          history: {
            ...request.history,
            sessions: [...request.history.sessions].sort((a, b) =>
              compareIds(a.id, b.id)
            ),
          },
        },
        policy: input.policy,
        index: input.index.fingerprint,
      }),
    engineVersion: ENGINE_VERSION,
    policyVersion: input.policy.version,
    policy: structuredClone(input.policy),
    datasetFingerprint: input.index.fingerprint,
    generatedAt: request.now,
    goal: request.preferences.goal,
    durationWeeks: weeks.length,
    weeks,
    diagnostics: {
      splits: result.splits,
      candidateCount: result.candidates,
      optimizerIterations: result.iterations,
      selectedSplit: result.split,
      score: scoreWeek(result.week, { ...input, targets: result.week.targets }),
      warnings: [],
    },
  }
  namespaceProgramIds(program, program.id)
  const validation = validateTrainingProgram(program, request, input.index)
  if (!validation.valid)
    return {
      status: "infeasible",
      issues: validation.issues,
      suggestions: ["review_input", "relax_volume_bounds"],
    }
  const issues = [...input.state.issues, ...validation.warnings]
  const missingLoads = [
    ...new Set(
      weeks.flatMap((w) =>
        w.sessions.flatMap((s) =>
          s.exercises
            .filter((e) => e.progression.action === "calibrate")
            .map((e) => e.exerciseId)
        )
      )
    ),
  ]
  if (missingLoads.length)
    issues.push({
      code: "INSUFFICIENT_HISTORY_FOR_LOAD",
      context: { exerciseIds: missingLoads },
    })
  const selectedIds = new Set(
    weeks.flatMap((w) =>
      w.sessions.flatMap((s) => s.exercises.map((e) => e.exerciseId))
    )
  )
  const missingSpecific =
    request.preferences.strengthExerciseIds?.filter(
      (id) => !selectedIds.has(id)
    ) ?? []
  if (missingSpecific.length)
    issues.push({
      code: "SPECIFICITY_UNAVAILABLE",
      context: { exerciseIds: missingSpecific },
    })
  program.diagnostics.warnings = issues
  const partial = issues.some((i) =>
    [
      "VOLUME_BELOW_TARGET",
      "FREQUENCY_BELOW_TARGET",
      "SPECIFICITY_UNAVAILABLE",
      "VOLUME_LIMIT",
    ].includes(i.code)
  )
  return { status: partial ? "partial" : "success", program, issues }
}
export function evaluateTrainingProgram(
  program: TrainingProgram,
  request: ProgramGenerationRequest,
  index?: ExerciseIndex
) {
  const invalid = validateGenerationRequest(request)
  if (invalid.length) return { valid: false, score: undefined, issues: invalid }
  const input = preparation(request, undefined, index)
  const validation = validateTrainingProgram(program, request, input.index)
  if (!validation.valid)
    return { valid: false, score: undefined, issues: validation.issues }
  const weeks = program.weeks.map((w) =>
    scoreWeek(w, { ...input, policy: program.policy, targets: w.targets })
  )
  return {
    valid: true,
    score: {
      total: mean(weeks.map((w) => w.total)),
      contributions: weeks[0].contributions.map((c, i) => ({
        ...c,
        rawValue: mean(weeks.map((w) => w.contributions[i].rawValue)),
        contribution: mean(weeks.map((w) => w.contributions[i].contribution)),
      })),
    },
    issues: validation.warnings,
  }
}

/** Scope planned identities to a revision, so historical matches cannot cross programs. */
export function namespaceProgramIds(program: TrainingProgram, id: string) {
  const scoped = (value: string) =>
    id + "/" + value.slice(value.indexOf("week-"))
  program.id = id
  for (const week of program.weeks) {
    week.id = scoped(week.id)
    for (const session of week.sessions) {
      session.id = scoped(session.id)
      for (const exercise of session.exercises)
        for (const set of [...exercise.workingSets, ...exercise.warmupSets])
          set.id = scoped(set.id)
    }
  }
}
