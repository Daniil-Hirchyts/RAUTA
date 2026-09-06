import type { ExerciseSummary, MuscleId } from "../../types"
export type { ExerciseSummary, MuscleId }
export type TrainingGoal =
  | "hypertrophy"
  | "strength"
  | "general_fitness"
  | "muscular_endurance"
  | "strength_hypertrophy"
  | "fat_loss_support"
  | "power"
export type Experience = "beginner" | "intermediate" | "advanced"
export type Confidence = "none" | "low" | "medium" | "high"
export type MovementPattern =
  | "horizontal_push"
  | "horizontal_pull"
  | "vertical_push"
  | "vertical_pull"
  | "squat"
  | "hinge"
  | "lunge"
  | "knee_extension"
  | "knee_flexion"
  | "hip_extension"
  | "hip_abduction"
  | "hip_adduction"
  | "elbow_flexion"
  | "elbow_extension"
  | "shoulder_abduction"
  | "calf_raise"
  | "trunk_flexion"
  | "trunk_extension"
  | "trunk_rotation"
  | "anti_extension"
  | "carry"
  | "unknown"
export type PlanningIssueCode =
  | "INVALID_INPUT"
  | "UNSUPPORTED_POPULATION"
  | "UNSUPPORTED_GOAL"
  | "INVALID_EXERCISE_DATA"
  | "UNKNOWN_EXERCISE"
  | "EXCLUDED_EXERCISE"
  | "UNAVAILABLE_EQUIPMENT"
  | "UNSUPPORTED_EXERCISE"
  | "NO_VALID_EXERCISES"
  | "SESSION_DURATION_INFEASIBLE"
  | "INVALID_PROGRAM"
  | "VOLUME_LIMIT"
  | "VOLUME_BELOW_TARGET"
  | "FREQUENCY_BELOW_TARGET"
  | "INSUFFICIENT_HISTORY_FOR_LOAD"
  | "INCOMPLETE_HISTORY"
  | "STALE_HISTORY"
  | "LOW_METADATA_CONFIDENCE"
  | "MISSED_VOLUME_DROPPED"
  | "REDUCED_VOLUME"
  | "SPECIFICITY_UNAVAILABLE"
export type PlanningIssue = {
  code: PlanningIssueCode
  path?: string
  context?: Record<string, string | number | boolean | string[]>
}
export type UserTrainingProfile = {
  age: number
  bodyWeightKg?: number
  heightCm?: number
  trainingAgeMonths?: number
  trainingExperience: Experience
  health:
    | { status: "healthy" }
    | {
        status: "unsupported"
        reasons: (
          | "medical_condition"
          | "active_injury"
          | "rehabilitation"
          | "pregnancy"
          | "other"
        )[]
      }
}
export type VolumeRange = {
  minimum: number
  preferred: number
  upperGuideline: number
}
export type LoadGrid =
  | { incrementKg: number; minimumKg?: number; maximumKg?: number }
  | { availableLoadsKg: number[] }
export type PlanningPreferences = {
  goal: TrainingGoal
  availableEquipment: string[]
  preferredExerciseIds?: string[]
  dislikedExerciseIds?: string[]
  excludedExerciseIds?: string[]
  excludedPatterns?: MovementPattern[]
  strengthExerciseIds?: string[]
  priorityMuscles?: {
    muscleId: MuscleId
    level: "low" | "normal" | "high" | "specialization"
  }[]
  preferredSessionDurationMinutes?: number
  maxSessionDurationMinutes: number
  maxWeeklyWorkingSets?: number
  muscleVolumeBounds?: {
    muscleId: MuscleId
    minimum?: number
    maximum?: number
  }[]
  loadGrids?: Record<string, LoadGrid>
  /** Station and basis must match logs before prescribing kg; no cross-machine transfer. */
  loadContexts?: Record<
    string,
    { stationId: string; basis: "total" | "per_implement" }
  >
}
export type TrainingSchedule = {
  weekStart: string
  days: number[]
  durationWeeks: number
}
export type ResistanceValue =
  | {
      type: "external_load" | "assistance"
      kg: number
      basis: "total" | "per_implement"
      stationId: string
    }
  | { type: "bodyweight" | "band_resistance" | "unknown" }
