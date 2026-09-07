import {
  TRAINING_PERSISTENCE_SCHEMA_VERSION,
  createEmptyPersistedTrainingState,
  type JsonValue,
  type PersistedActiveWorkoutDraft,
  type PersistedCompletedSession,
  type PersistedLoadConfiguration,
  type PersistedPlannedSession,
  type PersistedProgramRecord,
  type PersistedResistance,
  type PersistedTrainingSettings,
  type PersistedTrainingStateLatest,
  type PersistedTrainingStateV0,
  type PersistedTransitionIntent,
  type TrainingPersistenceIssue,
} from "./schema"

const SET_TYPES = new Set(["warmup", "working", "backoff", "drop", "other"])
const PLANNED_SET_TYPES = new Set(["warmup", "working", "backoff"])
const SIDES = new Set(["both", "left", "right"])
const CONFIDENCE = new Set(["none", "low", "medium", "high"])
const LOAD_ACQUISITION = new Set([
  "calibrate_by_rir",
  "history",
  "bodyweight",
  "band_resistance",
])
const GOALS = new Set([
  "strength",
  "hypertrophy",
  "strength_hypertrophy",
  "muscular_endurance",
  "general_fitness",
  "fat_loss_support",
  "power",
])

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value)

const nonEmptyString = (value: unknown): value is string =>
  typeof value === "string" && value.length > 0

const finite = (value: unknown, min = 0, max = 1_000_000): value is number =>
  typeof value === "number" && Number.isFinite(value) && value >= min && value <= max

const integer = (value: unknown, min = 0, max = 1_000_000) =>
  finite(value, min, max) && Number.isInteger(value)

export function isValidIsoTimestamp(value: unknown): value is string {
  if (
    typeof value !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z$/.test(value)
  )
    return false
  const time = Date.parse(value)
  return (
    Number.isFinite(time) &&
    new Date(time).toISOString() ===
      (value.length === 20 ? value.replace("Z", ".000Z") : value)
  )
}

export function isJsonValue(value: unknown, active = new WeakSet<object>()): value is JsonValue {
  if (
    value === null ||
    typeof value === "string" ||
    typeof value === "boolean"
  )
    return true
  if (typeof value === "number") return Number.isFinite(value)
  if (typeof value !== "object") return false
  if (active.has(value)) return false
  active.add(value)
  const valid = Array.isArray(value)
    ? value.every((item) => isJsonValue(item, active))
    : Object.entries(value).every(
        ([key, item]) => key.length > 0 && item !== undefined && isJsonValue(item, active)
      )
  active.delete(value)
  return valid
}

export function isValidPersistedResistance(value: unknown): value is PersistedResistance {
  if (!isRecord(value)) return false
  if (
    value.type === "unknown" ||
    value.type === "bodyweight" ||
    value.type === "band_resistance"
  )
    return Object.keys(value).length === 1
  return (
    (value.type === "external_load" || value.type === "assistance") &&
    finite(value.kg, 0, 2000) &&
    (value.basis === "total" || value.basis === "per_implement") &&
    nonEmptyString(value.stationId)
  )
}

function isValidRepRange(value: unknown) {
  return (
    isRecord(value) &&
    integer(value.min, 1, 1000) &&
    integer(value.max, Number(value.min), 1000)
  )
}

function isValidScore(value: unknown) {
  return (
    isRecord(value) &&
    finite(value.total, -1_000_000, 1_000_000) &&
    Array.isArray(value.contributions) &&
    value.contributions.every(
      (item) =>
        isRecord(item) &&
        nonEmptyString(item.factor) &&
        finite(item.rawValue, -1_000_000, 1_000_000) &&
        finite(item.weight, -1_000_000, 1_000_000) &&
        finite(item.contribution, -1_000_000, 1_000_000)
    )
  )
}

function isValidPlanningIssue(value: unknown) {
  return (
    isRecord(value) &&
    nonEmptyString(value.code) &&
    (value.path === undefined || typeof value.path === "string") &&
    (value.context === undefined || (isRecord(value.context) && isJsonValue(value.context)))
  )
}

function isValidProgression(value: unknown) {
  return (
    isRecord(value) &&
    [
      "calibrate",
      "hold",
      "increase_load",
      "decrease_load",
      "increase_reps",
      "reduce_assistance",
      "increase_assistance",
      "coarse_grid_progression",
    ].includes(String(value.action)) &&
    isValidPersistedResistance(value.resistance) &&
    isValidRepRange(value.targetReps) &&
    CONFIDENCE.has(String(value.confidence)) &&
    Array.isArray(value.reasons) &&
    value.reasons.every(nonEmptyString) &&
    (value.suggestedStrategies === undefined ||
      (Array.isArray(value.suggestedStrategies) &&
        value.suggestedStrategies.every(nonEmptyString)))
  )
}

function isValidPlannedSet(value: unknown) {
  return (
    isRecord(value) &&
    nonEmptyString(value.id) &&
    PLANNED_SET_TYPES.has(String(value.setType)) &&
    isValidRepRange(value.targetReps) &&
    finite(value.targetRir, 0, 10) &&
    isValidPersistedResistance(value.resistance) &&
    LOAD_ACQUISITION.has(String(value.loadAcquisition)) &&
    value.side === "both" &&
    (value.groupId === undefined || nonEmptyString(value.groupId))
  )
}

