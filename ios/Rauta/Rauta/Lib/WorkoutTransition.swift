import Foundation

/// Starting, finishing and cancelling a workout, as transitions that survive
/// being interrupted.
///
/// Each of those actions is one thing to the person doing it and several writes
/// to separately persisted stores underneath. This module writes down what is
/// about to happen before it happens, runs the steps, and clears the note when
/// they have all landed. A relaunch in the middle finds the note and finishes
/// the same steps rather than inferring what probably happened.
@MainActor
enum WorkoutTransition {
    private static func pendingIntent(
        _ kind: PersistedTransitionIntent.Kind,
        _ workoutId: String
    ) throws -> PersistedTransitionIntent? {
        let pending = TrainingRecordsStore.shared.data.transition
        if let pending, pending.kind != kind || pending.sourceWorkoutId != workoutId {
            throw TrainingPersistenceError("Finish recovering the pending workout transition first")
        }
        return pending
    }

    private static func makeId(_ prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString.lowercased())"
    }

    /// Writes the intent to start `workout` before its draft exists.
    ///
    /// The shell the start will expose is fixed here too, so a relaunch between
    /// the draft landing and the shell appearing can put back the session the
    /// person was already looking at instead of losing it.
    @discardableResult
    static func recordStartIntent(_ workout: Workout, startedAtMs: Double) throws
        -> PersistedTransitionIntent {
        if let pending = try pendingIntent(.start, workout.id) { return pending }
        let intent = PersistedTransitionIntent(
            id: makeId("transition"),
            kind: .start,
            recordedAt: ISOTime.string(fromMillis: startedAtMs),
            sourceWorkoutId: workout.id,
            draftId: nil,
            planned: workout.planned.map {
                PersistedPlannedReference(programId: $0.programId, sessionId: $0.sessionId)
            },
            shell: PersistedTransitionShell(
                workoutName: workout.name,
                workoutDate: CalendarDate.toISO(Date(timeIntervalSince1970: startedAtMs / 1000)),
                exerciseIds: workout.exerciseIds,
                startedAtMs: startedAtMs
            ),
            completedAt: nil,
            sessionId: nil,
            status: nil,
            legacy: nil
        )
        try TrainingRecordsStore.shared.beginTransition(intent)
        return intent
    }

    /// Writes the intent to finish `session`, with every identity and instant
    /// the finish will use already decided.
    ///
    /// One completion instant is read from the clock here and reused by every
    /// step, including a replay: recovery that read the clock again would give a
    /// resumed finish a different duration than the one the person saw.
    @discardableResult
    static func recordFinishIntent(
        _ session: ActiveWorkoutSession,
        durationMs: Double,
        completedAt: String? = nil
    ) throws -> PersistedTransitionIntent {
        if let pending = try pendingIntent(.finish, session.workoutId) { return pending }
        let completedAt = completedAt ?? ISOTime.now()
        let settings = SettingsStore.shared
        let draft = TrainingRecordsStore.shared.data.activeWorkout
        if let draft, draft.sourceWorkoutId != session.workoutId {
            throw TrainingPersistenceError("The active workout and its training draft do not match")
        }
        // An exercise counts as performed if it was checked off or if it holds
        // real sets, so the saved workout cannot claim less than the structured
        // session.
        let performed = TrainingSessionBridge.performedExerciseIds()
        let covered = TrainingSessionBridge.activePlannedCoverage()?.complete ?? true

        let planned: PersistedPlannedReference? = {
            guard let programId = draft?.plannedProgramId,
                  let sessionId = draft?.plannedSessionId
            else { return nil }
            return PersistedPlannedReference(programId: programId, sessionId: sessionId)
        }()

        let intent = PersistedTransitionIntent(
            id: makeId("transition"),
            kind: .finish,
            recordedAt: completedAt,
            sourceWorkoutId: session.workoutId,
            draftId: draft?.id,
            planned: planned,
            shell: nil,
            completedAt: completedAt,
            sessionId: makeId("training-session"),
            status: covered ? .completed : .partial,
            legacy: PersistedLegacyCompletionIntent(
                startedAt: ISOTime.string(fromMillis: session.startedAt),
                completedAt: completedAt,
                durationMs: durationMs,
                activeCalories: WorkoutStats.estimateStrengthCalories(
                    durationMs, bodyWeightKg: settings.healthBodyWeightKg
                ),
                completedExerciseIds: session.exerciseIds.filter {
                    session.completedIds.contains($0) || performed.contains($0)
                },
                healthSyncStatus: settings.appleHealthEnabled && settings.autoSyncWorkouts
                    ? .pending
                    : .notRequested
            )
        )
        try TrainingRecordsStore.shared.beginTransition(intent)
        return intent
    }

    /// Writes the intent to discard `session`. A cancelled session is partial
    /// however much of it was performed, so no status has to be decided.
    @discardableResult
    static func recordCancelIntent(_ session: ActiveWorkoutSession) throws
        -> PersistedTransitionIntent {
        if let pending = try pendingIntent(.cancel, session.workoutId) { return pending }
        let draft = TrainingRecordsStore.shared.data.activeWorkout
        let intent = PersistedTransitionIntent(
            id: makeId("transition"),
            kind: .cancel,
            recordedAt: ISOTime.now(),
            sourceWorkoutId: session.workoutId,
            draftId: draft?.id,
            planned: nil,
            shell: nil,
            completedAt: draft.map { TrainingSessionBridge.draftClosingTime($0) } ?? ISOTime.now(),
            sessionId: makeId("training-session"),
            status: nil,
            legacy: nil
        )
        try TrainingRecordsStore.shared.beginTransition(intent)
        return intent
    }

    /// Applies the legacy completion an intent still owes. An existing
    /// completion is never replaced: the first one the person saw stands.
    private static func applyLegacy(_ recovery: TransitionRecovery) {
        guard let owed = recovery.legacy else { return }
        WorkoutsStore.shared.completeWorkout(owed.workoutId, WorkoutCompletion(
            startedAt: owed.intent.startedAt,
            completedAt: owed.intent.completedAt,
            durationMs: owed.intent.durationMs,
            completedExerciseIds: owed.intent.completedExerciseIds,
            activeCalories: owed.intent.activeCalories,
            healthSyncStatus: owed.intent.healthSyncStatus == .pending ? .pending : .notRequested
        ))
    }

    /// Closes the draft under the identity and instant the intent fixed, so a
    /// replay lands on the same session rather than adding another.
    ///
    /// - Returns: why the draft could not be closed, when it could not. This
    ///   used to be discarded, which is how a finish could report success while
    ///   history never received the session — the caller needs it to tell the
    ///   truth.
    private static func applyDraft(_ recovery: TransitionRecovery) -> String? {
        let store = TrainingRecordsStore.shared
        guard let draft = store.data.activeWorkout else { return nil }
        if recovery.draft == .discard {
            do { try store.cancelWorkout() } catch { return message(error) }
            return nil
        }
        guard recovery.draft == .close else { return nil }

        let hasObservations = draft.exercises.contains { exercise in
            exercise.sets.contains { $0.observation?.completed == true }
        }
        // Nothing performed leaves no structured session at all, whatever the
        // intent hoped for: an interrupted finish must not become fiction.
        guard hasObservations else {
            do { try store.cancelWorkout() } catch { return message(error) }
            return nil
        }

        let coverageComplete = TrainingSessionBridge.activePlannedCoverage()?.complete ?? true
        let status: CompletedSession.Status = (recovery.close?.status == .completed && coverageComplete)
            ? .completed
            : .partial
        do {
            _ = try store.completeWorkout(
                status: status,
                completedAt: recovery.close?.completedAt
                    ?? TrainingSessionBridge.draftClosingTime(draft),
                sessionId: recovery.close?.sessionId
            )
        } catch {
            return message(error)
        }
        return nil
    }

    private static func message(_ error: Error) -> String {
        if let error = error as? TrainingPersistenceError { return error.message }
        if let error = error as? TrainingPersistenceValidationError {
            return error.issues.first?.message ?? "This session could not be recorded."
        }
        return error.localizedDescription
    }

    /// Finishes whatever transition was in flight when the app stopped. Returns
    /// the shell half for the caller to apply. Safe to run repeatedly.
    @discardableResult
    static func recoverWorkoutTransition(
        shellWorkoutId: String? = nil,
        shellStartedAtMs: Double? = nil
    ) -> TransitionRecovery {
        var ignored: String?
        return recoverWorkoutTransition(
            shellWorkoutId: shellWorkoutId,
            shellStartedAtMs: shellStartedAtMs,
            draftFailure: &ignored
        )
    }

    /// The same, reporting any write the draft half refused.
    @discardableResult
    static func recoverWorkoutTransition(
        shellWorkoutId: String? = nil,
        shellStartedAtMs: Double? = nil,
        draftFailure: inout String?
    ) -> TransitionRecovery {
        let store = TrainingRecordsStore.shared
        let intent = store.data.transition
        let draft = store.data.activeWorkout
        let workout = WorkoutsStore.shared.workouts.first { $0.id == intent?.sourceWorkoutId }

        let recovery = TransitionPlanner.plan(TransitionPlanner.Input(
            intent: intent,
            draft: draft,
            sessions: store.data.sessions,
            workoutCompleted: workout?.completion != nil,
            workoutExists: workout != nil,
            shellWorkoutId: shellWorkoutId,
            shellStartedAtMs: shellStartedAtMs
        ))
        if recovery.reason == .none { return recovery }

        if let intent, intent.kind == .start, let shell = intent.shell,
           recovery.reason == .startResumed || recovery.reason == .startSettled,
           let workout, workout.completion == nil, workout.date != shell.workoutDate {
            WorkoutsStore.shared.updateWorkout(
                workout.id, WorkoutsStore.WorkoutPatch(date: shell.workoutDate)
            )
        }
        // The structured record goes first. If it refuses, the workout is not
        // yet marked complete, the running session is untouched, and finishing
        // can simply be tried again — which is what a failure has to leave
        // behind. Doing it the other way round completes the workout, which
        // ends the session out from under a finish that did not happen.
        draftFailure = applyDraft(recovery)
        guard draftFailure == nil else { return recovery }
        applyLegacy(recovery)

        return recovery
    }

    /// Clears the journal entry for a transition that ran to completion.
    static func settleWorkoutTransition() {
        try? TrainingRecordsStore.shared.clearTransition()
    }

    /// The structured session a finish wrote, looked for the same way recovery
    /// decides a finish is already written.
    ///
    /// Nil is a real answer: a session where nothing was logged writes no
    /// structured record at all, because inventing one would be fiction.
    static func recordedSession(
        sessionId: String?,
        workoutId: String,
        startedAt: String?
    ) -> PersistedCompletedSession? {
        let sessions = TrainingRecordsStore.shared.data.sessions
        if let sessionId, let match = sessions.first(where: { $0.id == sessionId }) { return match }
        guard let startedAt else { return nil }
        return sessions.first { $0.sourceWorkoutId == workoutId && $0.startedAt == startedAt }
    }

    /// Whether a finish that has run left every record it promised.
    ///
    /// Returns the reason it did not, so the player can say something true
    /// instead of closing on a save that never happened.
    static func unfinishedFinishReason(
        workoutId: String,
        expectedStructuredSession: Bool,
        sessionId: String?,
        draftStartedAt: String?
    ) -> String? {
        if TrainingRecordsStore.shared.data.activeWorkout != nil {
            return "The session is still open, so nothing was filed away yet."
        }
        if let workout = WorkoutsStore.shared.workout(workoutId), workout.completion == nil {
            return "This workout is not marked complete yet."
        }
        if expectedStructuredSession,
           recordedSession(
               sessionId: sessionId, workoutId: workoutId, startedAt: draftStartedAt
           ) == nil {
            return "Your logged sets have not reached your training history yet."
        }
        return nil
    }
}
