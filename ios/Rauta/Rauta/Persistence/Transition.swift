import Foundation

/// Carrying an interrupted workout transition forward.
///
/// Starting and finishing a workout are single actions to the person doing them
/// and several writes to independently persisted stores underneath. An intent
/// fixes that by being written first: it names the transition, the identities it
/// will use and — for a finish — the single instant it completes at, so
/// replaying it any number of times reaches the same result as running it once.
///
/// What an intent is not is evidence. It carries identities, times and the
/// legacy shell's own numbers; which sets were performed lives only in the
/// draft's observations, and nothing here writes one.
enum TransitionRecoveryReason: String {
    /// No intent was in flight.
    case none
    /// A start that never created its draft; nothing happened to carry forward.
    case startAbandoned = "start-abandoned"
    /// A start whose draft landed but whose shell never appeared.
    case startResumed = "start-resumed"
    /// A start already complete in both stores.
    case startSettled = "start-settled"
    /// A finish with steps still owed.
    case finishResumed = "finish-resumed"
    /// A finish whose session history already holds.
    case finishSettled = "finish-settled"
    /// A cancel with its draft still open.
    case cancelResumed = "cancel-resumed"
    /// An intent naming a draft that is not the one in hand.
    case intentStale = "intent-stale"
}

enum DraftDisposition: String { case keep, close, discard }
enum ShellDisposition: String { case keep, clear, restore }

struct TransitionClose {
    var sessionId: String
    var completedAt: String
    var status: CompletedSession.Status
}

struct TransitionLegacy {
    var workoutId: String
    var intent: PersistedLegacyCompletionIntent
}

struct TransitionShellRestore {
    var workoutId: String
    var workoutName: String
    var workoutDate: String
    var exerciseIds: [String]
    var startedAtMs: Double
}

/// Each step recovery may still owe, decided from the state that came back.
struct TransitionRecovery {
    var draft: DraftDisposition
    var close: TransitionClose?
    var legacy: TransitionLegacy?
    var shell: ShellDisposition
    var restore: TransitionShellRestore?
    var clearIntent: Bool
    var reason: TransitionRecoveryReason

    static let nothing = TransitionRecovery(
        draft: .keep, close: nil, legacy: nil, shell: .keep,
        restore: nil, clearIntent: false, reason: .none
    )
}

enum TransitionPlanner {
    struct Input {
        var intent: PersistedTransitionIntent?
        var draft: PersistedActiveWorkoutDraft?
        var sessions: [PersistedCompletedSession]
        /// Whether the application workout already carries a legacy completion.
        var workoutCompleted: Bool
        /// Whether the application workout still exists at all.
        var workoutExists: Bool
        /// The workout a live shell is already running, when there is one.
        var shellWorkoutId: String?
        var shellStartedAtMs: Double?
    }

    /// Whether history already holds the session this finish would write.
    private static func alreadyWritten(
        _ sessions: [PersistedCompletedSession],
        _ intent: PersistedTransitionIntent,
        _ draft: PersistedActiveWorkoutDraft?
    ) -> Bool {
        let fallbackStartedAt: String? = draft?.startedAt
            ?? intent.legacy?.startedAt
            ?? intent.shell.map { ISOTime.string(fromMillis: $0.startedAtMs) }

        return sessions.contains { session in
            if let sessionId = intent.sessionId, session.id == sessionId { return true }
            if let plannedSessionId = draft?.plannedSessionId,
               session.plannedSessionId == plannedSessionId { return true }
            if session.sourceWorkoutId == intent.sourceWorkoutId,
               let fallbackStartedAt, session.startedAt == fallbackStartedAt { return true }
            return false
        }
    }

    /// Whether the draft in hand is the one the intent was written about.
    private static func draftMatches(
        _ intent: PersistedTransitionIntent,
        _ draft: PersistedActiveWorkoutDraft?
    ) -> Bool {
        guard let draft else { return false }
        guard draft.sourceWorkoutId == intent.sourceWorkoutId else { return false }
        if let draftId = intent.draftId, draft.id != draftId { return false }
        if intent.kind == .start {
            guard let startedAtMs = intent.shell?.startedAtMs,
                  ISOTime.parse(draft.startedAt) == startedAtMs
            else { return false }
        }
        if intent.kind != .cancel {
            guard draft.plannedProgramId == intent.planned?.programId,
                  draft.plannedSessionId == intent.planned?.sessionId
            else { return false }
        }
        return true
    }