function isValidPlannedExercise(value: unknown) {
  return (
    isRecord(value) &&
    nonEmptyString(value.exerciseId) &&
    integer(value.order, 0, 1000) &&
    Array.isArray(value.workingSets) &&
    value.workingSets.every(isValidPlannedSet) &&
    Array.isArray(value.warmupSets) &&
    value.warmupSets.every(isValidPlannedSet) &&
    finite(value.restSeconds, 0, 3600) &&
    Array.isArray(value.targetMuscles) &&
    value.targetMuscles.every(nonEmptyString) &&
    isValidScore(value.rationale) &&
    isValidProgression(value.progression)
  )
}

function isValidPlannedSession(value: unknown): value is PersistedPlannedSession {
  const duration = isRecord(value) && isRecord(value.duration) ? value.duration : undefined
  return (
    isRecord(value) &&
    nonEmptyString(value.id) &&
    isValidIsoTimestamp(value.scheduledAt) &&
    Array.isArray(value.focus) &&
    value.focus.every(nonEmptyString) &&
    Array.isArray(value.exercises) &&
    value.exercises.every(isValidPlannedExercise) &&
    duration !== undefined &&
    [
      "generalWarmupSeconds",
      "specificWarmupSeconds",
      "workingSetSeconds",
      "restSeconds",
      "transitionSeconds",
      "totalSeconds",
    ].every((key) => finite(duration[key], 0, 86_400)) &&
    CONFIDENCE.has(String(duration.confidence))
  )
}

function validateProgramRecord(
  value: unknown,
  path: string,
  issues: TrainingPersistenceIssue[]
): value is PersistedProgramRecord {
  if (!isRecord(value)) {
    issues.push({ path, message: "program record must be an object" })
    return false
  }
  const snapshot = isRecord(value.snapshot) ? value.snapshot : undefined
  let valid =
    nonEmptyString(value.id) &&
    ["active", "completed", "archived"].includes(String(value.lifecycle)) &&
    isValidIsoTimestamp(value.createdAt) &&
    snapshot !== undefined &&
    nonEmptyString(snapshot.id) &&
    snapshot.id === value.id &&
    nonEmptyString(snapshot.engineVersion) &&
    nonEmptyString(snapshot.policyVersion) &&
    isRecord(snapshot.policy) &&
    isJsonValue(snapshot.policy) &&
    nonEmptyString(snapshot.policy.version) &&
    snapshot.policy.version === snapshot.policyVersion &&
    nonEmptyString(snapshot.datasetFingerprint) &&
    isValidIsoTimestamp(snapshot.generatedAt) &&
    GOALS.has(String(snapshot.goal)) &&
    integer(snapshot.durationWeeks, 1, 52) &&
    Array.isArray(snapshot.weeks) &&
    snapshot.weeks.length === snapshot.durationWeeks &&
    isRecord(snapshot.diagnostics) &&
    Array.isArray(snapshot.diagnostics.splits) &&
    snapshot.diagnostics.splits.every(
      (split) =>
        isRecord(split) &&
        nonEmptyString(split.name) &&
        finite(split.score, -1_000_000, 1_000_000) &&
        typeof split.valid === "boolean"
    ) &&
    integer(snapshot.diagnostics.candidateCount, 0, 1_000_000) &&
    integer(snapshot.diagnostics.optimizerIterations, 0, 10_000_000) &&
    typeof snapshot.diagnostics.selectedSplit === "string" &&
    isValidScore(snapshot.diagnostics.score) &&
    Array.isArray(snapshot.diagnostics.warnings) &&
    snapshot.diagnostics.warnings.every(isValidPlanningIssue)

  const plannedIds = new Set<string>()
  const sessionIds = new Set<string>()
  const weekIds = new Set<string>()
  if (snapshot && Array.isArray(snapshot.weeks)) {
    for (const [weekIndex, week] of snapshot.weeks.entries()) {
      const weekPath = `${path}.snapshot.weeks.${weekIndex}`
      if (
        !isRecord(week) ||
        !nonEmptyString(week.id) ||
        weekIds.has(week.id) ||
        !isValidIsoTimestamp(week.start) ||
        !["base", "reduced_volume"].includes(String(week.phase)) ||
        !Array.isArray(week.sessions) ||
        !Array.isArray(week.targets)
      ) {
        issues.push({ path: weekPath, message: "invalid persisted training week" })
        valid = false
        continue
      }
      weekIds.add(week.id)
      for (const target of week.targets) {
        if (
          !isRecord(target) ||
          !nonEmptyString(target.muscleId) ||
          !finite(target.minimum, 0, 100) ||
          !finite(target.preferred, Number(target.minimum), 100) ||
          !finite(target.upperGuideline, Number(target.preferred), 100) ||
          !finite(target.importance, 0, 100) ||
          !finite(target.preferredExposures, 0, 20)
        ) {
          issues.push({ path: weekPath + ".targets", message: "invalid muscle target" })
          valid = false
        }
      }
      for (const session of week.sessions) {
        if (!isValidPlannedSession(session) || sessionIds.has(String(session?.id))) {
          issues.push({ path: weekPath + ".sessions", message: "invalid or duplicate planned session" })
          valid = false
          continue
        }
        sessionIds.add(session.id)
        for (const exercise of session.exercises)
          for (const set of [...exercise.workingSets, ...exercise.warmupSets]) {
            if (plannedIds.has(set.id)) {
              issues.push({ path: weekPath + ".sets", message: "duplicate planned set ID" })
              valid = false
            }
            plannedIds.add(set.id)
          }
      }
    }
  }

  if (snapshot && snapshot.adaptation !== undefined) {
    const adaptation = snapshot.adaptation
    if (
      !isRecord(adaptation) ||
      !nonEmptyString(adaptation.sourceProgramId) ||
      !isValidIsoTimestamp(adaptation.asOf) ||
      !["remaining_week", "next_week"].includes(String(adaptation.mode))
    ) {
      issues.push({ path: path + ".snapshot.adaptation", message: "invalid adaptation lineage" })
      valid = false
    }
  }
  if (value.revision !== undefined) {
    const revision = value.revision
    if (
      !isRecord(revision) ||
      !nonEmptyString(revision.sourceProgramId) ||
      !["remaining_week", "next_week", "manual_regeneration"].includes(
        String(revision.reason)
      ) ||
      !isValidIsoTimestamp(revision.asOf) ||
      [revision.incorporatedSessionIds, revision.replacedSessionIds].some(
        (ids) => ids !== undefined && (
          !Array.isArray(ids) || !ids.every(nonEmptyString) ||
          new Set(ids).size !== ids.length
        )
      )
    ) {
      issues.push({ path: path + ".revision", message: "invalid program revision lineage" })
      valid = false
    }
  }
  if (!valid) issues.push({ path, message: "invalid persisted program record" })
  return valid
}

