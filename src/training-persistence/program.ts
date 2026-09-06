import type {
  MuscleId,
  PlanningIssue,
  ProgressionRecommendation,
  ResistanceValue,
  Score,
  TrainingPolicy,
  TrainingProgram,
} from "../training/domain/types"
import type {
  JsonObject,
  PersistedPlanningIssue,
  PersistedProgramRecord,
  PersistedProgramSnapshot,
  PersistedProgressionRecommendation,
  PersistedResistance,
  PersistedScore,
} from "./schema"

const cloneResistance = (value: ResistanceValue | PersistedResistance) =>
  structuredClone(value)

function persistScore(score: Score): PersistedScore {
  return {
    total: score.total,
    contributions: score.contributions.map((item) => ({ ...item })),
  }
}

function restoreScore(score: PersistedScore): Score {
  return {
    total: score.total,
    contributions: score.contributions.map((item) => ({ ...item })),
  }
}

function persistProgression(
  progression: ProgressionRecommendation
): PersistedProgressionRecommendation {
  return {
    action: progression.action,
    resistance: cloneResistance(progression.resistance) as PersistedResistance,
    targetReps: { ...progression.targetReps },
    confidence: progression.confidence,
    reasons: [...progression.reasons],
    suggestedStrategies: progression.suggestedStrategies
      ? [...progression.suggestedStrategies]
      : undefined,
  }
}

function restoreProgression(
  progression: PersistedProgressionRecommendation
): ProgressionRecommendation {
  return {
    action: progression.action,
    resistance: cloneResistance(progression.resistance) as ResistanceValue,
    targetReps: { ...progression.targetReps },
    confidence: progression.confidence,
    reasons: [...progression.reasons] as ProgressionRecommendation["reasons"],
    suggestedStrategies: progression.suggestedStrategies
      ? ([...progression.suggestedStrategies] as ProgressionRecommendation["suggestedStrategies"])
      : undefined,
  }
}

function persistIssue(issue: PlanningIssue): PersistedPlanningIssue {
  return {
    code: issue.code,
    path: issue.path,
    context: issue.context
      ? (structuredClone(issue.context) as JsonObject)
      : undefined,
  }
}

function restoreIssue(issue: PersistedPlanningIssue): PlanningIssue {
  return {
    code: issue.code as PlanningIssue["code"],
    path: issue.path,
    context: issue.context
      ? (structuredClone(issue.context) as PlanningIssue["context"])
      : undefined,
  }
}

export function toPersistedProgramSnapshot(
  program: TrainingProgram
): PersistedProgramSnapshot {
  return {
    id: program.id,
    engineVersion: program.engineVersion,
    policyVersion: program.policyVersion,
    policy: structuredClone(program.policy) as unknown as JsonObject,
    datasetFingerprint: program.datasetFingerprint,
    generatedAt: program.generatedAt,
    goal: program.goal,
    durationWeeks: program.durationWeeks,
    weeks: program.weeks.map((week) => ({
      id: week.id,
      start: week.start,
      phase: week.phase,
      targets: week.targets.map((target) => ({ ...target })),
      sessions: week.sessions.map((session) => ({
        id: session.id,
        scheduledAt: session.scheduledAt,
        focus: [...session.focus],
        duration: { ...session.duration },
        exercises: session.exercises.map((exercise) => ({
          exerciseId: exercise.exerciseId,
          order: exercise.order,
          workingSets: exercise.workingSets.map((set) => ({
            id: set.id,
            setType: set.setType,
            targetReps: { ...set.targetReps },
            targetRir: set.targetRir,
            resistance: cloneResistance(set.resistance) as PersistedResistance,
            loadAcquisition: set.loadAcquisition,
            side: set.side,
            groupId: set.groupId,
          })),
          warmupSets: exercise.warmupSets.map((set) => ({
            id: set.id,
            setType: set.setType,
            targetReps: { ...set.targetReps },
            targetRir: set.targetRir,
            resistance: cloneResistance(set.resistance) as PersistedResistance,
            loadAcquisition: set.loadAcquisition,
            side: set.side,
            groupId: set.groupId,
          })),
          restSeconds: exercise.restSeconds,
          targetMuscles: [...exercise.targetMuscles],
          rationale: persistScore(exercise.rationale),
          progression: persistProgression(exercise.progression),
        })),
      })),
    })),
    diagnostics: {
      splits: program.diagnostics.splits.map((split) => ({ ...split })),
      candidateCount: program.diagnostics.candidateCount,
      optimizerIterations: program.diagnostics.optimizerIterations,
      selectedSplit: program.diagnostics.selectedSplit,
      score: persistScore(program.diagnostics.score),
      warnings: program.diagnostics.warnings.map(persistIssue),
    },
    adaptation: program.adaptation ? { ...program.adaptation } : undefined,
  }
}

