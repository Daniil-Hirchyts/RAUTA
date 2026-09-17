import Foundation

// MARK: - Exercise

nonisolated struct ExerciseSummary: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var equipment: String
    var primaryMuscle: MuscleId?
    /// Muscles ordered strongest-involvement first, with `muscleWeights[i]`
    /// holding how much of the exercise's effort lands on `muscles[i]`
    /// (1 = the muscle the movement is built around).
    var muscles: [MuscleId]
    var muscleWeights: [Double]
    var instructions: [String]
}

// MARK: - Enumerations

nonisolated enum TrainingGoal: String, Codable, CaseIterable, Hashable, Sendable {
    case hypertrophy
    case strength
    case generalFitness = "general_fitness"
    case muscularEndurance = "muscular_endurance"
    case strengthHypertrophy = "strength_hypertrophy"
    case fatLossSupport = "fat_loss_support"
    case power
}

nonisolated enum Experience: String, Codable, CaseIterable, Hashable, Sendable {
    case beginner, intermediate, advanced
}

nonisolated enum Confidence: String, Codable, CaseIterable, Hashable, Sendable {
    case none, low, medium, high

    var rank: Int {
        switch self {
        case .none: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    func atLeast(_ minimum: Confidence) -> Bool { rank >= minimum.rank }
}

nonisolated enum MovementPattern: String, Codable, CaseIterable, Hashable, Sendable {
    case horizontalPush = "horizontal_push"
    case horizontalPull = "horizontal_pull"
    case verticalPush = "vertical_push"
    case verticalPull = "vertical_pull"
    case squat
    case hinge
    case lunge
    case kneeExtension = "knee_extension"
    case kneeFlexion = "knee_flexion"
    case hipExtension = "hip_extension"
    case hipFlexion = "hip_flexion"
    case hipAbduction = "hip_abduction"
    case hipAdduction = "hip_adduction"
    case hipRotation = "hip_rotation"
    case elbowFlexion = "elbow_flexion"
    case elbowExtension = "elbow_extension"
    case shoulderAbduction = "shoulder_abduction"
    case shoulderFlexion = "shoulder_flexion"
    case shoulderExtension = "shoulder_extension"
    case shoulderRotation = "shoulder_rotation"
    case scapularProtraction = "scapular_protraction"
    case scapularRetraction = "scapular_retraction"
    case scapularElevation = "scapular_elevation"
    case scapularDepression = "scapular_depression"
    case wristFlexion = "wrist_flexion"
    case wristExtension = "wrist_extension"
    case forearmRotation = "forearm_rotation"
    case grip
    case calfRaise = "calf_raise"
    case dorsiflexion
    case trunkFlexion = "trunk_flexion"
    case trunkExtension = "trunk_extension"
    case trunkRotation = "trunk_rotation"
    case trunkLateralFlexion = "trunk_lateral_flexion"
    case antiExtension = "anti_extension"
    case antiRotation = "anti_rotation"
    case neckFlexion = "neck_flexion"
    case neckExtension = "neck_extension"
    case neckRotation = "neck_rotation"
    case carry
    case locomotion
    case jump
    case throwing = "throw"
    case mobility
    case balance
    case wholeBody = "whole_body"
    case unknown
}

nonisolated enum PlanningIssueCode: String, Codable, Hashable, Sendable {
    case invalidInput = "INVALID_INPUT"
    case unsupportedPopulation = "UNSUPPORTED_POPULATION"
    case unsupportedGoal = "UNSUPPORTED_GOAL"
    case invalidExerciseData = "INVALID_EXERCISE_DATA"
    case unknownExercise = "UNKNOWN_EXERCISE"
    case excludedExercise = "EXCLUDED_EXERCISE"
    case unavailableEquipment = "UNAVAILABLE_EQUIPMENT"
    case unsupportedExercise = "UNSUPPORTED_EXERCISE"
    case noValidExercises = "NO_VALID_EXERCISES"
    case sessionDurationInfeasible = "SESSION_DURATION_INFEASIBLE"
    case invalidProgram = "INVALID_PROGRAM"
    case volumeLimit = "VOLUME_LIMIT"
    case volumeBelowTarget = "VOLUME_BELOW_TARGET"
    case frequencyBelowTarget = "FREQUENCY_BELOW_TARGET"
    case insufficientHistoryForLoad = "INSUFFICIENT_HISTORY_FOR_LOAD"
    case incompleteHistory = "INCOMPLETE_HISTORY"
    case staleHistory = "STALE_HISTORY"
    case lowMetadataConfidence = "LOW_METADATA_CONFIDENCE"
    case missedVolumeDropped = "MISSED_VOLUME_DROPPED"
    case reducedVolume = "REDUCED_VOLUME"
    case specificityUnavailable = "SPECIFICITY_UNAVAILABLE"
}

/// The loosely typed context bag planning issues carry.
nonisolated enum IssueContextValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case strings([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([String].self) { self = .strings(value) }
        else { self = .string("") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .strings(let value): try container.encode(value)
        }
    }

    var text: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return Num.trimmed(value)
        case .bool(let value): return value ? "true" : "false"
        case .strings(let value): return value.joined(separator: ", ")
        }
    }
}

