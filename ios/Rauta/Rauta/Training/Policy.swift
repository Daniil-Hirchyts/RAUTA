import Foundation

let ENGINE_VERSION = "1.3.0"

struct GoalPolicy: Codable, Hashable, Sendable {
    var volume: VolumeRange
    var compoundReps: RepRange
    var isolationReps: RepRange
    var rir: Double
    var compoundRest: Double
    var isolationRest: Double
    var specificityWeight: Double
}

struct SimilarityWeights: Codable, Hashable, Sendable {
    var family: Double
    var patterns: Double
    var directMuscles: Double
    var mechanics: Double
    var tracking: Double
    var laterality: Double
    var equipment: Double
}

struct OrderingWeights: Codable, Hashable, Sendable {
    var specific: Double
    var priority: Double
    var compound: Double
}

/// Exact values are versioned engineering policy; see docs/training-engine/EVIDENCE.md.
///
/// Weight bags stay keyed by `String` so a persisted program snapshot is
/// byte-identical to the one the TypeScript engine wrote.
struct TrainingPolicy: Codable, Hashable, Sendable {
    var version: String
    var goals: [String: GoalPolicy]
    var indirectCredit: Double
    var meaningfulExposureSets: Double
    var workloadHalfLifeHours: Double
    var maxSetsPerExercise: Int
    var sessionMuscleGuideline: Double
    var beginnerPreferredSets: Double
    var priorityMultipliers: [String: Double]
    var maxWeeklyVolumeIncrease: Double
    var historyMinSessions: Int
    var staleAfterDays: Double
    var trendThreshold: Double
    var reductionFraction: Double
    var maxLoadIncreaseFraction: Double
    var coarseGridMaxLoadIncreaseFraction: Double
    var coarseGridMaxExtraReps: Double
    var coarseGridRequiredTopExposures: Int
    var progressionEvidenceSets: Int
    var maxBodyweightReps: Double
    var rirTolerance: Double
    var generalWarmupSeconds: Double
    var secondsPerRep: Double
    var transitionSeconds: Double
    var warmupRestSeconds: Double
    var warmupFractions: [Double]
    var warmupReps: [Double]
    var minimumAutomaticClassificationConfidence: Double
    var minimumSpecializedClassificationConfidence: Double
    var beamWidth: Int
    var candidateLimit: Int
    var maxExercisesPerSession: Int
    var localIterations: Int
    var exerciseWeights: [String: Double]
    var sessionWeights: [String: Double]
    var similarityWeights: SimilarityWeights
    var orderingWeights: OrderingWeights
    var adherenceReductionThreshold: Double
    var beginnerRir: Double
    var heavyWarmupMaxReps: Double
    var programWeights: [String: Double]

    func goal(_ goal: TrainingGoal) -> GoalPolicy {
        goals[goal.rawValue] ?? goals[TrainingGoal.generalFitness.rawValue]!
    }

    func priorityMultiplier(_ level: MusclePriorityLevel) -> Double {
        priorityMultipliers[level.rawValue] ?? 1
    }

    func exerciseWeight(_ key: ExerciseWeightKey) -> Double { exerciseWeights[key.rawValue] ?? 0 }
    func sessionWeight(_ key: SessionWeightKey) -> Double { sessionWeights[key.rawValue] ?? 0 }
    func programWeight(_ key: ProgramWeightKey) -> Double { programWeights[key.rawValue] ?? 0 }
}

enum ExerciseWeightKey: String, CaseIterable {
    case coverage, specificity, continuity, preference, skillSuitability
    case patternNeed, quality, redundancy, workload, duration
}

enum SessionWeightKey: String, CaseIterable {
    case coverage, duration, quality, redundancy, concentration, nonempty
}

enum ProgramWeightKey: String, CaseIterable {
    case volume, specificity, frequency, balance, quality, continuity
    case duration, preference, redundancy, recovery, session
}

