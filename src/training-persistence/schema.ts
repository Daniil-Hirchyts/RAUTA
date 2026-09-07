export const TRAINING_PERSISTENCE_SCHEMA_VERSION = 1 as const

export type JsonPrimitive = null | boolean | number | string
export type JsonValue =
  JsonPrimitive | JsonValue[] | { [key: string]: JsonValue }
export type JsonObject = { [key: string]: JsonValue }

export type PersistedResistance =
  | {
      type: "external_load" | "assistance"
      kg: number
      basis: "total" | "per_implement"
      stationId: string
    }
  | { type: "bodyweight" | "band_resistance" | "unknown" }

export type PersistedRepRange = { min: number; max: number }

export type PersistedScore = {
  total: number
  contributions: {
    factor: string
    rawValue: number
    weight: number
    contribution: number
  }[]
}

export type PersistedProgressionRecommendation = {
  action:
    | "calibrate"
    | "hold"
    | "increase_load"
    | "decrease_load"
    | "increase_reps"
    | "reduce_assistance"
    | "increase_assistance"
    | "coarse_grid_progression"
  resistance: PersistedResistance
  targetReps: PersistedRepRange
  confidence: "none" | "low" | "medium" | "high"
  reasons: string[]
  suggestedStrategies?: string[]
}

export type PersistedPlannedSet = {
  id: string
  setType: "warmup" | "working" | "backoff"
  targetReps: PersistedRepRange
  targetRir: number
  resistance: PersistedResistance
  loadAcquisition:
    "calibrate_by_rir" | "history" | "bodyweight" | "band_resistance"
  side: "both"
  groupId?: string
}

export type PersistedPlannedExercise = {
  exerciseId: string
  order: number
  workingSets: PersistedPlannedSet[]
  warmupSets: PersistedPlannedSet[]
  restSeconds: number
  targetMuscles: string[]
  rationale: PersistedScore
  progression: PersistedProgressionRecommendation
}

export type PersistedSessionDuration = {
  generalWarmupSeconds: number
  specificWarmupSeconds: number
  workingSetSeconds: number
  restSeconds: number
  transitionSeconds: number
  totalSeconds: number
  confidence: "none" | "low" | "medium" | "high"
}

export type PersistedPlannedSession = {
  id: string
  scheduledAt: string
  focus: string[]
  exercises: PersistedPlannedExercise[]
  duration: PersistedSessionDuration
}

export type PersistedMuscleTarget = {
  muscleId: string
  minimum: number
  preferred: number
  upperGuideline: number
  importance: number
  preferredExposures: number
}

export type PersistedTrainingWeek = {
  id: string
  start: string
  phase: "base" | "reduced_volume"
  sessions: PersistedPlannedSession[]
  targets: PersistedMuscleTarget[]
}

export type PersistedPlanningIssue = {
  code: string
  path?: string
  context?: JsonObject
}

export type PersistedProgramSnapshot = {
  id: string
  engineVersion: string
  policyVersion: string
  /** Full JSON-safe policy snapshot. It is restored verbatim, never replaced by the current default. */
  policy: JsonObject
  datasetFingerprint: string
  generatedAt: string
  goal:
    | "strength"
    | "hypertrophy"
    | "strength_hypertrophy"
    | "muscular_endurance"
    | "general_fitness"
    | "fat_loss_support"
    | "power"
  durationWeeks: number
  weeks: PersistedTrainingWeek[]
  diagnostics: {
    splits: { name: string; score: number; valid: boolean }[]
    candidateCount: number
    optimizerIterations: number
    selectedSplit: string
    score: PersistedScore
    warnings: PersistedPlanningIssue[]
  }
  adaptation?: {
    sourceProgramId: string
    asOf: string
    mode: "remaining_week" | "next_week"
  }
}

export type PersistedProgramRecord = {
  id: string
  lifecycle: "active" | "completed" | "archived"
  createdAt: string
  snapshot: PersistedProgramSnapshot
  revision?: {
    sourceProgramId: string
    reason: "remaining_week" | "next_week" | "manual_regeneration"
    asOf: string
    /** Actual structured session IDs consumed by this revision. */
    incorporatedSessionIds?: string[]
    /** Source prescriptions replaced by this revision, never performed slots. */
    replacedSessionIds?: string[]
  }
}

export type PersistedCompletedSet = {
  id: string
  plannedSetId?: string
  reps: number
  resistance: PersistedResistance
  rir?: number
  rpe?: number
  completed: boolean
  setType: "warmup" | "working" | "backoff" | "drop" | "other"
  side: "both" | "left" | "right"
  timestamp?: string
}

export type PersistedCompletedExercise = {
  /** Persistence identity for this performed exercise segment. */
  id: string
  /** Canonical exercise catalogue identity actually performed. */
  exerciseId: string
  /** Canonical exercise identity prescribed by the historical plan, if this was a substitution. */
  plannedExerciseId?: string
  exerciseNameSnapshot?: string
  sets: PersistedCompletedSet[]
}

export type PersistedCompletedSession = {
  /** Actual workout identity; never a planned-session ID. */
  id: string
  /**
   * The application workout record this session was performed from, when one
   * exists. It is the join that keeps one training history: a legacy
   * `gym-lib-workouts` record naming the same workout contributes identity and
   * time only until a structured session claims it, and then not at all.
   */
  sourceWorkoutId?: string
  plannedProgramId?: string
  plannedSessionId?: string
  startedAt: string
  completedAt: string
  durationSeconds?: number
  status: "completed" | "partial"
  exercises: PersistedCompletedExercise[]
}