export type SetType = "warmup" | "working" | "backoff" | "drop" | "other"
export type CompletedSet = {
  id: string
  plannedSetId?: string
  reps: number
  resistance: ResistanceValue
  rir?: number
  rpe?: number
  completed: boolean
  setType: SetType
  /** both = paired limbs (3 sets each side = 3 records); left/right = half group credit. */
  side: "both" | "left" | "right"
  timestamp?: string
}
export type CompletedExercise = { exerciseId: string; sets: CompletedSet[] }
export type CompletedSession = {
  id: string
  plannedSessionId?: string
  startedAt: string
  completedAt: string
  durationSeconds?: number
  status: "completed" | "partial"
  exercises: CompletedExercise[]
}
export type TrainingHistory = {
  sessions: CompletedSession[]
  coverage: "complete" | "unknown"
  coverageStart?: string
}
export type Readiness = {
  perceivedReadiness?: "normal" | "low"
  soreness?: { muscleId: MuscleId; level: "none" | "mild" | "high" }[]
  pain?: boolean
}
export type MuscleParticipation = {
  muscleId: MuscleId
  relativeInvolvement: number
}
export type EffectiveSetRole = {
  muscleId: MuscleId
  role: "direct" | "indirect" | "incidental"
  provenance: "rule" | "curated"
}
export type AutomaticProgramming =
  | "allowed"
  | "specialized_only"
  | "manual_only"
