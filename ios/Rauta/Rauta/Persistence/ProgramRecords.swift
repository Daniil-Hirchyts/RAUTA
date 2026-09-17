import Foundation

nonisolated enum ProgramRecords {
    /// The snapshot keeps the policy as raw JSON so it is restored verbatim,
    /// never replaced by the current default.
    static func toPersistedSnapshot(_ program: TrainingProgram) -> PersistedProgramSnapshot {
        PersistedProgramSnapshot(
            id: program.id,
            engineVersion: program.engineVersion,
            policyVersion: program.policyVersion,
            policy: program.policy.jsonTree,
            datasetFingerprint: program.datasetFingerprint,
            generatedAt: program.generatedAt,
            goal: program.goal,
            durationWeeks: program.durationWeeks,
            weeks: program.weeks,
            diagnostics: program.diagnostics,
            adaptation: program.adaptation
        )
    }

    static func toEngineProgram(_ snapshot: PersistedProgramSnapshot) -> TrainingProgram {
        TrainingProgram(
            id: snapshot.id,
            engineVersion: snapshot.engineVersion,
            policyVersion: snapshot.policyVersion,
            policy: JSONCoding.value(snapshot.policy, as: TrainingPolicy.self) ?? DEFAULT_POLICY,
            datasetFingerprint: snapshot.datasetFingerprint,
            generatedAt: snapshot.generatedAt,
            goal: snapshot.goal,
            durationWeeks: snapshot.durationWeeks,
            weeks: snapshot.weeks,
            diagnostics: snapshot.diagnostics,
            adaptation: snapshot.adaptation
        )
    }

    struct RecordOptions {
        var kind: PersistedProgramRecord.Kind?
        var lifecycle: PersistedProgramRecord.Lifecycle?
        var manualSourceProgramId: String?
        var manualRevisionAt: String?
        var incorporatedSessionIds: [String]?
        var replacedSessionIds: [String]?

        init(
            kind: PersistedProgramRecord.Kind? = nil,
            lifecycle: PersistedProgramRecord.Lifecycle? = nil,
            manualSourceProgramId: String? = nil,
            manualRevisionAt: String? = nil,
            incorporatedSessionIds: [String]? = nil,
            replacedSessionIds: [String]? = nil
        ) {
            self.kind = kind
            self.lifecycle = lifecycle
            self.manualSourceProgramId = manualSourceProgramId
            self.manualRevisionAt = manualRevisionAt
            self.incorporatedSessionIds = incorporatedSessionIds
            self.replacedSessionIds = replacedSessionIds
        }
    }

    static func createRecord(
        _ program: TrainingProgram,
        options: RecordOptions = RecordOptions()
    ) -> PersistedProgramRecord {
        let snapshot = toPersistedSnapshot(program)

        var revision: PersistedProgramRevision?
        if let adaptation = program.adaptation {
            revision = PersistedProgramRevision(
                sourceProgramId: adaptation.sourceProgramId,
                reason: adaptation.mode == .remainingWeek ? .remainingWeek : .nextWeek,
                asOf: adaptation.asOf,
                incorporatedSessionIds: options.incorporatedSessionIds,
                replacedSessionIds: options.replacedSessionIds
            )
        } else if let manualSourceProgramId = options.manualSourceProgramId {
            revision = PersistedProgramRevision(
                sourceProgramId: manualSourceProgramId,
                reason: .manualRegeneration,
                asOf: options.manualRevisionAt ?? program.generatedAt,
                incorporatedSessionIds: nil,
                replacedSessionIds: options.replacedSessionIds
            )
        }

        return PersistedProgramRecord(
            id: program.id,
            kind: options.kind,
            lifecycle: options.lifecycle ?? .active,
            createdAt: program.generatedAt,
            snapshot: snapshot,
            revision: revision
        )
    }

    /// A revision withdraws only the future slots it replaced. Historical
    /// prescriptions remain readable even when their source is archived.
    static func isSupersededPlannedSession(
        _ data: PersistedTrainingState,
        _ programId: String,
        _ sessionId: String
    ) -> Bool {
        data.programs.contains { program in
            guard let revision = program.revision,
                  revision.sourceProgramId == programId,
                  revision.reason == .remainingWeek || revision.reason == .manualRegeneration
            else { return false }

            if let replaced = revision.replacedSessionIds {
                return replaced.contains(sessionId)
            }

            // Compatibility with revisions saved before explicit slot metadata.
            let source = data.programs.first { $0.id == programId }
            let session = source?.snapshot.weeks
                .flatMap(\.sessions)
                .first { $0.id == sessionId }
            guard let session, session.scheduledAt > revision.asOf else { return false }
            return program.snapshot.weeks.contains { week in
                week.sessions.contains { $0.scheduledAt == session.scheduledAt }
            }
        }
    }

    /// Planned sessions are startable only from the active revision. Archived
    /// snapshots remain readable as history, but an unperformed old projection
    /// cannot be resumed as if it still belonged to the current prescription.
    static func isStartablePlannedSession(
        _ data: PersistedTrainingState,
        _ programId: String,
        _ sessionId: String
    ) -> Bool {
        guard let program = data.programs.first(where: { $0.id == programId }) else { return false }
        let currentRevision = program.effectiveKind == .workout
            || (data.activeProgramId == programId && program.lifecycle == .active)
        let hasSession = program.snapshot.weeks.contains { week in
            week.sessions.contains { $0.id == sessionId }
        }
        return currentRevision
            && hasSession
            && !isSupersededPlannedSession(data, programId, sessionId)
    }
}