nonisolated struct PlanningIssue: Codable, Hashable, Sendable {
    var code: PlanningIssueCode
    var path: String?
    var context: [String: IssueContextValue]?

    init(_ code: PlanningIssueCode, path: String? = nil, context: [String: IssueContextValue]? = nil) {
        self.code = code
        self.path = path
        self.context = context
    }
}

// MARK: - Profile & preferences

nonisolated enum HealthLimitation: String, Codable, CaseIterable, Hashable, Sendable {
    case medicalCondition = "medical_condition"
    case activeInjury = "active_injury"
    case rehabilitation
    case pregnancy
    case other
}

nonisolated struct TrainingHealth: Codable, Hashable, Sendable {
    enum Status: String, Codable, Hashable, Sendable { case healthy, unsupported }
    var status: Status
    var reasons: [HealthLimitation]?

    static let healthy = TrainingHealth(status: .healthy, reasons: nil)
    static func unsupported(_ reasons: [HealthLimitation]) -> TrainingHealth {
        TrainingHealth(status: .unsupported, reasons: reasons)
    }
}

nonisolated struct UserTrainingProfile: Codable, Hashable, Sendable {
    var age: Double
    var bodyWeightKg: Double?
    var heightCm: Double?
    var trainingAgeMonths: Double?
    var trainingExperience: Experience
    var health: TrainingHealth
}

nonisolated struct VolumeRange: Codable, Hashable, Sendable {
    var minimum: Double
    var preferred: Double
    var upperGuideline: Double
}

nonisolated enum LoadBasis: String, Codable, Hashable, Sendable {
    case total
    case perImplement = "per_implement"
}

/// `{ incrementKg, minimumKg?, maximumKg? }` or `{ availableLoadsKg }`.
nonisolated struct LoadGrid: Codable, Hashable, Sendable {
    var incrementKg: Double?
    var minimumKg: Double?
    var maximumKg: Double?
    var availableLoadsKg: [Double]?

    init(incrementKg: Double, minimumKg: Double? = nil, maximumKg: Double? = nil) {
        self.incrementKg = incrementKg
        self.minimumKg = minimumKg
        self.maximumKg = maximumKg
        self.availableLoadsKg = nil
    }

    init(availableLoadsKg: [Double]) {
        self.availableLoadsKg = availableLoadsKg
        self.incrementKg = nil
        self.minimumKg = nil
        self.maximumKg = nil
    }

    var isDiscrete: Bool { availableLoadsKg != nil }
}

nonisolated enum MusclePriorityLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case low, normal, high, specialization
}

nonisolated struct MusclePriorityPreference: Codable, Hashable, Sendable {
    var muscleId: MuscleId
    var level: MusclePriorityLevel
}

nonisolated struct MuscleVolumeBound: Codable, Hashable, Sendable {
    var muscleId: MuscleId
    var minimum: Double?
    var maximum: Double?
}

nonisolated struct LoadContext: Codable, Hashable, Sendable {
    var stationId: String
    var basis: LoadBasis
}

nonisolated struct PlanningPreferences: Codable, Hashable, Sendable {
    var goal: TrainingGoal
    var availableEquipment: [String]
    var preferredExerciseIds: [String]?
    var dislikedExerciseIds: [String]?
    var excludedExerciseIds: [String]?
    var excludedPatterns: [MovementPattern]?
    var strengthExerciseIds: [String]?
    var priorityMuscles: [MusclePriorityPreference]?
    var preferredSessionDurationMinutes: Double?
    var maxSessionDurationMinutes: Double
    var maxWeeklyWorkingSets: Double?
    var muscleVolumeBounds: [MuscleVolumeBound]?
    var loadGrids: [String: LoadGrid]?
    /// Station and basis must match logs before prescribing kg; no cross-machine transfer.
    var loadContexts: [String: LoadContext]?
}