function isValidCompletedSet(value: unknown) {
  return (
    isRecord(value) &&
    nonEmptyString(value.id) &&
    (value.plannedSetId === undefined || nonEmptyString(value.plannedSetId)) &&
    integer(value.reps, value.completed === true ? 1 : 0, 1000) &&
    isValidPersistedResistance(value.resistance) &&
    (value.rir === undefined || finite(value.rir, 0, 10)) &&
    (value.rpe === undefined || finite(value.rpe, 0, 10)) &&
    !(
      finite(value.rir, 0, 10) &&
      finite(value.rpe, 0, 10) &&
      Math.abs(value.rir + value.rpe - 10) > 1
    ) &&
    typeof value.completed === "boolean" &&
    SET_TYPES.has(String(value.setType)) &&
    SIDES.has(String(value.side)) &&
    (value.timestamp === undefined || isValidIsoTimestamp(value.timestamp))
  )
}

function validateCompletedSession(
  value: unknown,
  path: string,
  issues: TrainingPersistenceIssue[],
  globalExerciseIds?: Set<string>,
  globalSetIds?: Set<string>
): value is PersistedCompletedSession {
  if (
    !isRecord(value) ||
    !nonEmptyString(value.id) ||
    !isValidIsoTimestamp(value.startedAt) ||
    !isValidIsoTimestamp(value.completedAt) ||
    Date.parse(value.startedAt) > Date.parse(value.completedAt) ||
    !["completed", "partial"].includes(String(value.status)) ||
    (value.durationSeconds !== undefined && !finite(value.durationSeconds, 0, 86_400)) ||
    !Array.isArray(value.exercises) ||
    (value.sourceWorkoutId !== undefined && !nonEmptyString(value.sourceWorkoutId)) ||
    (value.plannedProgramId !== undefined && !nonEmptyString(value.plannedProgramId)) ||
    (value.plannedSessionId !== undefined && !nonEmptyString(value.plannedSessionId)) ||
    (value.plannedSessionId !== undefined && value.plannedProgramId === undefined)
  ) {
    issues.push({ path, message: "invalid completed session" })
    return false
  }
  let valid = true
  const plannedSetUsage = new Map<string, { exerciseId: string; sides: string[] }>()
  for (const [exerciseIndex, exercise] of value.exercises.entries()) {
    const exercisePath = `${path}.exercises.${exerciseIndex}`
    if (
      !isRecord(exercise) ||
      !nonEmptyString(exercise.id) ||
      !nonEmptyString(exercise.exerciseId) ||
      (exercise.plannedExerciseId !== undefined && !nonEmptyString(exercise.plannedExerciseId)) ||
      (exercise.exerciseNameSnapshot !== undefined && typeof exercise.exerciseNameSnapshot !== "string") ||
      !Array.isArray(exercise.sets)
    ) {
      issues.push({ path: exercisePath, message: "invalid completed exercise" })
      valid = false
      continue
    }
    if (globalExerciseIds?.has(exercise.id)) {
      issues.push({ path: exercisePath + ".id", message: "duplicate completed exercise ID" })
      valid = false
    }
    globalExerciseIds?.add(exercise.id)
    for (const [setIndex, set] of exercise.sets.entries()) {
      const setPath = `${exercisePath}.sets.${setIndex}`
      if (!isValidCompletedSet(set)) {
        issues.push({ path: setPath, message: "invalid completed set" })
        valid = false
        continue
      }
      if (globalSetIds?.has(set.id)) {
        issues.push({ path: setPath + ".id", message: "duplicate completed set ID" })
        valid = false
      }
      globalSetIds?.add(set.id)
      if (
        set.timestamp !== undefined &&
        (Date.parse(set.timestamp) < Date.parse(value.startedAt) ||
          Date.parse(set.timestamp) > Date.parse(value.completedAt))
      ) {
        issues.push({ path: setPath + ".timestamp", message: "set timestamp is outside the session" })
        valid = false
      }
      if (set.plannedSetId) {
        const prior = plannedSetUsage.get(set.plannedSetId)
        if (
          prior &&
          (prior.exerciseId !== exercise.exerciseId ||
            prior.sides.includes(set.side) ||
            prior.sides.includes("both") ||
            set.side === "both")
        ) {
          issues.push({ path: setPath + ".plannedSetId", message: "invalid repeated planned-set linkage" })
          valid = false
        }
        plannedSetUsage.set(set.plannedSetId, {
          exerciseId: exercise.exerciseId,
          sides: [...(prior?.sides ?? []), set.side],
        })
      }
    }
  }
  return valid
}