export function toEngineProgramSnapshot(
  snapshot: PersistedProgramSnapshot
): TrainingProgram {
  return {
    id: snapshot.id,
    engineVersion: snapshot.engineVersion,
    policyVersion: snapshot.policyVersion,
    policy: structuredClone(snapshot.policy) as unknown as TrainingPolicy,
    datasetFingerprint: snapshot.datasetFingerprint,
    generatedAt: snapshot.generatedAt,
    goal: snapshot.goal,
    durationWeeks: snapshot.durationWeeks,
    weeks: snapshot.weeks.map((week) => ({
      id: week.id,
      start: week.start,
      phase: week.phase,
      targets: week.targets.map((target) => ({
        ...target,
        muscleId: target.muscleId as MuscleId,
      })),
      sessions: week.sessions.map((session) => ({
        id: session.id,
        scheduledAt: session.scheduledAt,
        focus: [...session.focus] as MuscleId[],
        duration: { ...session.duration },
        exercises: session.exercises.map((exercise) => ({
          exerciseId: exercise.exerciseId,
          order: exercise.order,
          workingSets: exercise.workingSets.map((set) => ({
            id: set.id,
            setType: set.setType,
            targetReps: { ...set.targetReps },
            targetRir: set.targetRir,
            resistance: cloneResistance(set.resistance) as ResistanceValue,
            loadAcquisition: set.loadAcquisition,
            side: set.side,
            groupId: set.groupId,
          })),
          warmupSets: exercise.warmupSets.map((set) => ({
            id: set.id,
            setType: set.setType,
            targetReps: { ...set.targetReps },
            targetRir: set.targetRir,
            resistance: cloneResistance(set.resistance) as ResistanceValue,
            loadAcquisition: set.loadAcquisition,
            side: set.side,
            groupId: set.groupId,
          })),
          restSeconds: exercise.restSeconds,
          targetMuscles: [...exercise.targetMuscles] as MuscleId[],
          rationale: restoreScore(exercise.rationale),
          progression: restoreProgression(exercise.progression),
        })),
      })),
    })),
    diagnostics: {
      splits: snapshot.diagnostics.splits.map((split) => ({ ...split })),
      candidateCount: snapshot.diagnostics.candidateCount,
      optimizerIterations: snapshot.diagnostics.optimizerIterations,
      selectedSplit: snapshot.diagnostics.selectedSplit,
      score: restoreScore(snapshot.diagnostics.score),
      warnings: snapshot.diagnostics.warnings.map(restoreIssue),
    },
    adaptation: snapshot.adaptation ? { ...snapshot.adaptation } : undefined,
  }
}

export function createPersistedProgramRecord(
  program: TrainingProgram,
  options: {
    lifecycle?: PersistedProgramRecord["lifecycle"]
    manualSourceProgramId?: string
    manualRevisionAt?: string
  } = {}
): PersistedProgramRecord {
  const snapshot = toPersistedProgramSnapshot(program)
  const revision = program.adaptation
    ? {
        sourceProgramId: program.adaptation.sourceProgramId,
        reason: program.adaptation.mode,
        asOf: program.adaptation.asOf,
      }
    : options.manualSourceProgramId
      ? {
          sourceProgramId: options.manualSourceProgramId,
          reason: "manual_regeneration" as const,
          asOf: options.manualRevisionAt ?? program.generatedAt,
        }
      : undefined
  return {
    id: program.id,
    lifecycle: options.lifecycle ?? "active",
    createdAt: program.generatedAt,
    snapshot,
    revision,
  }
}