let DEFAULT_POLICY = TrainingPolicy(
    version: "1.3.0",
    goals: [
        "hypertrophy": GoalPolicy(
            volume: VolumeRange(minimum: 6, preferred: 10, upperGuideline: 18),
            compoundReps: RepRange(min: 6, max: 12),
            isolationReps: RepRange(min: 10, max: 20),
            rir: 2, compoundRest: 120, isolationRest: 90, specificityWeight: 0.5
        ),
        "strength": GoalPolicy(
            volume: VolumeRange(minimum: 4, preferred: 6, upperGuideline: 12),
            compoundReps: RepRange(min: 3, max: 6),
            isolationReps: RepRange(min: 8, max: 12),
            rir: 2, compoundRest: 180, isolationRest: 90, specificityWeight: 2
        ),
        "general_fitness": GoalPolicy(
            volume: VolumeRange(minimum: 3, preferred: 6, upperGuideline: 12),
            compoundReps: RepRange(min: 8, max: 12),
            isolationReps: RepRange(min: 10, max: 15),
            rir: 3, compoundRest: 120, isolationRest: 60, specificityWeight: 0.3
        ),
        "muscular_endurance": GoalPolicy(
            volume: VolumeRange(minimum: 3, preferred: 6, upperGuideline: 12),
            compoundReps: RepRange(min: 12, max: 20),
            isolationReps: RepRange(min: 15, max: 25),
            rir: 2, compoundRest: 90, isolationRest: 60, specificityWeight: 0.2
        ),
        "strength_hypertrophy": GoalPolicy(
            volume: VolumeRange(minimum: 5, preferred: 8, upperGuideline: 16),
            compoundReps: RepRange(min: 4, max: 8),
            isolationReps: RepRange(min: 10, max: 15),
            rir: 2, compoundRest: 180, isolationRest: 90, specificityWeight: 1.4
        ),
        "fat_loss_support": GoalPolicy(
            volume: VolumeRange(minimum: 3, preferred: 6, upperGuideline: 12),
            compoundReps: RepRange(min: 8, max: 12),
            isolationReps: RepRange(min: 10, max: 15),
            rir: 3, compoundRest: 120, isolationRest: 60, specificityWeight: 0.3
        ),
    ],
    indirectCredit: 0.5,
    meaningfulExposureSets: 1,
    workloadHalfLifeHours: 48,
    maxSetsPerExercise: 4,
    sessionMuscleGuideline: 6,
    beginnerPreferredSets: 6,
    priorityMultipliers: ["low": 0.75, "normal": 1, "high": 1.25, "specialization": 1.5],
    maxWeeklyVolumeIncrease: 2,
    historyMinSessions: 6,
    staleAfterDays: 28,
    trendThreshold: 0.03,
    reductionFraction: 0.1,
    maxLoadIncreaseFraction: 0.1,
    coarseGridMaxLoadIncreaseFraction: 0.35,
    coarseGridMaxExtraReps: 4,
    coarseGridRequiredTopExposures: 2,
    progressionEvidenceSets: 3,
    maxBodyweightReps: 30,
    rirTolerance: 1,
    generalWarmupSeconds: 180,
    secondsPerRep: 4,
    transitionSeconds: 45,
    warmupRestSeconds: 60,
    warmupFractions: [0.5, 0.75],
    warmupReps: [5, 3],
    minimumAutomaticClassificationConfidence: 0.7,
    minimumSpecializedClassificationConfidence: 0.55,
    beamWidth: 3,
    candidateLimit: 8,
    maxExercisesPerSession: 7,
    localIterations: 12,
    exerciseWeights: [
        "coverage": 5, "specificity": 1, "continuity": 0.8, "preference": 0.5,
        "skillSuitability": 0.7, "patternNeed": 0.7, "quality": 0.4,
        "redundancy": -1.5, "workload": -0.5, "duration": -0.5,
    ],
    sessionWeights: [
        "coverage": 2, "duration": 1, "quality": 1,
        "redundancy": -1, "concentration": -1, "nonempty": 2,
    ],
    similarityWeights: SimilarityWeights(
        family: 0, patterns: 0.5, directMuscles: 0.4,
        mechanics: 0, tracking: 0, laterality: 0, equipment: 0.1
    ),
    orderingWeights: OrderingWeights(specific: 10, priority: 2, compound: 1),
    adherenceReductionThreshold: 0.7,
    beginnerRir: 3,
    heavyWarmupMaxReps: 8,
    programWeights: [
        "volume": 5, "specificity": 1, "frequency": 0.6, "balance": 0.6,
        "quality": 0.3, "continuity": 0.4, "duration": 0.4, "preference": 0.3,
        "redundancy": -0.6, "recovery": -0.6, "session": 0.5,
    ]
)

/// The tracking modes the planner knows how to prescribe against.
let PLANNER_SUPPORTED_TRACKING: [TrackingMode] = [
    .externalLoad, .assistance, .bodyweight, .bandResistance,
]

func plannerSupportsTracking(_ tracking: TrackingMode) -> Bool {
    PLANNER_SUPPORTED_TRACKING.contains(tracking)
}

func plannerSupportsExercise(_ metadata: ExerciseMetadata) -> Bool {
    metadata.exerciseType == .resistance && plannerSupportsTracking(metadata.tracking)
}