function isValidSetTarget(value: unknown) {
  return (
    isRecord(value) &&
    isValidRepRange(value.reps) &&
    finite(value.rir, 0, 10) &&
    isValidPersistedResistance(value.resistance)
  )
}

function isValidSetObservation(value: unknown) {
  return (
    isRecord(value) &&
    typeof value.completed === "boolean" &&
    (value.reps === undefined || integer(value.reps, 0, 1000)) &&
    (value.resistance === undefined || isValidPersistedResistance(value.resistance)) &&
    (value.rir === undefined || finite(value.rir, 0, 10)) &&
    (value.rpe === undefined || finite(value.rpe, 0, 10)) &&
    !(
      finite(value.rir, 0, 10) &&
      finite(value.rpe, 0, 10) &&
      Math.abs(value.rir + value.rpe - 10) > 1
    ) &&
    (value.timestamp === undefined || isValidIsoTimestamp(value.timestamp))
  )
}

function validateActiveWorkout(
  value: unknown,
  path: string,
  issues: TrainingPersistenceIssue[]
): value is PersistedActiveWorkoutDraft {
  if (
    !isRecord(value) ||
    !nonEmptyString(value.id) ||
    !isValidIsoTimestamp(value.startedAt) ||
    (value.sourceWorkoutId !== undefined && !nonEmptyString(value.sourceWorkoutId)) ||
    (value.plannedProgramId !== undefined && !nonEmptyString(value.plannedProgramId)) ||
    (value.plannedSessionId !== undefined && !nonEmptyString(value.plannedSessionId)) ||
    (value.plannedSessionId !== undefined && value.plannedProgramId === undefined) ||
    !Array.isArray(value.exercises)
  ) {
    issues.push({ path, message: "invalid active workout draft" })
    return false
  }
  let valid = true
  const exerciseIds = new Set<string>()
  const setIds = new Set<string>()
  for (const [exerciseIndex, exercise] of value.exercises.entries()) {
    const exercisePath = `${path}.exercises.${exerciseIndex}`
    if (
      !isRecord(exercise) ||
      !nonEmptyString(exercise.id) ||
      exerciseIds.has(String(exercise.id)) ||
      !nonEmptyString(exercise.exerciseId) ||
      (exercise.plannedExerciseId !== undefined && !nonEmptyString(exercise.plannedExerciseId)) ||
      (exercise.exerciseNameSnapshot !== undefined && typeof exercise.exerciseNameSnapshot !== "string") ||
      !Array.isArray(exercise.sets)
    ) {
      issues.push({ path: exercisePath, message: "invalid or duplicate active exercise" })
      valid = false
      continue
    }
    exerciseIds.add(exercise.id)
    for (const [setIndex, set] of exercise.sets.entries()) {
      const setPath = `${exercisePath}.sets.${setIndex}`
      if (
        !isRecord(set) ||
        !nonEmptyString(set.id) ||
        setIds.has(String(set.id)) ||
        (set.plannedSetId !== undefined && !nonEmptyString(set.plannedSetId)) ||
        !SET_TYPES.has(String(set.setType)) ||
        !SIDES.has(String(set.side)) ||
        (set.target !== undefined && !isValidSetTarget(set.target)) ||
        (set.observation !== undefined && !isValidSetObservation(set.observation))
      ) {
        issues.push({ path: setPath, message: "invalid or duplicate active set" })
        valid = false
        continue
      }
      setIds.add(set.id)
      if (
        isRecord(set.observation) &&
        set.observation.timestamp !== undefined &&
        Date.parse(String(set.observation.timestamp)) < Date.parse(value.startedAt)
      ) {
        issues.push({ path: setPath + ".observation.timestamp", message: "observation predates workout" })
        valid = false
      }
    }
  }
  return valid
}