nonisolated struct TrainingSchedule: Codable, Hashable, Sendable {
    var weekStart: String
    var days: [Int]
    /// Explicit slots when rescheduling puts multiple sessions on one day.
    var sessionDays: [Int]?
    var durationWeeks: Int
}

// MARK: - Observations

nonisolated enum ResistanceKind: String, Codable, Hashable, Sendable {
    case externalLoad = "external_load"
    case assistance
    case bodyweight
    case bandResistance = "band_resistance"
    case unknown
}

nonisolated struct ResistanceValue: Codable, Hashable, Sendable {
    var type: ResistanceKind
    var kg: Double?
    var basis: LoadBasis?
    var stationId: String?

    static let bodyweight = ResistanceValue(type: .bodyweight)
    static let bandResistance = ResistanceValue(type: .bandResistance)
    static let unknown = ResistanceValue(type: .unknown)

    init(type: ResistanceKind, kg: Double? = nil, basis: LoadBasis? = nil, stationId: String? = nil) {
        self.type = type
        self.kg = kg
        self.basis = basis
        self.stationId = stationId
    }

    static func load(_ kg: Double, basis: LoadBasis, stationId: String) -> ResistanceValue {
        ResistanceValue(type: .externalLoad, kg: kg, basis: basis, stationId: stationId)
    }

    static func assistance(_ kg: Double, basis: LoadBasis, stationId: String) -> ResistanceValue {
        ResistanceValue(type: .assistance, kg: kg, basis: basis, stationId: stationId)
    }

    var isMeasured: Bool { type == .externalLoad || type == .assistance }
}

nonisolated enum SetType: String, Codable, CaseIterable, Hashable, Sendable {
    case warmup, working, backoff, drop, other
}

nonisolated enum SetSide: String, Codable, CaseIterable, Hashable, Sendable {
    case both, left, right
}

nonisolated struct CompletedSet: Codable, Hashable, Sendable {
    var id: String
    var plannedSetId: String?
    var reps: Double
    var resistance: ResistanceValue
    var rir: Double?
    var rpe: Double?
    var completed: Bool
    var setType: SetType
    /// both = paired limbs (3 sets each side = 3 records); left/right = half group credit.
    var side: SetSide
    var timestamp: String?
}

nonisolated struct CompletedExercise: Codable, Hashable, Sendable {
    var exerciseId: String
    var sets: [CompletedSet]
}

nonisolated struct CompletedSession: Codable, Hashable, Sendable {
    enum Status: String, Codable, Hashable, Sendable { case completed, partial }
    var id: String
    var plannedSessionId: String?
    var startedAt: String
    var completedAt: String
    var durationSeconds: Double?
    var status: Status
    var exercises: [CompletedExercise]
}

nonisolated struct TrainingHistory: Codable, Hashable, Sendable {
    enum Coverage: String, Codable, Hashable, Sendable { case complete, unknown }
    var sessions: [CompletedSession]
    var coverage: Coverage
    var coverageStart: String?

    static let empty = TrainingHistory(sessions: [], coverage: .unknown, coverageStart: nil)
}

nonisolated struct SorenessEntry: Codable, Hashable, Sendable {
    enum Level: String, Codable, Hashable, Sendable { case none, mild, high }
    var muscleId: MuscleId
    var level: Level
}

nonisolated struct Readiness: Codable, Hashable, Sendable {
    enum Perceived: String, Codable, Hashable, Sendable { case normal, low }
    var perceivedReadiness: Perceived?
    var soreness: [SorenessEntry]?
    var pain: Bool?
}

// MARK: - Metadata

nonisolated struct MuscleParticipation: Codable, Hashable, Sendable {
    var muscleId: MuscleId
    var relativeInvolvement: Double
}

nonisolated struct EffectiveSetRole: Codable, Hashable, Sendable {
    enum Role: String, Codable, Hashable, Sendable { case direct, indirect, incidental }
    enum Provenance: String, Codable, Hashable, Sendable { case rule, curated }
    var muscleId: MuscleId
    var role: Role
    var provenance: Provenance
}