export type PersistedSetTarget = {
  reps: PersistedRepRange
  rir: number
  resistance: PersistedResistance
}

export type PersistedSetObservation = {
  reps?: number
  resistance?: PersistedResistance
  rir?: number
  rpe?: number
  completed: boolean
  timestamp?: string
}

export type PersistedActiveSetDraft = {
  /** Draft identity; distinct from both plannedSetId and the later completed-set ID. */
  id: string
  plannedSetId?: string
  setType: "warmup" | "working" | "backoff" | "drop" | "other"
  side: "both" | "left" | "right"
  target?: PersistedSetTarget
  observation?: PersistedSetObservation
}

export type PersistedActiveExerciseDraft = {
  id: string
  exerciseId: string
  plannedExerciseId?: string
  exerciseNameSnapshot?: string
  sets: PersistedActiveSetDraft[]
}

export type PersistedActiveWorkoutDraft = {
  id: string
  /** The application workout being performed, carried into the completed
   *  session so the two histories never count it twice. */
  sourceWorkoutId?: string
  plannedProgramId?: string
  plannedSessionId?: string
  startedAt: string
  exercises: PersistedActiveExerciseDraft[]
}

export type PersistedLoadGrid =
  | { incrementKg: number; minimumKg?: number; maximumKg?: number }
  | { availableLoadsKg: number[] }

export type PersistedLoadConfiguration = {
  id: string
  exerciseId: string
  stationId: string
  basis: "total" | "per_implement"
  grid: PersistedLoadGrid
}

export type PersistedTrainingSettings = {
  historyCoverage:
    { status: "unknown" } | { status: "complete"; coverageStart: string }
  loadConfigurations: PersistedLoadConfiguration[]
}

/**
 * The legacy completion a finish transition intends to write.
 *
 * Held in the intent rather than recomputed during recovery: a clock read on
 * the way back would give a resumed finish a different duration than the one
 * the person actually saw.
 */
export type PersistedLegacyCompletionIntent = {
  startedAt: string
  completedAt: string
  durationMs: number
  activeCalories: number
  completedExerciseIds: string[]
  healthSyncStatus: "not-requested" | "pending"
}

/**
 * One workout transition that spans stores, written down before it starts.
 *
 * Starting and finishing a workout touch three independently persisted stores,
 * so a process killed between two of those writes leaves the transition half
 * applied. The intent names what was about to happen, with every identity and
 * timestamp it will need already fixed, so recovery can carry the same
 * transition forward to the same result instead of guessing at the wreckage.
 *
 * Nothing here is evidence of training. An intent carries identities, times and
 * the legacy shell's own numbers; the sets that were performed live only in the
 * draft, and recovery never writes one.
 */
export type PersistedTransitionIntent = {
  /** Stable identity for the transition itself, so a retry is recognisable. */
  id: string
  kind: "start" | "finish" | "cancel"
  recordedAt: string
  /** The application workout the transition belongs to. */
  sourceWorkoutId: string
  /** The structured draft the transition creates, closes or discards. */
  draftId?: string
  /** Present only when the workout being started is a planned one. Recovery
   *  reads it to keep lineage; it never invents one that was not here. */
  planned?: { programId: string; sessionId: string }
  /** `start` only: the shell to re-establish, exactly as it was to be created. */
  shell?: {
    workoutName: string
    workoutDate: string
    exerciseIds: string[]
    startedAtMs: number
  }
  /** `finish` only: the one completion instant every step of the transition
   *  uses, so replaying it can never produce a second, different answer. */
  completedAt?: string
  /** `finish` only: the identity the structured session will be written under.
   *  Fixed here so a replayed close cannot add a second session. */
  sessionId?: string
  /** `finish` only: the status decided from coverage when the intent was
   *  recorded, so recovery does not re-judge work it cannot see. */
  status?: "completed" | "partial"
  /** `finish` only: the legacy completion to apply, if it has not landed. */
  legacy?: PersistedLegacyCompletionIntent
}

export type PersistedTrainingStateV1 = {
  schemaVersion: typeof TRAINING_PERSISTENCE_SCHEMA_VERSION
  programs: PersistedProgramRecord[]
  sessions: PersistedCompletedSession[]
  activeWorkout: PersistedActiveWorkoutDraft | null
  activeProgramId?: string
  settings: PersistedTrainingSettings
  /** The cross-store transition in flight, when one is. Absent is the normal
   *  resting state; a value means a transition was interrupted. */
  transition?: PersistedTransitionIntent
}

export type PersistedTrainingStateLatest = PersistedTrainingStateV1

/** Transitional V0 existed only as a pre-release envelope: no coverage claim was representable. */
export type PersistedTrainingStateV0 = {
  schemaVersion: 0
  programs?: PersistedProgramRecord[]
  sessions?: PersistedCompletedSession[]
  activeWorkout?: PersistedActiveWorkoutDraft | null
  activeProgramId?: string
  settings?: { loadConfigurations?: PersistedLoadConfiguration[] }
}

export type TrainingPersistenceIssue = {
  path: string
  message: string
}

export function createEmptyPersistedTrainingState(): PersistedTrainingStateLatest {
  return {
    schemaVersion: TRAINING_PERSISTENCE_SCHEMA_VERSION,
    programs: [],
    sessions: [],
    activeWorkout: null,
    settings: {
      historyCoverage: { status: "unknown" },
      loadConfigurations: [],
    },
  }
}