function validateLoadConfiguration(
  value: unknown,
  path: string,
  issues: TrainingPersistenceIssue[]
): value is PersistedLoadConfiguration {
  if (
    !isRecord(value) ||
    !nonEmptyString(value.id) ||
    !nonEmptyString(value.exerciseId) ||
    !nonEmptyString(value.stationId) ||
    (value.mode !== undefined &&
      value.mode !== "external_load" &&
      value.mode !== "assistance") ||
    !["total", "per_implement"].includes(String(value.basis)) ||
    !isRecord(value.grid)
  ) {
    issues.push({ path, message: "invalid load configuration" })
    return false
  }
  const grid = value.grid
  const valid = Array.isArray(grid.availableLoadsKg)
    ? grid.availableLoadsKg.length > 0 &&
      grid.availableLoadsKg.length <= 1000 &&
      grid.availableLoadsKg.every((load) => finite(load, 0, 2000)) &&
      new Set(grid.availableLoadsKg).size === grid.availableLoadsKg.length
    : finite(grid.incrementKg, 0.001, 100) &&
      (grid.minimumKg === undefined || finite(grid.minimumKg, 0, 2000)) &&
      (grid.maximumKg === undefined ||
        finite(grid.maximumKg, Number(grid.minimumKg ?? 0), 2000))
  if (!valid) issues.push({ path: path + ".grid", message: "invalid load grid" })
  return valid
}

/**
 * The transition journal.
 *
 * An intent is a promise about identities and instants, so every one it names
 * has to be there and well formed before recovery is allowed to act on it. A
 * malformed intent is dropped rather than half-read: the draft it refers to
 * still holds the observations, and the reconciliation layer closes that state
 * safely on its own.
 */
function validateTransitionIntent(
  value: unknown,
  path: string,
  issues: TrainingPersistenceIssue[]
): value is PersistedTransitionIntent {
  const fail = (message: string) => {
    issues.push({ path, message })
    return false
  }
  if (
    !isRecord(value) ||
    !nonEmptyString(value.id) ||
    (value.kind !== "start" && value.kind !== "finish" && value.kind !== "cancel") ||
    !isValidIsoTimestamp(value.recordedAt) ||
    !nonEmptyString(value.sourceWorkoutId) ||
    (value.draftId !== undefined && !nonEmptyString(value.draftId))
  )
    return fail("invalid transition intent")

  if (value.planned !== undefined) {
    const planned = value.planned
    if (
      !isRecord(planned) ||
      !nonEmptyString(planned.programId) ||
      !nonEmptyString(planned.sessionId)
    )
      return fail("invalid transition planned lineage")
  }

  if (value.shell !== undefined) {
    const shell = value.shell
    if (
      !isRecord(shell) ||
      typeof shell.workoutName !== "string" ||
      typeof shell.workoutDate !== "string" ||
      !Array.isArray(shell.exerciseIds) ||
      !shell.exerciseIds.every((id) => nonEmptyString(id)) ||
      !Number.isFinite(shell.startedAtMs) ||
      Number(shell.startedAtMs) <= 0
    )
      return fail("invalid transition shell")
  }

  if (value.kind === "start" && (!value.shell ||
      !isRecord(value.shell) || !Array.isArray(value.shell.exerciseIds) ||
      value.shell.exerciseIds.length === 0 ||
      new Set(value.shell.exerciseIds).size !== value.shell.exerciseIds.length ||
      Date.parse(value.recordedAt as string) !== value.shell.startedAtMs))
    return fail("invalid start transition")
  if (value.kind === "cancel" &&
      (!isValidIsoTimestamp(value.completedAt) || !nonEmptyString(value.sessionId)))
    return fail("invalid cancel transition")

  if (value.kind === "finish") {
    if (
      !isValidIsoTimestamp(value.completedAt) ||
      !nonEmptyString(value.sessionId) ||
      (value.status !== "completed" && value.status !== "partial")
    )
      return fail("invalid finish transition")
    const legacy = value.legacy
    if (
      !isRecord(legacy) ||
      !isValidIsoTimestamp(legacy.startedAt) ||
      !isValidIsoTimestamp(legacy.completedAt) ||
      legacy.completedAt !== value.completedAt ||
      Date.parse(legacy.startedAt as string) > Date.parse(legacy.completedAt as string) ||
      !finite(legacy.durationMs, 0, 1000 * 60 * 60 * 24 * 7) ||
      !finite(legacy.activeCalories, 0, 100000) ||
      !Array.isArray(legacy.completedExerciseIds) ||
      !legacy.completedExerciseIds.every((id) => nonEmptyString(id)) ||
      (legacy.healthSyncStatus !== "not-requested" &&
        legacy.healthSyncStatus !== "pending")
    )
      return fail("invalid finish transition completion")
  }
  return true
}

