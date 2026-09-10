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
    private static func applyDraft(_ recovery: TransitionRecovery) {
        let store = TrainingRecordsStore.shared
        guard let draft = store.data.activeWorkout else { return }
        if recovery.draft == .discard {
            try? store.cancelWorkout()
            return
        }
        guard recovery.draft == .close else { return }

        let hasObservations = draft.exercises.contains { exercise in
            exercise.sets.contains { $0.observation?.completed == true }
        }
        // Nothing performed leaves no structured session at all, whatever the
        // intent hoped for: an interrupted finish must not become fiction.
        guard hasObservations else {
            try? store.cancelWorkout()
            return
        }

        let coverageComplete = TrainingSessionBridge.activePlannedCoverage()?.complete ?? true
        let status: CompletedSession.Status = (recovery.close?.status == .completed && coverageComplete)
            ? .completed
            : .partial
        _ = try? store.completeWorkout(
            status: status,
            completedAt: recovery.close?.completedAt
                ?? TrainingSessionBridge.draftClosingTime(draft),
            sessionId: recovery.close?.sessionId
        )
    }

    /// Finishes whatever transition was in flight when the app stopped. Returns
    /// the shell half for the caller to apply. Safe to run repeatedly.
    @discardableResult
    static func recoverWorkoutTransition(
        shellWorkoutId: String? = nil,
        shellStartedAtMs: Double? = nil
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
        applyLegacy(recovery)
        applyDraft(recovery)

        return recovery
    }

    /// Clears the journal entry for a transition that ran to completion.
    static func settleWorkoutTransition() {
        try? TrainingRecordsStore.shared.clearTransition()
    }
}
