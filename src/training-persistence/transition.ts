import type {
  PersistedActiveWorkoutDraft,
  PersistedCompletedSession,
  PersistedLegacyCompletionIntent,
  PersistedTransitionIntent,
} from "./schema"

/**
 * Carrying an interrupted workout transition forward.
 *
 * Starting and finishing a workout are single actions to the person doing them
 * and several writes to independently persisted stores underneath. The
 * reconciliation layer can already make the wreckage of an interrupted one
 * *safe*; what it cannot do is know what was meant to happen, so it closes
 * sessions the person expected to keep.
 *
 * An intent fixes that by being written first. It names the transition, the
 * identities it will use and — for a finish — the single instant it completes
 * at, so replaying it any number of times reaches the same result as running
 * it once. Recovery is then a matter of finishing the steps that did not land,
 * never of re-deciding what should happen.
 *
 * What an intent is not is evidence. It carries identities, times and the
 * legacy shell's own numbers. Which sets were performed lives only in the
 * draft's observations, and nothing here writes one.
 */

/** Each step recovery may still owe, decided from the state that came back. */
export type TransitionRecovery = {
  /** `close` writes the draft's observations under the intent's identity and
   *  instant. `discard` drops it, only ever when history already holds it.
   *  `keep` leaves it live for a start that is being resumed. */
  draft: "keep" | "close" | "discard"
  /** Fixed by the intent, so a replayed close cannot land differently. */
  close?: {
    sessionId: string
    completedAt: string
    status: "completed" | "partial"
  }
  /** The legacy completion still owed, absent once one is already recorded.
   *  An existing completion is never replaced: the first one the person saw
   *  is the one that stands. */
  legacy?: PersistedLegacyCompletionIntent & { workoutId: string }
  /** `restore` re-establishes the shell an interrupted start never exposed. */
  shell: "keep" | "clear" | "restore"
  restore?: {
    workoutId: string
    workoutName: string
    workoutDate: string
    exerciseIds: string[]
    startedAtMs: number
  }
  /** Whether the intent is spent and should be cleared. */
  clearIntent: boolean
  reason: TransitionRecoveryReason
}

export type TransitionRecoveryReason =
  /** No intent was in flight. */
  | "none"
  /** A start that never created its draft; nothing happened to carry forward. */
  | "start-abandoned"
  /** A start whose draft landed but whose shell never appeared. */
  | "start-resumed"
  /** A start already complete in both stores. */
  | "start-settled"
  /** A finish with steps still owed. */
  | "finish-resumed"
  /** A finish whose session history already holds. */
  | "finish-settled"
  /** A cancel with its draft still open. */
  | "cancel-resumed"
  /** An intent naming a draft that is not the one in hand. */
  | "intent-stale"

const NOTHING: TransitionRecovery = {
  draft: "keep",
  shell: "keep",
  clearIntent: false,
  reason: "none",
}

/** Whether history already holds the session this finish would write. Checked
 *  by the identity the intent fixed and by the draft's own lineage, so neither
 *  a replay nor a differently-identified retry can double-count one workout. */
function alreadyWritten(
  sessions: readonly PersistedCompletedSession[],
  intent: PersistedTransitionIntent,
  draft: PersistedActiveWorkoutDraft | null
) {
  return sessions.some(
    (session) =>
      session.id === intent.sessionId ||
      (draft?.plannedSessionId !== undefined &&
        session.plannedSessionId === draft.plannedSessionId) ||
      (session.sourceWorkoutId === intent.sourceWorkoutId &&
        session.startedAt ===
          (draft?.startedAt ??
            intent.legacy?.startedAt ??
            (intent.shell
              ? new Date(intent.shell.startedAtMs).toISOString()
              : undefined)))
  )
}

/** Whether the draft in hand is the one the intent was written about. An intent
 *  that names a draft explicitly must match it; one written before the draft
 *  existed is matched by the workout it belongs to. */
function draftMatches(
  intent: PersistedTransitionIntent,
  draft: PersistedActiveWorkoutDraft | null
) {
  if (!draft) return false
  return (
    draft.sourceWorkoutId === intent.sourceWorkoutId &&
    (!intent.draftId || draft.id === intent.draftId) &&
    (intent.kind !== "start" ||
      Date.parse(draft.startedAt) === intent.shell?.startedAtMs) &&
    (intent.kind === "cancel" ||
      (draft.plannedProgramId === intent.planned?.programId &&
        draft.plannedSessionId === intent.planned?.sessionId))
  )
}

