import Foundation

nonisolated enum DraftIdKind: String { case exercise, set }

typealias PersistenceIdFactory = (DraftIdKind) -> String

nonisolated enum WorkoutDrafts {
    private static func assertTimestamp(_ value: String, _ field: String) throws {
        guard PersistenceValidation.isValidIsoTimestamp(value) else {
            throw TrainingPersistenceError("Invalid \(field)")
        }
    }

    private static func assertObservation(_ observation: PersistedSetObservation) throws {
        var valid = true
        if let reps = observation.reps, reps != reps.rounded() || reps < 0 || reps > 1000 { valid = false }
        if let resistance = observation.resistance,
           !PersistenceValidation.isValidResistance(resistance) { valid = false }
        if let rir = observation.rir, !rir.isFinite || rir < 0 || rir > 10 { valid = false }
        if let rpe = observation.rpe, !rpe.isFinite || rpe < 0 || rpe > 10 { valid = false }
        if let rir = observation.rir, let rpe = observation.rpe, abs(rir + rpe - 10) > 1 { valid = false }
        if let timestamp = observation.timestamp,
           !PersistenceValidation.isValidIsoTimestamp(timestamp) { valid = false }
        guard valid else { throw TrainingPersistenceError("Invalid set observation") }
    }

    struct PlannedDraftInput {
        var draftId: String
        var programId: String
        var session: PlannedSession
        var startedAt: String
        var makeId: PersistenceIdFactory
        var exerciseNameSnapshot: ((String) -> String?)?
        /// The application workout this planned session is being performed
        /// from, when the shell projected one.
        var sourceWorkoutId: String?
    }

    static func createFromPlannedSession(_ input: PlannedDraftInput) throws -> PersistedActiveWorkoutDraft {
        try assertTimestamp(input.startedAt, "workout start")
        guard !input.draftId.isEmpty, !input.programId.isEmpty, !input.session.id.isEmpty else {
            throw TrainingPersistenceError("Missing planned workout identity")
        }

        return PersistedActiveWorkoutDraft(
            id: input.draftId,
            sourceWorkoutId: input.sourceWorkoutId,
            plannedProgramId: input.programId,
            plannedSessionId: input.session.id,
            startedAt: input.startedAt,
            exercises: input.session.exercises.map { exercise in
                PersistedActiveExerciseDraft(
                    id: input.makeId(.exercise),
                    exerciseId: exercise.exerciseId,
                    plannedExerciseId: exercise.exerciseId,
                    exerciseNameSnapshot: input.exerciseNameSnapshot?(exercise.exerciseId),
                    sets: (exercise.warmupSets + exercise.workingSets).map { set in
                        PersistedActiveSetDraft(
                            id: input.makeId(.set),
                            plannedSetId: set.id,
                            setType: SetType(rawValue: set.setType.rawValue) ?? .working,
                            side: SetSide(rawValue: set.side) ?? .both,
                            target: PersistedSetTarget(
                                reps: set.targetReps,
                                rir: set.targetRir,
                                resistance: set.resistance
                            ),
                            observation: nil
                        )
                    }
                )
            }
        )
    }

    /// A draft made from a planned session, cut loose from its plan: the
    /// workout's own exercises in its order, each keeping the prescription it
    /// had — set types, sides, targets — and nothing that points back at the
    /// plan. Used when the plan was replaced and the person trains the session
    /// anyway, so it cannot be counted against a plan that no longer runs.
    static func detachedFromPlan(
        _ draft: PersistedActiveWorkoutDraft,
        exerciseIds: [String],
        makeId: PersistenceIdFactory,
        exerciseNameSnapshot: ((String) -> String?)?
    ) -> PersistedActiveWorkoutDraft {
        let prescribed = Dictionary(
            draft.exercises.map { ($0.exerciseId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var detached = draft
        detached.plannedProgramId = nil
        detached.plannedSessionId = nil
        detached.exercises = exerciseIds.map { exerciseId in
            guard var exercise = prescribed[exerciseId] else {
                return PersistedActiveExerciseDraft(
                    id: makeId(.exercise),
                    exerciseId: exerciseId,
                    plannedExerciseId: nil,
                    exerciseNameSnapshot: exerciseNameSnapshot?(exerciseId),
                    sets: []
                )
            }
            exercise.plannedExerciseId = nil
            exercise.sets = exercise.sets.map { set in
                var set = set
                set.plannedSetId = nil
                return set
            }
            return exercise
        }
        return detached
    }

    struct FreeDraftInput {
        var draftId: String
        var startedAt: String
        var exerciseIds: [String]
        var makeId: PersistenceIdFactory
        var exerciseNameSnapshot: ((String) -> String?)?
        var sourceWorkoutId: String?
    }

    static func createFreeDraft(_ input: FreeDraftInput) throws -> PersistedActiveWorkoutDraft {
        try assertTimestamp(input.startedAt, "workout start")
        guard !input.draftId.isEmpty else { throw TrainingPersistenceError("Missing workout identity") }

        return PersistedActiveWorkoutDraft(
            id: input.draftId,
            sourceWorkoutId: input.sourceWorkoutId,
            plannedProgramId: nil,
            plannedSessionId: nil,
            startedAt: input.startedAt,
            exercises: try input.exerciseIds.map { exerciseId in
                guard !exerciseId.isEmpty else {
                    throw TrainingPersistenceError("Missing exercise identity")
                }
                return PersistedActiveExerciseDraft(
                    id: input.makeId(.exercise),
                    exerciseId: exerciseId,
                    plannedExerciseId: nil,
                    exerciseNameSnapshot: input.exerciseNameSnapshot?(exerciseId),
                    sets: []
                )
            }
        )
    }

    static func recordSetObservation(
        _ draft: PersistedActiveWorkoutDraft,
        exerciseEntryId: String,
        setDraftId: String,
        observation: PersistedSetObservation
    ) throws -> PersistedActiveWorkoutDraft {
        try assertObservation(observation)
        var next = draft
        var found = false
        for exerciseIndex in next.exercises.indices
        where next.exercises[exerciseIndex].id == exerciseEntryId {
            for setIndex in next.exercises[exerciseIndex].sets.indices
            where next.exercises[exerciseIndex].sets[setIndex].id == setDraftId {
                next.exercises[exerciseIndex].sets[setIndex].observation = observation
                found = true
            }
        }
        guard found else { throw TrainingPersistenceError("Active workout set not found") }
        return next
    }

    static func addUnplannedSet(
        _ draft: PersistedActiveWorkoutDraft,
        exerciseEntryId: String,
        setDraftId: String,
        setType: SetType,
        side: SetSide,
        observation: PersistedSetObservation? = nil
    ) throws -> PersistedActiveWorkoutDraft {
        if let observation { try assertObservation(observation) }
        var next = draft
        guard let exerciseIndex = next.exercises.firstIndex(where: { $0.id == exerciseEntryId }) else {
            throw TrainingPersistenceError("Active workout exercise not found")
        }
        let duplicate = next.exercises.contains { $0.sets.contains { $0.id == setDraftId } }
        guard !duplicate else { throw TrainingPersistenceError("Duplicate active set ID") }

        next.exercises[exerciseIndex].sets.append(PersistedActiveSetDraft(
            id: setDraftId,
            plannedSetId: nil,
            setType: setType,
            side: side,
            target: nil,
            observation: observation
        ))
        return next
    }

    static func substituteExercise(
        _ draft: PersistedActiveWorkoutDraft,
        exerciseEntryId: String,
        exerciseId: String,
        exerciseNameSnapshot: String?
    ) throws -> PersistedActiveWorkoutDraft {
        guard !exerciseId.isEmpty else {
            throw TrainingPersistenceError("Missing substitute exercise identity")
        }
        var next = draft
        guard let index = next.exercises.firstIndex(where: { $0.id == exerciseEntryId }) else {
            throw TrainingPersistenceError("Active workout exercise not found")
        }
        guard !next.exercises[index].sets.contains(where: { $0.observation != nil }) else {
            throw TrainingPersistenceError(
                "Keep the recorded exercise; add the replacement as a new exercise"
            )
        }
        next.exercises[index].exerciseId = exerciseId
        next.exercises[index].exerciseNameSnapshot = exerciseNameSnapshot
        return next
    }

    /// Deterministic completion transition. Planned targets without a completed
    /// observation disappear from history; they remain available through the
    /// immutable program snapshot.
    static func complete(
        _ draft: PersistedActiveWorkoutDraft,
        sessionId: String,
        completedAt: String,
        status: CompletedSession.Status,
        makeId: PersistenceIdFactory
    ) throws -> PersistedCompletedSession {
        try assertTimestamp(completedAt, "workout completion")
        guard !sessionId.isEmpty else {
            throw TrainingPersistenceError("Missing completed session identity")
        }
        let startedAtMillis = ISOTime.parse(draft.startedAt) ?? 0
        let completedAtMillis = ISOTime.parse(completedAt) ?? 0
        guard completedAtMillis >= startedAtMillis else {
            throw TrainingPersistenceError("Workout completion predates start")
        }

        var exercises: [PersistedCompletedExercise] = []
        for exercise in draft.exercises {
            var sets: [CompletedSet] = []
            for set in exercise.sets {
                guard let observation = set.observation, observation.completed else { continue }
                try assertObservation(observation)
                guard let reps = observation.reps, reps >= 1, let resistance = observation.resistance else {
                    throw TrainingPersistenceError("Completed set is missing actual reps or resistance")
                }
                if let timestamp = observation.timestamp {
                    let at = ISOTime.parse(timestamp) ?? .nan
                    guard at >= startedAtMillis, at <= completedAtMillis else {
                        throw TrainingPersistenceError("Completed set timestamp is outside workout")
                    }
                }
                sets.append(CompletedSet(
                    id: makeId(.set),
                    plannedSetId: set.plannedSetId,
                    reps: reps,
                    resistance: resistance,
                    rir: observation.rir,
                    rpe: observation.rpe,
                    completed: true,
                    setType: set.setType,
                    side: set.side,
                    timestamp: observation.timestamp
                ))
            }
            guard !sets.isEmpty else { continue }
            exercises.append(PersistedCompletedExercise(
                id: makeId(.exercise),
                exerciseId: exercise.exerciseId,
                plannedExerciseId: exercise.plannedExerciseId,
                exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                sets: sets
            ))
        }

        guard !exercises.isEmpty else {
            throw TrainingPersistenceError("Complete at least one set before saving")
        }

        // A session somebody left open overnight has a span, not a training
        // duration. Rather than refuse to record the sets that were genuinely
        // performed — or invent a plausible number for the hours in between —
        // the work is kept and the duration is left unknown. The raw
        // timestamps are untouched either way.
        let span = (completedAtMillis - startedAtMillis) / 1000
        return PersistedCompletedSession(
            id: sessionId,
            sourceWorkoutId: draft.sourceWorkoutId,
            plannedProgramId: draft.plannedProgramId,
            plannedSessionId: draft.plannedSessionId,
            startedAt: draft.startedAt,
            completedAt: completedAt,
            durationSeconds: span <= MAX_SESSION_DURATION_SECONDS ? span : nil,
            status: status,
            exercises: exercises
        )
    }

    /// How much of a planned session's prescribed work has actually been done.
    struct PlannedWorkCoverage {
        /// Working sets the prescription asked for.
        var prescribed: Int
        /// Of those, the ones answered by a real completed observation.
        var performed: Int
        /// Whether the prescription itself could be read out of its snapshot.
        var verified: Bool
        /// Whether the whole prescription was verifiably carried out.
        var complete: Bool
    }

    /// Coverage follows planned identity rather than exercise identity, so a
    /// substituted exercise still answers the prescription its `plannedSetId`
    /// lineage points at, while an extra set — which has no `plannedSetId` — is
    /// real work that can never stand in for a prescribed set nobody performed.
    ///
    /// Returns nil for a free workout: there is no prescription to cover.
    static func plannedWorkCoverage(
        _ draft: PersistedActiveWorkoutDraft,
        _ session: PlannedSession?
    ) -> PlannedWorkCoverage? {
        guard let plannedSessionId = draft.plannedSessionId else { return nil }

        let source = session?.id == plannedSessionId ? session : nil
        let prescribed: Set<String> = {
            if let source {
                return Set(source.exercises.flatMap { $0.workingSets.map(\.id) })
            }
            // Its snapshot is unreadable, so there is nothing to be measured
            // against. What the draft still lists says how much work is in
            // flight, but a prescription nobody can read is never certified.
            return Set(draft.exercises.flatMap { exercise in
                exercise.sets.compactMap { set in
                    (set.plannedSetId != nil && set.setType != .warmup) ? set.plannedSetId : nil
                }
            })
        }()

        var performed = Set<String>()
        for exercise in draft.exercises {
            for set in exercise.sets {
                guard let plannedSetId = set.plannedSetId,
                      set.observation?.completed == true,
                      prescribed.contains(plannedSetId)
                else { continue }
                performed.insert(plannedSetId)
            }
        }

        return PlannedWorkCoverage(
            prescribed: prescribed.count,
            performed: performed.count,
            verified: source != nil,
            complete: source != nil && performed.count == prescribed.count
        )
    }
}