nonisolated enum AutomaticProgramming: String, Codable, CaseIterable, Hashable, Sendable {
    case allowed
    case specializedOnly = "specialized_only"
    case manualOnly = "manual_only"
}

nonisolated enum ExerciseType: String, Codable, CaseIterable, Hashable, Sendable {
    case resistance, isometric, stretch, mobility, conditioning, power, unknown
}

nonisolated enum Mechanics: String, Codable, CaseIterable, Hashable, Sendable {
    case compound, isolation, unknown
}

nonisolated enum Laterality: String, Codable, CaseIterable, Hashable, Sendable {
    case bilateral, unilateral, alternating, unknown
}

nonisolated enum TrackingMode: String, Codable, CaseIterable, Hashable, Sendable {
    case externalLoad = "external_load"
    case assistance
    case bodyweight
    case bandResistance = "band_resistance"
    case repetitionOnly = "repetition_only"
    case timed
    case distance
    case unknown
}

nonisolated enum MetadataProvenance: String, Codable, Hashable, Sendable {
    case rule
    case curated
    case curatedText = "curated_text"
    case curatedSampledFrames = "curated_sampled_frames"
    case curatedSampledFramesAndText = "curated_sampled_frames_and_text"
    case curatedVideo = "curated_video"
    case curatedVideoAndText = "curated_video_and_text"
}

nonisolated enum ReviewStatus: String, Codable, Hashable, Sendable {
    case ruleOnly = "rule_only"
    case partiallyReviewed = "partially_reviewed"
    case fullyReviewed = "fully_reviewed"
    case staleSourceReview = "stale_source_review"
    case staleMediaReview = "stale_media_review"
    case staleSourceAndMediaReview = "stale_source_and_media_review"
}

nonisolated enum Skill: String, Codable, CaseIterable, Hashable, Sendable {
    case basic, complex, unknown
}

nonisolated struct ExerciseMetadata: Codable, Hashable, Sendable {
    var exerciseId: String
    var exerciseType: ExerciseType
    var movementPatterns: [MovementPattern]
    var mechanics: Mechanics
    var laterality: Laterality
    var tracking: TrackingMode
    var requiredEquipment: [String]
    var setRoles: [EffectiveSetRole]
    var classificationConfidence: Double
    var skill: Skill
    var setupSeconds: Double
    var tags: [String]
    var automaticProgramming: AutomaticProgramming
    var familyId: String?
    var variantOf: String?
    var duplicateOf: String?
    var provenance: MetadataProvenance
    var reviewStatus: ReviewStatus?
    var reviewedFields: [String]?
    var ruleVersion: String
}

nonisolated struct IndexedExercise: Hashable, Sendable {
    var exercise: ExerciseSummary
    var metadata: ExerciseMetadata
    var participation: [MuscleParticipation]

    var id: String { exercise.id }
}

// MARK: - Prescription

nonisolated struct RepRange: Codable, Hashable, Sendable {
    var min: Double
    var max: Double
}

nonisolated enum PlannedSetType: String, Codable, Hashable, Sendable {
    case warmup, working, backoff
}

nonisolated enum LoadAcquisition: String, Codable, Hashable, Sendable {
    case calibrateByRir = "calibrate_by_rir"
    case history
    case bodyweight
    case bandResistance = "band_resistance"
}

nonisolated struct PlannedSet: Codable, Hashable, Sendable {
    var id: String
    var setType: PlannedSetType
    var targetReps: RepRange
    var targetRir: Double
    var resistance: ResistanceValue
    var loadAcquisition: LoadAcquisition
    var side: String
    var groupId: String?

    init(
        id: String,
        setType: PlannedSetType,
        targetReps: RepRange,
        targetRir: Double,
        resistance: ResistanceValue,
        loadAcquisition: LoadAcquisition,
        side: String = "both",
        groupId: String? = nil
    ) {
        self.id = id
        self.setType = setType
        self.targetReps = targetReps
        self.targetRir = targetRir
        self.resistance = resistance
        self.loadAcquisition = loadAcquisition
        self.side = side
        self.groupId = groupId
    }
}

nonisolated struct ScoreContribution: Codable, Hashable, Sendable {
    var factor: String
    var rawValue: Double
    var weight: Double
    var contribution: Double
}

nonisolated struct Score: Codable, Hashable, Sendable {
    var total: Double
    var contributions: [ScoreContribution]

    static let zero = Score(total: 0, contributions: [])
}