// MARK: - History

nonisolated struct LegacyWorkoutObservation {
    var id: String
    var completion: LegacyWorkouts.LegacyCompletion?
}

nonisolated enum PersistedHistory {
    private static func toEngineSession(_ session: PersistedCompletedSession) -> CompletedSession {
        var order: [String] = []
        var byExercise: [String: [CompletedSet]] = [:]
        for entry in session.exercises {
            if byExercise[entry.exerciseId] == nil {
                byExercise[entry.exerciseId] = []
                order.append(entry.exerciseId)
            }
            byExercise[entry.exerciseId]?.append(contentsOf: entry.sets)
        }
        return CompletedSession(
            id: session.id,
            plannedSessionId: session.plannedSessionId,
            startedAt: session.startedAt,
            completedAt: session.completedAt,
            durationSeconds: session.durationSeconds,
            status: session.status,
            exercises: order.map { CompletedExercise(exerciseId: $0, sets: byExercise[$0] ?? []) }
        )
    }

    /// Structured sessions are lossless; legacy workouts contribute identity and
    /// time and zero fictional sets.
    static func toTrainingHistory(
        _ state: PersistedTrainingState,
        legacyWorkouts: [LegacyWorkoutObservation] = []
    ) -> TrainingHistory {
        let structured = state.sessions.map(toEngineSession)

        // A workout performed with structured logging is one session, not two:
        // its legacy record names the same workout and would otherwise be
        // counted again as a second, set-less exposure.
        var structuredIds = Set(state.sessions.map(\.id))
        for session in state.sessions {
            if let sourceWorkoutId = session.sourceWorkoutId { structuredIds.insert(sourceWorkoutId) }
        }

        let legacy = legacyWorkouts.compactMap { workout -> CompletedSession? in
            guard !structuredIds.contains(workout.id) else { return nil }
            return LegacyWorkouts.adapt(id: workout.id, completion: workout.completion)
        }

        let sessions = (structured + legacy).sorted { left, right in
            if left.startedAt != right.startedAt {
                return left.startedAt.compare(right.startedAt) == .orderedAscending
            }
            return left.id.compare(right.id) == .orderedAscending
        }

        let coverage = state.settings.historyCoverage
        if coverage.status == .complete {
            return TrainingHistory(
                sessions: sessions,
                coverage: .complete,
                coverageStart: coverage.coverageStart
            )
        }
        return TrainingHistory(sessions: sessions, coverage: .unknown, coverageStart: nil)
    }
}