    /// The steps an interrupted transition still owes. Pure and total: same
    /// input, same plan, no stores and no clock.
    static func plan(_ input: Input) -> TransitionRecovery {
        guard let intent = input.intent else { return .nothing }
        let draft = input.draft
        let sessions = input.sessions

        let clearShell: ShellDisposition = input.shellWorkoutId == intent.sourceWorkoutId ? .clear : .keep

        // A stale journal cannot close a newer, unrelated workout.
        if draft != nil && !draftMatches(intent, draft) {
            return TransitionRecovery(
                draft: .keep, close: nil, legacy: nil, shell: .keep,
                restore: nil, clearIntent: true, reason: .intentStale
            )
        }

        switch intent.kind {
        case .start:
            if !input.workoutExists || input.workoutCompleted || alreadyWritten(sessions, intent, draft) {
                return TransitionRecovery(
                    draft: .keep, close: nil, legacy: nil, shell: clearShell,
                    restore: nil, clearIntent: true, reason: .intentStale
                )
            }
            if !draftMatches(intent, draft) {
                // Its draft never landed, or a different one is live. Nothing
                // was created that the person could expect back.
                return TransitionRecovery(
                    draft: .keep, close: nil, legacy: nil, shell: clearShell,
                    restore: nil, clearIntent: true,
                    reason: draft != nil ? .intentStale : .startAbandoned
                )
            }
            guard let shell = intent.shell else {
                return TransitionRecovery(
                    draft: .keep, close: nil, legacy: nil, shell: .keep,
                    restore: nil, clearIntent: true, reason: .startSettled
                )
            }
            if input.shellWorkoutId == intent.sourceWorkoutId,
               input.shellStartedAtMs == shell.startedAtMs {
                // Both halves are already there. The note is simply spent.
                return TransitionRecovery(
                    draft: .keep, close: nil, legacy: nil, shell: .keep,
                    restore: nil, clearIntent: true, reason: .startSettled
                )
            }
            // The draft is open and the shell it belongs to can be put back
            // exactly as the start was going to create it.
            return TransitionRecovery(
                draft: .keep,
                close: nil,
                legacy: nil,
                shell: .restore,
                restore: TransitionShellRestore(
                    workoutId: intent.sourceWorkoutId,
                    workoutName: shell.workoutName,
                    workoutDate: shell.workoutDate,
                    exerciseIds: shell.exerciseIds,
                    startedAtMs: shell.startedAtMs
                ),
                clearIntent: true,
                reason: .startResumed
            )

        case .cancel:
            if !draftMatches(intent, draft) {
                return TransitionRecovery(
                    draft: .keep, close: nil, legacy: nil, shell: clearShell,
                    restore: nil, clearIntent: true, reason: .cancelResumed
                )
            }
            return TransitionRecovery(
                draft: alreadyWritten(sessions, intent, draft) ? .discard : .close,
                close: TransitionClose(
                    sessionId: intent.sessionId ?? "",
                    completedAt: intent.completedAt ?? intent.recordedAt,
                    // A cancelled session is partial however much was performed.
                    status: .partial
                ),
                legacy: nil,
                shell: clearShell,
                restore: nil,
                clearIntent: true,
                reason: .cancelResumed
            )

        case .finish:
            let written = alreadyWritten(sessions, intent, draft)
            let legacyOwed = input.workoutExists && !input.workoutCompleted && intent.legacy != nil
            if !draftMatches(intent, draft) && !legacyOwed {
                return TransitionRecovery(
                    draft: .keep, close: nil, legacy: nil, shell: clearShell,
                    restore: nil, clearIntent: true,
                    reason: written ? .finishSettled : .intentStale
                )
            }

            var close: TransitionClose?
            if let sessionId = intent.sessionId,
               let completedAt = intent.completedAt,
               let status = intent.status {
                close = TransitionClose(sessionId: sessionId, completedAt: completedAt, status: status)
            }

            var legacy: TransitionLegacy?
            if legacyOwed, let intentLegacy = intent.legacy {
                legacy = TransitionLegacy(workoutId: intent.sourceWorkoutId, intent: intentLegacy)
            }

            return TransitionRecovery(
                draft: draftMatches(intent, draft) ? (written ? .discard : .close) : .keep,
                close: close,
                legacy: legacy,
                shell: clearShell,
                restore: nil,
                clearIntent: true,
                reason: .finishResumed
            )
        }
    }
}