function validateSettings(
  value: unknown,
  path: string,
  issues: TrainingPersistenceIssue[]
): value is PersistedTrainingSettings {
  if (!isRecord(value) || !isRecord(value.historyCoverage) || !Array.isArray(value.loadConfigurations)) {
    issues.push({ path, message: "invalid training settings" })
    return false
  }
  const coverage = value.historyCoverage
  let valid =
    coverage.status === "unknown" ||
    (coverage.status === "complete" && isValidIsoTimestamp(coverage.coverageStart))
  if (!valid)
    issues.push({ path: path + ".historyCoverage", message: "invalid history coverage" })
  const ids = new Set<string>()
  const contexts = new Set<string>()
  for (const [index, configuration] of value.loadConfigurations.entries()) {
    const configPath = `${path}.loadConfigurations.${index}`
    if (!validateLoadConfiguration(configuration, configPath, issues)) {
      valid = false
      continue
    }
    const contextKey = `${configuration.exerciseId}\u0000${configuration.stationId}\u0000${configuration.basis}\u0000${configuration.mode ?? "external_load"}`
    if (ids.has(configuration.id) || contexts.has(contextKey)) {
      issues.push({ path: configPath, message: "duplicate load configuration" })
      valid = false
    }
    ids.add(configuration.id)
    contexts.add(contextKey)
  }
  // A selection is a preference, not evidence. It is checked for shape only:
  // one that no longer names a saved station resolves to the equipment default
  // rather than taking the rest of the settings down with it.
  if (value.activeLoadConfigurations !== undefined) {
    const active = value.activeLoadConfigurations
    if (
      !isRecord(active) ||
      Object.entries(active).some(
        ([exerciseId, configurationId]) =>
          !nonEmptyString(exerciseId) || !nonEmptyString(configurationId)
      )
    ) {
      issues.push({
        path: path + ".activeLoadConfigurations",
        message: "invalid active load configuration selection",
      })
      valid = false
    }
  }
  return valid
}

export function validatePersistedTrainingState(
  value: unknown
): TrainingPersistenceIssue[] {
  const issues: TrainingPersistenceIssue[] = []
  if (!isRecord(value)) return [{ path: "state", message: "training persistence must be an object" }]
  if (value.schemaVersion !== TRAINING_PERSISTENCE_SCHEMA_VERSION)
    return [{ path: "schemaVersion", message: "unsupported training persistence schema version" }]
  if (!Array.isArray(value.programs) || !Array.isArray(value.sessions)) {
    return [{ path: "state", message: "programs and sessions must be arrays" }]
  }

  const programIds = new Set<string>()
  const programs = new Map<string, PersistedProgramRecord>()
  for (const [index, record] of value.programs.entries()) {
    const path = `programs.${index}`
    if (!validateProgramRecord(record, path, issues)) continue
    if (programIds.has(record.id)) issues.push({ path: path + ".id", message: "duplicate program ID" })
    programIds.add(record.id)
    programs.set(record.id, record)
  }

  for (const [index, record] of value.programs.entries()) {
    if (!isRecord(record) || !nonEmptyString(record.id)) continue
    const revision = isRecord(record.revision) ? record.revision : undefined
    const sourceId = nonEmptyString(revision?.sourceProgramId)
      ? revision.sourceProgramId
      : isRecord(record.snapshot) && isRecord(record.snapshot.adaptation) &&
          nonEmptyString(record.snapshot.adaptation.sourceProgramId)
        ? record.snapshot.adaptation.sourceProgramId
        : undefined
    if (sourceId && (sourceId === record.id || !programs.has(sourceId)))
      issues.push({ path: `programs.${index}.revision`, message: "program revision source is missing or self-referential" })
  }

  if (value.activeProgramId !== undefined) {
    if (!nonEmptyString(value.activeProgramId) || !programs.has(value.activeProgramId))
      issues.push({ path: "activeProgramId", message: "active program does not exist" })
  }

  const sessionIds = new Set<string>()
  const completedExerciseIds = new Set<string>()
  const completedSetIds = new Set<string>()
  for (const [index, session] of value.sessions.entries()) {
    const path = `sessions.${index}`
    if (!validateCompletedSession(session, path, issues, completedExerciseIds, completedSetIds)) continue
    if (sessionIds.has(session.id)) issues.push({ path: path + ".id", message: "duplicate completed session ID" })
    sessionIds.add(session.id)
    if (session.plannedProgramId) {
      const program = programs.get(session.plannedProgramId)
      if (!program) {
        issues.push({ path: path + ".plannedProgramId", message: "planned program does not exist" })
        continue
      }
      const plannedSession = program.snapshot.weeks
        .flatMap((week) => week.sessions)
        .find((planned) => planned.id === session.plannedSessionId)
      if (!plannedSession) {
        issues.push({ path: path + ".plannedSessionId", message: "planned session does not exist in program snapshot" })
        continue
      }
      const plannedExerciseIds = new Set(plannedSession.exercises.map((exercise) => exercise.exerciseId))
      const plannedSetIds = new Set(
        plannedSession.exercises.flatMap((exercise) =>
          [...exercise.workingSets, ...exercise.warmupSets].map((set) => set.id)
        )
      )
      for (const exercise of session.exercises) {
        if (exercise.plannedExerciseId && !plannedExerciseIds.has(exercise.plannedExerciseId))
          issues.push({ path: path + ".plannedExerciseId", message: "planned exercise lineage is absent from snapshot" })
        for (const set of exercise.sets)
          if (set.plannedSetId && !plannedSetIds.has(set.plannedSetId))
            issues.push({ path: path + ".plannedSetId", message: "planned set lineage is absent from snapshot" })
      }
    }
  }

  if (value.activeWorkout !== null && value.activeWorkout !== undefined) {
    const activeWorkout = value.activeWorkout
    if (validateActiveWorkout(activeWorkout, "activeWorkout", issues) && activeWorkout.plannedProgramId) {
      const program = programs.get(activeWorkout.plannedProgramId)
      if (!program)
        issues.push({ path: "activeWorkout.plannedProgramId", message: "planned program does not exist" })
      else if (
        !program.snapshot.weeks
          .flatMap((week) => week.sessions)
          .some((session) => session.id === activeWorkout.plannedSessionId)
      )
        issues.push({ path: "activeWorkout.plannedSessionId", message: "planned session does not exist" })
    }
  }

  if (value.transition !== undefined)
    validateTransitionIntent(value.transition, "transition", issues)

  validateSettings(value.settings, "settings", issues)
  return issues
}