nonisolated enum ProgressionAction: String, Codable, Hashable, Sendable {
    case calibrate
    case hold
    case increaseLoad = "increase_load"
    case decreaseLoad = "decrease_load"
    case increaseReps = "increase_reps"
    case reduceAssistance = "reduce_assistance"
    case increaseAssistance = "increase_assistance"
    case coarseGridProgression = "coarse_grid_progression"
}

nonisolated enum ProgressionReason: String, Codable, Hashable, Sendable {
    case noHistory = "no_history"
    case staleHistory = "stale_history"
    case contextChanged = "context_changed"
    case missingEffort = "missing_effort"
    case incompleteSets = "incomplete_sets"
    case topOfRange = "top_of_range"
    case repeatedUnderperformance = "repeated_underperformance"
    case withinRange = "within_range"
    case gridUnavailable = "grid_unavailable"
    case incrementTooLarge = "increment_too_large"
    case coarseLoadGrid = "coarse_load_grid"
    case coarseGridRequiresAlternativeProgression = "coarse_grid_requires_alternative_progression"
}

nonisolated enum ProgressionStrategySuggestion: String, Codable, Hashable, Sendable {
    case continueRepetitionProgression = "continue_repetition_progression"
    case useSmallerIncrementIfAvailable = "use_smaller_increment_if_available"
    case useDifferentVariation = "use_different_variation"
}

nonisolated struct ProgressionRecommendation: Codable, Hashable, Sendable {
    var action: ProgressionAction
    var resistance: ResistanceValue
    var targetReps: RepRange
    var confidence: Confidence
    var reasons: [ProgressionReason]
    var suggestedStrategies: [ProgressionStrategySuggestion]?
}

nonisolated struct PlannedExercise: Codable, Hashable, Sendable {
    var exerciseId: String
    var order: Int
    var workingSets: [PlannedSet]
    var warmupSets: [PlannedSet]
    var restSeconds: Double
    var targetMuscles: [MuscleId]
    var rationale: Score
    var progression: ProgressionRecommendation
}

nonisolated struct SessionDurationEstimate: Codable, Hashable, Sendable {
    var generalWarmupSeconds: Double
    var specificWarmupSeconds: Double
    var workingSetSeconds: Double
    var restSeconds: Double
    var transitionSeconds: Double
    var totalSeconds: Double
    var confidence: Confidence
}

nonisolated struct PlannedSession: Codable, Hashable, Sendable {
    var id: String
    var scheduledAt: String
    var focus: [MuscleId]
    var exercises: [PlannedExercise]
    var duration: SessionDurationEstimate
}

nonisolated struct MuscleTarget: Codable, Hashable, Sendable {
    var muscleId: MuscleId
    var minimum: Double
    var preferred: Double
    var upperGuideline: Double
    var importance: Double
    var preferredExposures: Double
}

nonisolated struct TrainingWeek: Codable, Hashable, Sendable {
    enum Phase: String, Codable, Hashable, Sendable {
        case base
        case reducedVolume = "reduced_volume"
    }
    var id: String
    var start: String
    var phase: Phase
    var sessions: [PlannedSession]
    var targets: [MuscleTarget]
}

nonisolated struct SplitDiagnostic: Codable, Hashable, Sendable {
    var name: String
    var score: Double
    var valid: Bool
}

nonisolated struct ProgramDiagnostics: Codable, Hashable, Sendable {
    var splits: [SplitDiagnostic]
    var candidateCount: Int
    var optimizerIterations: Int
    var selectedSplit: String
    var score: Score
    var warnings: [PlanningIssue]
}

nonisolated struct ProgramAdaptation: Codable, Hashable, Sendable {
    enum Mode: String, Codable, Hashable, Sendable {
        case remainingWeek = "remaining_week"
        case nextWeek = "next_week"
    }
    var sourceProgramId: String
    var asOf: String
    var mode: Mode
}

nonisolated struct TrainingProgram: Codable, Hashable, Sendable {
    var id: String
    var engineVersion: String
    var policyVersion: String
    var policy: TrainingPolicy
    var datasetFingerprint: String
    var generatedAt: String
    var goal: TrainingGoal
    var durationWeeks: Int
    var weeks: [TrainingWeek]
    var diagnostics: ProgramDiagnostics
    var adaptation: ProgramAdaptation?
}

// MARK: - Requests & results

