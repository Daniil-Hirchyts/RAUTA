import Foundation

nonisolated let TRAINING_PERSISTENCE_SCHEMA_VERSION = 1

// MARK: - Program snapshot

/// The program exactly as it was generated. The policy is kept as an opaque
/// JSON object so a restored snapshot is the one that was written, never the
/// current default silently substituted for it.
nonisolated struct PersistedProgramSnapshot: Codable, Hashable, Sendable {
    var id: String
    var engineVersion: String
    var policyVersion: String
    var policy: JSONValue
    var datasetFingerprint: String
    var generatedAt: String
    var goal: TrainingGoal
    var durationWeeks: Int
    var weeks: [TrainingWeek]
    var diagnostics: ProgramDiagnostics
    var adaptation: ProgramAdaptation?
}

nonisolated struct PersistedProgramRevision: Codable, Hashable, Sendable {
    enum Reason: String, Codable, Hashable, Sendable {
        case remainingWeek = "remaining_week"
        case nextWeek = "next_week"
        case manualRegeneration = "manual_regeneration"
    }
    var sourceProgramId: String
    var reason: Reason
    var asOf: String
    /// Actual structured session IDs consumed by this revision.
    var incorporatedSessionIds: [String]?
    /// Source prescriptions replaced by this revision, never performed slots.
    var replacedSessionIds: [String]?
}

nonisolated struct PersistedProgramRecord: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable { case plan, workout }
    enum Lifecycle: String, Codable, Hashable, Sendable { case active, completed, archived }

    var id: String
    /// One-session prescriptions use the same engine snapshot without becoming
    /// the user's active multi-session plan. Missing means `plan` for v1 data.
    var kind: Kind?
    var lifecycle: Lifecycle
    var createdAt: String
    var snapshot: PersistedProgramSnapshot
    var revision: PersistedProgramRevision?

    var effectiveKind: Kind { kind ?? .plan }
}

// MARK: - Completed work

nonisolated struct PersistedCompletedExercise: Codable, Hashable, Sendable {
    /// Persistence identity for this performed exercise segment.
    var id: String
    /// Canonical exercise catalogue identity actually performed.
    var exerciseId: String
    /// Canonical exercise identity prescribed by the historical plan, if this
    /// was a substitution.
    var plannedExerciseId: String?
    var exerciseNameSnapshot: String?
    var sets: [CompletedSet]
}

/// The longest span a recorded session's duration can be.
///
/// A day is not a training session. Past this the elapsed time between opening
/// and closing the app says nothing about how long somebody trained, so it is
/// recorded as unknown rather than as a number — and the validator refuses to
/// store one.
nonisolated let MAX_SESSION_DURATION_SECONDS: Double = 86_400

nonisolated struct PersistedCompletedSession: Codable, Hashable, Sendable {
    /// Actual workout identity; never a planned-session ID.
    var id: String
    /// The application workout record this session was performed from, when one
    /// exists. It is the join that keeps one training history.
    var sourceWorkoutId: String?
    var plannedProgramId: String?
    var plannedSessionId: String?
    var startedAt: String
    var completedAt: String
    var durationSeconds: Double?
    var status: CompletedSession.Status
    var exercises: [PersistedCompletedExercise]
}

// MARK: - Active draft

nonisolated struct PersistedSetTarget: Codable, Hashable, Sendable {
    var reps: RepRange
    var rir: Double
    var resistance: ResistanceValue
}

nonisolated struct PersistedSetObservation: Codable, Hashable, Sendable {
    var reps: Double?
    var resistance: ResistanceValue?
    var rir: Double?
    var rpe: Double?
    var completed: Bool
    var timestamp: String?

    init(
        reps: Double? = nil,
        resistance: ResistanceValue? = nil,
        rir: Double? = nil,
        rpe: Double? = nil,
        completed: Bool,
        timestamp: String? = nil
    ) {
        self.reps = reps
        self.resistance = resistance
        self.rir = rir
        self.rpe = rpe
        self.completed = completed
        self.timestamp = timestamp
    }
}

nonisolated struct PersistedActiveSetDraft: Codable, Hashable, Sendable, Identifiable {
    /// Draft identity; distinct from both `plannedSetId` and the later
    /// completed-set ID.
    var id: String
    var plannedSetId: String?
    var setType: SetType
    var side: SetSide
    var target: PersistedSetTarget?
    var observation: PersistedSetObservation?
}

nonisolated struct PersistedActiveExerciseDraft: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var exerciseId: String
    var plannedExerciseId: String?
    var exerciseNameSnapshot: String?
    var sets: [PersistedActiveSetDraft]
}

nonisolated struct PersistedActiveWorkoutDraft: Codable, Hashable, Sendable {
    var id: String
    /// The application workout being performed, carried into the completed
    /// session so the two histories never count it twice.
    var sourceWorkoutId: String?
    var plannedProgramId: String?
    var plannedSessionId: String?
    var startedAt: String
    var exercises: [PersistedActiveExerciseDraft]
}

// MARK: - Settings