export class TrainingPersistenceValidationError extends Error {
  readonly issues: TrainingPersistenceIssue[]

  constructor(issues: TrainingPersistenceIssue[]) {
    super(issues.map((issue) => `${issue.path}: ${issue.message}`).join("; "))
    this.issues = issues
    this.name = "TrainingPersistenceValidationError"
  }
}

function normalize<T extends PersistedTrainingStateLatest>(state: T): T {
  const copy = structuredClone(state)
  copy.programs.sort((left, right) => left.id.localeCompare(right.id))
  copy.sessions.sort((left, right) =>
    left.id === right.id ? left.startedAt.localeCompare(right.startedAt) : left.id.localeCompare(right.id)
  )
  copy.settings.loadConfigurations.sort((left, right) => left.id.localeCompare(right.id))
  if (copy.settings.activeLoadConfigurations)
    copy.settings.activeLoadConfigurations = Object.fromEntries(
      Object.entries(copy.settings.activeLoadConfigurations).sort(
        ([left], [right]) => left.localeCompare(right)
      )
    )
  return copy
}

export function normalizePersistedTrainingState(
  state: PersistedTrainingStateLatest
): PersistedTrainingStateLatest {
  return normalize(state)
}

export function migratePersistedTrainingState(value: unknown): PersistedTrainingStateLatest {
  if (value === undefined || value === null) return createEmptyPersistedTrainingState()
  if (!isRecord(value))
    throw new TrainingPersistenceValidationError([
      { path: "state", message: "training persistence must be an object" },
    ])

  let migrated: PersistedTrainingStateLatest
  if (value.schemaVersion === TRAINING_PERSISTENCE_SCHEMA_VERSION) {
    migrated = structuredClone(value) as PersistedTrainingStateLatest
  } else if (value.schemaVersion === 0) {
    const legacy = structuredClone(value) as PersistedTrainingStateV0
    migrated = {
      schemaVersion: TRAINING_PERSISTENCE_SCHEMA_VERSION,
      programs: Array.isArray(legacy.programs) ? legacy.programs : [],
      sessions: Array.isArray(legacy.sessions) ? legacy.sessions : [],
      activeWorkout: legacy.activeWorkout ?? null,
      activeProgramId: legacy.activeProgramId,
      settings: {
        historyCoverage: { status: "unknown" },
        loadConfigurations: Array.isArray(legacy.settings?.loadConfigurations)
          ? legacy.settings.loadConfigurations
          : [],
      },
    }
  } else {
    throw new TrainingPersistenceValidationError([
      { path: "schemaVersion", message: "unsupported training persistence schema version" },
    ])
  }

  const normalized = normalize(migrated)
  const issues = validatePersistedTrainingState(normalized)
  if (issues.length) throw new TrainingPersistenceValidationError(issues)
  return normalized
}