export type ExerciseMetadata = {
  exerciseId: string
  exerciseType:
    | "resistance"
    | "isometric"
    | "stretch"
    | "mobility"
    | "conditioning"
    | "power"
    | "unknown"
  movementPatterns: MovementPattern[]
  mechanics: "compound" | "isolation" | "unknown"
  laterality: "bilateral" | "unilateral" | "alternating" | "unknown"
  tracking:
    | "external_load"
    | "assistance"
    | "bodyweight"
    | "band_resistance"
    | "repetition_only"
    | "timed"
    | "distance"
    | "unknown"
  requiredEquipment: string[]
  setRoles: EffectiveSetRole[]
  classificationConfidence: number
  skill: "basic" | "complex" | "unknown"
  setupSeconds: number
  tags: string[]
  automaticProgramming: AutomaticProgramming
  familyId?: string
  variantOf?: string
  duplicateOf?: string
  provenance:
    | "rule"
    | "curated"
    | "curated_text"
    | "curated_sampled_frames"
    | "curated_sampled_frames_and_text"
    | "curated_video"
    | "curated_video_and_text"
  reviewStatus?:
    | "rule_only"
    | "partially_reviewed"
    | "fully_reviewed"
    | "stale_source_review"
    | "stale_media_review"
    | "stale_source_and_media_review"
  reviewedFields?: string[]
  ruleVersion: string
}
export type IndexedExercise = {
  exercise: ExerciseSummary
  metadata: ExerciseMetadata
  participation: MuscleParticipation[]
}
export type ExerciseIndex = {
  byId: ReadonlyMap<string, IndexedExercise>
  byMuscle: ReadonlyMap<MuscleId, IndexedExercise[]>
  byDirectMuscle: ReadonlyMap<MuscleId, IndexedExercise[]>
  byPrimaryMuscle: ReadonlyMap<MuscleId, IndexedExercise[]>
  byEquipment: ReadonlyMap<string, IndexedExercise[]>
  byMovementPattern: ReadonlyMap<MovementPattern, IndexedExercise[]>
  byFamily: ReadonlyMap<string, IndexedExercise[]>
  byAutomaticProgramming: ReadonlyMap<
    AutomaticProgramming,
    IndexedExercise[]
  >
  byTracking: ReadonlyMap<ExerciseMetadata["tracking"], IndexedExercise[]>
  byMechanics: ReadonlyMap<ExerciseMetadata["mechanics"], IndexedExercise[]>
  byExerciseType: ReadonlyMap<
    ExerciseMetadata["exerciseType"],
    IndexedExercise[]
  >
  issues: PlanningIssue[]
  fingerprint: string
}
export type RepRange = { min: number; max: number }
export type PlannedSet = {
  id: string
  setType: "warmup" | "working" | "backoff"
  targetReps: RepRange
  targetRir: number
  resistance: ResistanceValue
  loadAcquisition:
    | "calibrate_by_rir"
    | "history"
    | "bodyweight"
    | "band_resistance"
  side: "both"
  groupId?: string
}
export type ScoreContribution = {
  factor: string
  rawValue: number
  weight: number
  contribution: number
}
export type Score = { total: number; contributions: ScoreContribution[] }
export type PlannedExercise = {
  exerciseId: string
  order: number
  workingSets: PlannedSet[]
  warmupSets: PlannedSet[]
  restSeconds: number
  targetMuscles: MuscleId[]
  rationale: Score
  progression: ProgressionRecommendation
}
export type SessionDurationEstimate = {
  generalWarmupSeconds: number
  specificWarmupSeconds: number
  workingSetSeconds: number
  restSeconds: number
  transitionSeconds: number
  totalSeconds: number
  confidence: Confidence
}
export type PlannedSession = {
  id: string
  scheduledAt: string
  focus: MuscleId[]
  exercises: PlannedExercise[]
  duration: SessionDurationEstimate
}
export type MuscleTarget = VolumeRange & {
  muscleId: MuscleId
  importance: number
  preferredExposures: number
}
export type TrainingWeek = {
  id: string
  start: string
  phase: "base" | "reduced_volume"
  sessions: PlannedSession[]
  targets: MuscleTarget[]
}
export type TrainingPolicy = {
  version: string
  goals: Record<
    Exclude<TrainingGoal, "power">,
    {
      volume: VolumeRange
      compoundReps: RepRange
      isolationReps: RepRange
      rir: number
      compoundRest: number
      isolationRest: number
      specificityWeight: number
    }
  >
  indirectCredit: number
  meaningfulExposureSets: number
  workloadHalfLifeHours: number
  maxSetsPerExercise: number
  sessionMuscleGuideline: number
  beginnerPreferredSets: number
  priorityMultipliers: Record<
    "low" | "normal" | "high" | "specialization",
    number
  >
  maxWeeklyVolumeIncrease: number
  historyMinSessions: number
  staleAfterDays: number
  trendThreshold: number
  reductionFraction: number
  maxLoadIncreaseFraction: number
  coarseGridMaxLoadIncreaseFraction: number
  coarseGridMaxExtraReps: number
  coarseGridRequiredTopExposures: number
  progressionEvidenceSets: number
  maxBodyweightReps: number
  rirTolerance: number
  generalWarmupSeconds: number
  secondsPerRep: number
  transitionSeconds: number
  warmupRestSeconds: number
  warmupFractions: number[]
  warmupReps: number[]
  minimumAutomaticClassificationConfidence: number
  minimumSpecializedClassificationConfidence: number
  beamWidth: number
  candidateLimit: number
  maxExercisesPerSession: number
  localIterations: number
  exerciseWeights: Record<
    | "coverage"
    | "specificity"
    | "continuity"
    | "preference"
    | "skillSuitability"
    | "patternNeed"
    | "quality"
    | "redundancy"
    | "workload"
    | "duration",
    number
  >
  sessionWeights: Record<
    | "coverage"
    | "duration"
    | "quality"
    | "redundancy"
    | "concentration"
    | "nonempty",
    number
  >
  similarityWeights: {
    family: number
    patterns: number
    directMuscles: number
    mechanics: number
    tracking: number
    laterality: number
    equipment: number
  }
  orderingWeights: { specific: number; priority: number; compound: number }
  adherenceReductionThreshold: number
  beginnerRir: number
  heavyWarmupMaxReps: number
  programWeights: Record<
    | "volume"
    | "specificity"
    | "frequency"
    | "balance"
    | "quality"
    | "continuity"
    | "duration"
    | "preference"
    | "redundancy"
    | "recovery"
    | "session",
    number
  >
}
export type TrainingProgram = {
  id: string
  engineVersion: string
  policyVersion: string
  policy: TrainingPolicy
  datasetFingerprint: string
  generatedAt: string
  goal: TrainingGoal
  durationWeeks: number
  weeks: TrainingWeek[]
  diagnostics: {
    splits: { name: string; score: number; valid: boolean }[]
    candidateCount: number
    optimizerIterations: number
    selectedSplit: string
    score: Score
    warnings: PlanningIssue[]
  }
  adaptation?: {
    sourceProgramId: string
    asOf: string
    mode: "remaining_week" | "next_week"
  }
}
export type TrainingProgramValidationContext = {
  sourceProgram?: TrainingProgram
}
export type ProgramGenerationRequest = {
  profile: UserTrainingProfile
  preferences: PlanningPreferences
  schedule: TrainingSchedule
  history: TrainingHistory
  exercises: ExerciseSummary[]
  now: string
  readiness?: Readiness
  metadata?: ExerciseMetadata[]
  policy?: TrainingPolicy
}
export type ProgramGenerationResult =
  | {
      status: "success" | "partial"
      program: TrainingProgram
      issues: PlanningIssue[]
    }
  | {
      status: "invalid" | "unsupported" | "infeasible"
      issues: PlanningIssue[]
      suggestions: (
        | "add_equipment"
        | "increase_duration"
        | "relax_volume_bounds"
        | "review_input"
        | "curate_metadata"
      )[]
    }
