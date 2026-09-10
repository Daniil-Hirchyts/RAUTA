import Foundation

/// Putting one workout back together after a relaunch.
///
/// A running workout lives in three stores that persist independently: the
/// workout itself, the clock and check marks, and the sets that were actually
/// performed. A relaunch restores them one at a time, so whatever the last write
/// did not reach comes back describing a different workout than its neighbours.
///
/// The rules are fixed and ordered, and they resolve every conflict the same way
/// every time:
///
/// - **Observations outrank everything.** The draft is the only record of work
///   that was really done.
/// - **Nothing is invented.** Recovery never mints a set, an observation or a
///   planned identity.
/// - **A workout is completed once.**
/// - **Empty is discarded, not recorded.**
/// - **Irreconcilable state fails closed**, and the observations survive it.
enum ReconciliationReason: String {
    /// Nothing was restored; there is no session to put back together.
    case idle
    /// The three pieces already agree.
    case coherent
    /// A shell with no structured record behind it: it can log nothing.
    case sessionWithoutDraft = "session-without-draft"
    /// Shell and draft name different workouts.
    case workoutMismatch = "workout-mismatch"
    /// The workout being performed is gone.
    case workoutMissing = "workout-missing"
    /// The workout was already completed while this state survived.
    case workoutCompleted = "workout-completed"
    /// History already holds this workout's or prescription's session.
    case alreadyRecorded = "already-recorded"
    /// Shell and draft disagree about the prescription, or it cannot be read.
    case plannedLineageMismatch = "planned-lineage-mismatch"
    /// Real observations outlived the shell that was collecting them.
    case draftWithoutSession = "draft-without-session"
}

struct SessionReconciliation {
    /// `keep` leaves the draft live. `close` writes its observations to history
    /// as a partial session, and leaves nothing behind when it holds none.
    /// `discard` drops it whole — only ever when history already holds it.
    var draft: DraftDisposition
    /// Whether the live UI session survives.
    var session: ShellKeep
    var reason: ReconciliationReason

    enum ShellKeep: String { case keep, clear }
}

@MainActor
enum SessionReconciler {
    /// Whether history already holds a session for this workout or prescription.
    private static func alreadyRecorded(
        _ training: PersistedTrainingState,
        _ draft: PersistedActiveWorkoutDraft
    ) -> Bool {
        training.sessions.contains { recorded in
            if let plannedSessionId = draft.plannedSessionId,
               recorded.plannedSessionId == plannedSessionId { return true }
            if let sourceWorkoutId = draft.sourceWorkoutId,
               recorded.sourceWorkoutId == sourceWorkoutId,
               recorded.startedAt == draft.startedAt { return true }
            // A free draft carries no workout to be identified by, so the instant
            // it started is its identity.
            if draft.sourceWorkoutId == nil, draft.plannedSessionId == nil,
               recorded.sourceWorkoutId == nil, recorded.plannedSessionId == nil,
               recorded.startedAt == draft.startedAt { return true }
            return false
        }
    }

    /// Whether the shell, the draft and the program snapshot tell one story
    /// about the prescription being performed.
    private static func plannedLineageHolds(
        _ training: PersistedTrainingState,
        _ workout: Workout?,
        _ draft: PersistedActiveWorkoutDraft
    ) -> Bool {
        if let workout {
            let shell = workout.planned
            if (shell != nil) != (draft.plannedSessionId != nil) { return false }
            if let shell,
               shell.programId != draft.plannedProgramId
                || shell.sessionId != draft.plannedSessionId { return false }
        }
        guard let plannedSessionId = draft.plannedSessionId else { return true }
        guard let record = training.programs.first(where: { $0.id == draft.plannedProgramId })
        else { return false }
        return record.snapshot.weeks.contains { week in
            week.sessions.contains { $0.id == plannedSessionId }
        }
    }

    struct Input {
        var session: ActiveWorkoutSession?
        var training: PersistedTrainingState
        var workouts: [Workout]
    }

    /// The decision, from the restored pieces alone. Pure and total: same input,
    /// same outcome, no stores and no clock.
    static func plan(_ input: Input) -> SessionReconciliation {
        let draft = input.training.activeWorkout

        guard let draft else {
            return input.session != nil
                // The shell survived without the record behind it. It can no
                // longer log a set, so the shell is what goes.
                ? SessionReconciliation(draft: .keep, session: .clear, reason: .sessionWithoutDraft)
                : SessionReconciliation(draft: .keep, session: .keep, reason: .idle)
        }

        if alreadyRecorded(input.training, draft) {
            return SessionReconciliation(draft: .discard, session: .clear, reason: .alreadyRecorded)
        }

        // The shell says which workout the set editor is pointed at and the draft
        // says which one the sets land in.
        if let session = input.session, session.workoutId != draft.sourceWorkoutId {
            return SessionReconciliation(draft: .close, session: .clear, reason: .workoutMismatch)
        }

        let workout = draft.sourceWorkoutId.flatMap { id in
            input.workouts.first { $0.id == id }
        }

        if draft.sourceWorkoutId != nil, workout == nil {
            return SessionReconciliation(draft: .close, session: .clear, reason: .workoutMissing)
        }
        if workout?.completion != nil {
            return SessionReconciliation(draft: .close, session: .clear, reason: .workoutCompleted)
        }
        if !plannedLineageHolds(input.training, workout, draft) {
            return SessionReconciliation(
                draft: .close, session: .clear, reason: .plannedLineageMismatch
            )
        }

        // The work is real and the prescription it answers is intact; only the
        // shell that was collecting it is missing.
        if input.session == nil {
            return SessionReconciliation(draft: .close, session: .keep, reason: .draftWithoutSession)
        }

        return SessionReconciliation(draft: .keep, session: .keep, reason: .coherent)
    }

    /// Applies the draft half of the decision and reports it, so the caller can
    /// apply the shell half against its own store. Idempotent by construction.
    @discardableResult
    static func reconcileRestoredSession(_ session: ActiveWorkoutSession?) -> SessionReconciliation {
        let store = TrainingRecordsStore.shared
        let decision = plan(Input(
            session: session,
            training: store.data,
            workouts: WorkoutsStore.shared.workouts
        ))

        if let draft = store.data.activeWorkout, decision.draft != .keep {
            // Unclosable means unreadable, not worthless: the draft stays put
            // with its observations rather than being cleared for tidiness.
            if decision.draft == .close {
                // Writes a partial session when the draft holds observations and
                // clears it when it does not.
                _ = try? store.abortWorkout(
                    completedAt: TrainingSessionBridge.draftClosingTime(draft)
                )
            } else {
                try? store.cancelWorkout()
            }
        }

        return decision
    }
}