nonisolated struct PersistedLoadConfiguration: Codable, Hashable, Sendable, Identifiable {
    enum Mode: String, Codable, Hashable, Sendable {
        case externalLoad = "external_load"
        case assistance
    }
    var id: String
    var exerciseId: String
    var stationId: String
    /// Which measurement this station carries. Absent means external load: a
    /// configuration written before assisted machines were describable says
    /// nothing about assistance rather than claiming to cover it.
    var mode: Mode?
    var basis: LoadBasis
    var grid: LoadGrid

    var effectiveMode: Mode { mode ?? .externalLoad }
}

nonisolated struct PersistedHistoryCoverage: Codable, Hashable, Sendable {
    enum Status: String, Codable, Hashable, Sendable { case unknown, complete }
    var status: Status
    var coverageStart: String?

    static let unknown = PersistedHistoryCoverage(status: .unknown, coverageStart: nil)
}

nonisolated struct PersistedTrainingSettings: Codable, Hashable, Sendable {
    var historyCoverage: PersistedHistoryCoverage
    var loadConfigurations: [PersistedLoadConfiguration]
    /// The station each exercise is currently trained at, by exercise ID. A
    /// pointer, not evidence: an entry that no longer resolves simply means the
    /// exercise falls back to its equipment default.
    var activeLoadConfigurations: [String: String]?
}

// MARK: - Transitions

/// The legacy completion a finish transition intends to write. Held in the
/// intent rather than recomputed during recovery: a clock read on the way back
/// would give a resumed finish a different duration than the one the person saw.
nonisolated struct PersistedLegacyCompletionIntent: Codable, Hashable, Sendable {
    enum SyncStatus: String, Codable, Hashable, Sendable {
        case notRequested = "not-requested"
        case pending
    }
    var startedAt: String
    var completedAt: String
    var durationMs: Double
    var activeCalories: Double
    var completedExerciseIds: [String]
    var healthSyncStatus: SyncStatus
}

nonisolated struct PersistedPlannedReference: Codable, Hashable, Sendable {
    var programId: String
    var sessionId: String
}

nonisolated struct PersistedTransitionShell: Codable, Hashable, Sendable {
    var workoutName: String
    var workoutDate: String
    var exerciseIds: [String]
    var startedAtMs: Double
}

/// One workout transition that spans stores, written down before it starts, so
/// recovery can carry the same transition forward to the same result instead of
/// guessing at the wreckage.
nonisolated struct PersistedTransitionIntent: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable { case start, finish, cancel }

    /// Stable identity for the transition itself, so a retry is recognisable.
    var id: String
    var kind: Kind
    var recordedAt: String
    /// The application workout the transition belongs to.
    var sourceWorkoutId: String
    /// The structured draft the transition creates, closes or discards.
    var draftId: String?
    /// Present only when the workout being started is a planned one.
    var planned: PersistedPlannedReference?
    /// `start` only: the shell to re-establish, exactly as it was to be created.
    var shell: PersistedTransitionShell?
    /// `finish` only: the one completion instant every step of the transition
    /// uses, so replaying it can never produce a second, different answer.
    var completedAt: String?
    /// `finish` only: the identity the structured session will be written under.
    var sessionId: String?
    /// `finish` only: the status decided from coverage when the intent was
    /// recorded, so recovery does not re-judge work it cannot see.
    var status: CompletedSession.Status?
    /// `finish` only: the legacy completion to apply, if it has not landed.
    var legacy: PersistedLegacyCompletionIntent?
}

// MARK: - State

nonisolated struct PersistedTrainingState: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var programs: [PersistedProgramRecord]
    var sessions: [PersistedCompletedSession]
    var activeWorkout: PersistedActiveWorkoutDraft?
    var activeProgramId: String?
    var settings: PersistedTrainingSettings
    /// The cross-store transition in flight, when one is.
    var transition: PersistedTransitionIntent?

    static func empty() -> PersistedTrainingState {
        PersistedTrainingState(
            schemaVersion: TRAINING_PERSISTENCE_SCHEMA_VERSION,
            programs: [],
            sessions: [],
            activeWorkout: nil,
            activeProgramId: nil,
            settings: PersistedTrainingSettings(
                historyCoverage: .unknown,
                loadConfigurations: [],
                activeLoadConfigurations: nil
            ),
            transition: nil
        )
    }
}

nonisolated struct TrainingPersistenceIssue: Hashable, Sendable {
    var path: String
    var message: String
}

/// Raised when a write would leave the persisted state invalid.
nonisolated struct TrainingPersistenceValidationError: Error {
    var issues: [TrainingPersistenceIssue]

    var localizedDescription: String {
        "Invalid training state: " + issues.map { "\($0.path): \($0.message)" }.joined(separator: "; ")
    }
}

/// Every other failure the persistence layer raises, kept as plain messages so
/// the surfaces that show them read the same text the web app did.
nonisolated struct TrainingPersistenceError: Error {
    var message: String

    init(_ message: String) { self.message = message }

    var localizedDescription: String { message }
}