/** Fail-safe hydration: corrupt payloads cannot crash startup or be reinterpreted as observations. */
export function recoverPersistedTrainingState(value: unknown): {
  state: PersistedTrainingStateLatest
  issues: TrainingPersistenceIssue[]
} {
  try {
    return { state: migratePersistedTrainingState(value), issues: [] }
  } catch (error) {
    const issues =
      error instanceof TrainingPersistenceValidationError
        ? error.issues
        : [{ path: "state", message: "unknown persistence error" }]
    if (!isRecord(value) || ![0, 1].includes(Number(value.schemaVersion)))
      return { state: createEmptyPersistedTrainingState(), issues }

    const candidate = value.schemaVersion === 0
      ? {
          schemaVersion: 1 as const,
          programs: Array.isArray(value.programs) ? value.programs : [],
          sessions: Array.isArray(value.sessions) ? value.sessions : [],
          activeWorkout: value.activeWorkout ?? null,
          activeProgramId: typeof value.activeProgramId === "string" ? value.activeProgramId : undefined,
          settings: {
            historyCoverage: { status: "unknown" as const },
            loadConfigurations:
              isRecord(value.settings) && Array.isArray(value.settings.loadConfigurations)
                ? value.settings.loadConfigurations
                : [],
          },
        }
      : value

    const recovered = createEmptyPersistedTrainingState()
    const rawPrograms = Array.isArray(candidate.programs) ? candidate.programs : []
    for (const item of rawPrograms) {
      const itemIssues: TrainingPersistenceIssue[] = []
      if (validateProgramRecord(item, "program", itemIssues)) recovered.programs.push(structuredClone(item))
    }
    const programIds = new Set(recovered.programs.map((program) => program.id))
    recovered.programs = recovered.programs.filter(
      (program) => {
        const sourceProgramId =
          program.revision?.sourceProgramId ??
          program.snapshot.adaptation?.sourceProgramId
        return (
          !sourceProgramId ||
          (sourceProgramId !== program.id && programIds.has(sourceProgramId))
        )
      }
    )
    const finalProgramIds = new Set(recovered.programs.map((program) => program.id))
    const rawSessions = Array.isArray(candidate.sessions) ? candidate.sessions : []
    const sessionIds = new Set<string>()
    const exerciseIds = new Set<string>()
    const setIds = new Set<string>()
    for (const item of rawSessions) {
      const itemIssues: TrainingPersistenceIssue[] = []
      const localExerciseIds = new Set<string>()
      const localSetIds = new Set<string>()
      if (
        !validateCompletedSession(
          item,
          "session",
          itemIssues,
          localExerciseIds,
          localSetIds
        ) ||
        sessionIds.has(item.id) ||
        [...localExerciseIds].some((id) => exerciseIds.has(id)) ||
        [...localSetIds].some((id) => setIds.has(id))
      )
        continue

      if (item.plannedProgramId) {
        const program = recovered.programs.find(
          (record) => record.id === item.plannedProgramId
        )
        const plannedSession = program?.snapshot.weeks
          .flatMap((week) => week.sessions)
          .find((session) => session.id === item.plannedSessionId)
        if (!program || !plannedSession) continue
        const plannedExerciseIds = new Set(
          plannedSession.exercises.map((exercise) => exercise.exerciseId)
        )
        const plannedSetIds = new Set(
          plannedSession.exercises.flatMap((exercise) =>
            [...exercise.workingSets, ...exercise.warmupSets].map(
              (set) => set.id
            )
          )
        )
        if (
          item.exercises.some(
            (exercise) =>
              (exercise.plannedExerciseId !== undefined &&
                !plannedExerciseIds.has(exercise.plannedExerciseId)) ||
              exercise.sets.some(
                (set) =>
                  set.plannedSetId !== undefined &&
                  !plannedSetIds.has(set.plannedSetId)
              )
          )
        )
          continue
      } else if (item.plannedSessionId) {
        continue
      }

      sessionIds.add(item.id)
      localExerciseIds.forEach((id) => exerciseIds.add(id))
      localSetIds.forEach((id) => setIds.add(id))
      recovered.sessions.push(structuredClone(item))
    }
    const activeWorkout = candidate.activeWorkout
    if (activeWorkout && validateActiveWorkout(activeWorkout, "activeWorkout", [])) {
      const plannedProgramId = activeWorkout.plannedProgramId
      const validLineage =
        !plannedProgramId ||
        (finalProgramIds.has(plannedProgramId) &&
          recovered.programs
            .find((program) => program.id === plannedProgramId)
            ?.snapshot.weeks.flatMap((week) => week.sessions)
            .some((session) => session.id === activeWorkout.plannedSessionId))
      if (validLineage) recovered.activeWorkout = structuredClone(activeWorkout)
    }
    if (
      typeof candidate.activeProgramId === "string" &&
      finalProgramIds.has(candidate.activeProgramId)
    )
      recovered.activeProgramId = candidate.activeProgramId
    // A corrupt intent is simply not carried over: recovery then falls back to
    // reconciling the restored stores, which preserves observations anyway.
    if (
      candidate.transition !== undefined &&
      validateTransitionIntent(candidate.transition, "transition", [])
    )
      recovered.transition = structuredClone(candidate.transition)
    const settingsIssues: TrainingPersistenceIssue[] = []
    if (validateSettings(candidate.settings, "settings", settingsIssues))
      recovered.settings = structuredClone(candidate.settings)
    const normalized = normalize(recovered)
    const recoveredIssues = validatePersistedTrainingState(normalized)
    return recoveredIssues.length
      ? {
          state: createEmptyPersistedTrainingState(),
          issues: [...issues, ...recoveredIssues],
        }
      : { state: normalized, issues }
  }
}

function stableJson(value: JsonValue): string {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`
  if (value !== null && typeof value === "object")
    return `{${Object.entries(value)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, item]) => `${JSON.stringify(key)}:${stableJson(item)}`)
      .join(",")}}`
  return JSON.stringify(value)
}

function omitUndefined(value: unknown): JsonValue {
  if (Array.isArray(value)) return value.map(omitUndefined)
  if (value !== null && typeof value === "object")
    return Object.fromEntries(
      Object.entries(value)
        .filter(([, item]) => item !== undefined)
        .map(([key, item]) => [key, omitUndefined(item)])
    )
  return value as JsonValue
}

export function serializePersistedTrainingState(state: PersistedTrainingStateLatest): string {
  const normalized = normalizePersistedTrainingState(state)
  const issues = validatePersistedTrainingState(normalized)
  if (issues.length) throw new TrainingPersistenceValidationError(issues)
  const jsonSafe = omitUndefined(normalized)
  if (!isJsonValue(jsonSafe))
    throw new TrainingPersistenceValidationError([
      { path: "state", message: "training persistence is not JSON-safe" },
    ])
  return stableJson(jsonSafe)
}