export type MuscleVolume = {
  direct: number
  indirect: number
  effective: number
}
export type MuscleTrainingState = {
  muscleId: MuscleId
  targetWeeklyEffectiveSets: number
  effectiveSetsCurrentWeek: number
  directSetsCurrentWeek: number
  indirectSetsCurrentWeek: number
  rolling7DaySets: number
  rolling14DaySets: number
  rolling28DaySets: number
  recentSessionCount: number
  lastMeaningfulTrainingAt?: string
  decayedWorkload: number
  volumeTargetDeficit: number
  workloadTrend?: number
  priorityScore: number
  status: "under_target" | "on_target" | "over_target" | "unknown"
  confidence: Confidence
}
export type StrengthEstimate = {
  estimated1RMKg: number
  confidence: Confidence
  estimator: string
  source: "actual_1rm" | "estimated_from_set"
}
export type PerformanceTrend =
  "improving" | "stable" | "declining" | "insufficient_data"
export type ExercisePerformanceState = {
  exerciseId: string
  bestEstimated1RM?: number
  recentEstimated1RM?: number
  recentResistance?: ResistanceValue
  recentRepPerformance?: number
  recentRir?: number
  trend: PerformanceTrend
  relativeChange?: number
  lastPerformedAt?: string
  exposureCount: number
  confidence: Confidence
}
export type DerivedTrainingState = {
  muscles: Record<MuscleId, MuscleTrainingState>
  exercises: Record<string, ExercisePerformanceState>
  adherence: {
    sessionCompletion?: number
    setCompletion?: number
    exerciseCompletion?: number
    durationRatio?: number
  }
  confidence: Confidence
  issues: PlanningIssue[]
}
export type ProgressionRecommendation = {
  action:
    | "calibrate"
    | "hold"
    | "increase_load"
    | "decrease_load"
    | "increase_reps"
    | "reduce_assistance"
    | "increase_assistance"
    | "coarse_grid_progression"
  resistance: ResistanceValue
  targetReps: RepRange
  confidence: Confidence
  reasons: (
    | "no_history"
    | "stale_history"
    | "context_changed"
    | "missing_effort"
    | "incomplete_sets"
    | "top_of_range"
    | "repeated_underperformance"
    | "within_range"
    | "grid_unavailable"
    | "increment_too_large"
    | "coarse_load_grid"
    | "coarse_grid_requires_alternative_progression"
  )[]
  suggestedStrategies?: (
    | "continue_repetition_progression"
    | "use_smaller_increment_if_available"
    | "use_different_variation"
  )[]
}
export type ProgressionInput = {
  exercise: IndexedExercise
  history: TrainingHistory
  now: string
  reps: RepRange
  rir: number
  requiredSets: number
  loadGrid?: LoadGrid
  loadContext?: { stationId: string; basis: "total" | "per_implement" }
  policy: TrainingPolicy
}
export interface ProgressionStrategy {
  recommend(input: ProgressionInput): ProgressionRecommendation
}
export interface StrengthEstimator {
  name: string
  estimate(set: CompletedSet): StrengthEstimate | undefined
}
export type OptimizationInput = {
  request: ProgramGenerationRequest
  index: ExerciseIndex
  state: DerivedTrainingState
  targets: MuscleTarget[]
  policy: TrainingPolicy
  continuityIds?: string[]
  baselineVolume?: Partial<Record<MuscleId, number>>
  adaptation?: {
    baselineCompletedWorkingSets: number
    baselineMuscleVolume: Partial<Record<MuscleId, number>>
    remainingWorkingSetBudget?: number
    remainingMuscleVolumeBounds?: {
      muscleId: MuscleId
      minimum?: number
      maximum?: number
    }[]
  }
}
export type OptimizationResult = {
  week?: TrainingWeek
  split: string
  candidates: number
  iterations: number
  splits: { name: string; score: number; valid: boolean }[]
}
export interface ProgramOptimizer {
  optimize(input: OptimizationInput): OptimizationResult
}