nonisolated struct ProgramGenerationRequest: Sendable {
    var profile: UserTrainingProfile
    var preferences: PlanningPreferences
    var schedule: TrainingSchedule
    var history: TrainingHistory
    var exercises: [ExerciseSummary]
    var now: String
    var readiness: Readiness?
    var metadata: [ExerciseMetadata]?
    var policy: TrainingPolicy?
}

nonisolated enum GenerationSuggestion: String, Codable, Hashable, Sendable {
    case addEquipment = "add_equipment"
    case increaseDuration = "increase_duration"
    case relaxVolumeBounds = "relax_volume_bounds"
    case reviewInput = "review_input"
    case curateMetadata = "curate_metadata"
}

nonisolated enum ProgramGenerationResult: Sendable {
    case success(program: TrainingProgram, issues: [PlanningIssue])
    case partial(program: TrainingProgram, issues: [PlanningIssue])
    case invalid(issues: [PlanningIssue], suggestions: [GenerationSuggestion])
    case unsupported(issues: [PlanningIssue], suggestions: [GenerationSuggestion])
    case infeasible(issues: [PlanningIssue], suggestions: [GenerationSuggestion])

    var program: TrainingProgram? {
        switch self {
        case .success(let program, _), .partial(let program, _): return program
        default: return nil
        }
    }

    var issues: [PlanningIssue] {
        switch self {
        case .success(_, let issues), .partial(_, let issues): return issues
        case .invalid(let issues, _), .unsupported(let issues, _), .infeasible(let issues, _): return issues
        }
    }

    var statusName: String {
        switch self {
        case .success: return "success"
        case .partial: return "partial"
        case .invalid: return "invalid"
        case .unsupported: return "unsupported"
        case .infeasible: return "infeasible"
        }
    }
}

// MARK: - Derived state

nonisolated struct MuscleVolume: Hashable, Sendable {
    var direct: Double
    var indirect: Double
    var effective: Double
}

nonisolated struct MuscleTrainingState: Hashable, Sendable {
    enum Status: String, Hashable, Sendable {
        case underTarget = "under_target"
        case onTarget = "on_target"
        case overTarget = "over_target"
        case unknown
    }
    var muscleId: MuscleId
    var targetWeeklyEffectiveSets: Double
    var effectiveSetsCurrentWeek: Double
    var directSetsCurrentWeek: Double
    var indirectSetsCurrentWeek: Double
    var rolling7DaySets: Double
    var rolling14DaySets: Double
    var rolling28DaySets: Double
    var recentSessionCount: Double
    var lastMeaningfulTrainingAt: String?
    var decayedWorkload: Double
    var volumeTargetDeficit: Double
    var workloadTrend: Double?
    var priorityScore: Double
    var status: Status
    var confidence: Confidence
}

nonisolated struct StrengthEstimate: Hashable, Sendable {
    enum Source: String, Hashable, Sendable {
        case actual1RM = "actual_1rm"
        case estimatedFromSet = "estimated_from_set"
    }
    var estimated1RMKg: Double
    var confidence: Confidence
    var estimator: String
    var source: Source
}

nonisolated enum PerformanceTrend: String, Hashable, Sendable {
    case improving, stable, declining
    case insufficientData = "insufficient_data"
}

nonisolated struct ExercisePerformanceState: Hashable, Sendable {
    var exerciseId: String
    var bestEstimated1RM: Double?
    var recentEstimated1RM: Double?
    var recentResistance: ResistanceValue?
    var recentRepPerformance: Double?
    var recentRir: Double?
    var trend: PerformanceTrend
    var relativeChange: Double?
    var lastPerformedAt: String?
    var exposureCount: Double
    var confidence: Confidence
}

nonisolated struct AdherenceState: Hashable, Sendable {
    var sessionCompletion: Double?
    var setCompletion: Double?
    var exerciseCompletion: Double?
    var durationRatio: Double?
}

nonisolated struct DerivedTrainingState: Sendable {
    var muscles: [MuscleId: MuscleTrainingState]
    var exercises: [String: ExercisePerformanceState]
    var adherence: AdherenceState
    var confidence: Confidence
    var issues: [PlanningIssue]
}

nonisolated struct ProgressionInput: Sendable {
    var exercise: IndexedExercise
    var history: TrainingHistory
    var now: String
    var reps: RepRange
    var rir: Double
    var requiredSets: Int
    var loadGrid: LoadGrid?
    var loadContext: LoadContext?
    var policy: TrainingPolicy
}