/**
 * The steps an interrupted transition still owes.
 *
 * Pure and total: same input, same plan, no stores and no clock. Every step is
 * guarded by whether its own effect is already visible, so running the plan
 * twice owes nothing the second time.
 */
export function planTransitionRecovery(input: {
  intent: PersistedTransitionIntent | undefined
  draft: PersistedActiveWorkoutDraft | null
  sessions: readonly PersistedCompletedSession[]
  /** Whether the application workout already carries a legacy completion. */
  workoutCompleted: boolean
  /** Whether the application workout still exists at all. */
  workoutExists: boolean
  /** The workout a live shell is already running, when there is one. A start
   *  that already has its shell must not have it rebuilt from the intent:
   *  doing so would throw away check marks and elapsed time the person has
   *  since accumulated. */
  shellWorkoutId?: string
  shellStartedAtMs?: number
}): TransitionRecovery {
  const { intent, draft, sessions } = input
  if (!intent) return NOTHING

  const clearShell =
    input.shellWorkoutId === intent.sourceWorkoutId ? "clear" : "keep"
  // A stale journal cannot close a newer, unrelated workout.
  if (draft && !draftMatches(intent, draft))
    return {
      draft: "keep",
      shell: "keep",
      clearIntent: true,
      reason: "intent-stale",
    }

  if (intent.kind === "start") {
    if (
      !input.workoutExists ||
      input.workoutCompleted ||
      alreadyWritten(sessions, intent, draft)
    )
      return {
        draft: "keep",
        shell: clearShell,
        clearIntent: true,
        reason: "intent-stale",
      }
    if (!draftMatches(intent, draft))
      // Its draft never landed, or a different one is live. Nothing was
      // created that the person could expect back.
      return {
        draft: "keep",
        shell: clearShell,
        clearIntent: true,
        reason: draft ? "intent-stale" : "start-abandoned",
      }
    if (
      !intent.shell ||
      (input.shellWorkoutId === intent.sourceWorkoutId &&
        input.shellStartedAtMs === intent.shell.startedAtMs)
    )
      // Both halves are already there. The note is simply spent.
      return {
        draft: "keep",
        shell: "keep",
        clearIntent: true,
        reason: "start-settled",
      }
    // The draft is open and the shell it belongs to can be put back exactly as
    // the start was going to create it.
    return {
      draft: "keep",
      shell: "restore",
      restore: {
        workoutId: intent.sourceWorkoutId,
        workoutName: intent.shell.workoutName,
        workoutDate: intent.shell.workoutDate,
        exerciseIds: [...intent.shell.exerciseIds],
        startedAtMs: intent.shell.startedAtMs,
      },
      clearIntent: true,
      reason: "start-resumed",
    }
  }

  if (intent.kind === "cancel") {
    if (!draftMatches(intent, draft))
      return {
        draft: "keep",
        shell: clearShell,
        clearIntent: true,
        reason: "cancel-resumed",
      }
    return {
      draft: alreadyWritten(sessions, intent, draft) ? "discard" : "close",
      close: {
        sessionId: intent.sessionId ?? "",
        completedAt: intent.completedAt ?? intent.recordedAt,
        // A cancelled session is partial however much of it was performed.
        status: "partial",
      },
      shell: clearShell,
      clearIntent: true,
      reason: "cancel-resumed",
    }
  }

  // A finish. Each step is owed only where its effect is not already there.
  const written = alreadyWritten(sessions, intent, draft)
  const legacyOwed =
    input.workoutExists && !input.workoutCompleted && intent.legacy
  if (!draftMatches(intent, draft) && !legacyOwed)
    return {
      draft: "keep",
      shell: clearShell,
      clearIntent: true,
      reason: written ? "finish-settled" : "intent-stale",
    }

  return {
    draft: draftMatches(intent, draft)
      ? written
        ? "discard"
        : "close"
      : "keep",
    ...(intent.sessionId && intent.completedAt && intent.status
      ? {
          close: {
            sessionId: intent.sessionId,
            completedAt: intent.completedAt,
            status: intent.status,
          },
        }
      : {}),
    ...(legacyOwed
      ? { legacy: { ...intent.legacy!, workoutId: intent.sourceWorkoutId } }
      : {}),
    shell: clearShell,
    clearIntent: true,
    reason: "finish-resumed",
  }
}
