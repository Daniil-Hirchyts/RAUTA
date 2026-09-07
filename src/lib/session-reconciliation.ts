import type { ActiveWorkoutSession } from "@/lib/active-workout"
import { draftClosingTime } from "@/lib/training-session"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts, type Workout } from "@/store/use-workouts"
import type {
  PersistedActiveWorkoutDraft,
  PersistedTrainingStateLatest,
} from "@/training-persistence/schema"

/**
 * Putting one workout back together after a relaunch.
 *
 * A running workout lives in three stores that persist independently: the
 * workout itself in `useWorkouts`, the clock and check marks in
 * `useActiveWorkout`, and the sets that were actually performed in
 * `useTrainingRecords`. While the app runs they move together. A relaunch
 * restores them one at a time, so whatever the last write did not reach comes
 * back describing a different workout than its neighbours — and nothing until
 * now proved, on the way in, that the three still described the same session.
 *
 * That is not cosmetic. The shell decides which workout the set editor is
 * pointed at while the draft decides which prescription a logged set answers,
 * so a shell restored onto somebody else's draft records real sets against the
 * wrong workout and the wrong planned lineage — and the deterministic engine
 * reads the result as fact.
 *
 * So the pieces are reconciled once, before they become application state.
 * The rules are fixed and ordered, and they resolve every conflict the same
 * way every time:
 *
 * - **Observations outrank everything.** The draft is the only record of work
 *   that was really done. Where the shell and the draft disagree, the shell is
 *   what goes; where a draft cannot stay live, its observations are written to
 *   history as a partial session rather than dropped.
 * - **Nothing is invented.** Recovery never mints a set, an observation or a
 *   planned identity, never edits a program snapshot, and never re-reads a
 *   check mark or a legacy completion as evidence that a set was performed.
 * - **A workout is completed once.** A shell or draft that outlived the
 *   completion of its own workout is closed, not offered for a second finish.
 * - **Empty is discarded, not recorded.** A draft with no observations leaves
 *   no session behind, so a stale shell cannot become fictional history.
 * - **Irreconcilable state fails closed.** What cannot be proved coherent is
 *   closed rather than resumed, and the observations survive the closing.
 */

/** Which of the fixed rules decided the outcome. Named so a repair is legible
 *  in a test and in a bug report rather than being an unexplained clear. */
export type ReconciliationReason =
  /** Nothing was restored; there is no session to put back together. */
  | "idle"
  /** The three pieces already agree. */
  | "coherent"
  /** A shell with no structured record behind it: it can log nothing. */
  | "session-without-draft"
  /** Shell and draft name different workouts. */
  | "workout-mismatch"
  /** The workout being performed is gone. */
  | "workout-missing"
  /** The workout was already completed while this state survived. */
  | "workout-completed"
  /** History already holds this workout's or prescription's session. */
  | "already-recorded"
  /** Shell and draft disagree about the prescription, or it cannot be read. */
  | "planned-lineage-mismatch"
  /** Real observations outlived the shell that was collecting them. */
  | "draft-without-session"

export type SessionReconciliation = {
  /** `keep` leaves the draft live. `close` writes its observations to history
   *  as a partial session, and leaves nothing behind when it holds none.
   *  `discard` drops it whole — only ever when history already holds it. */
  draft: "keep" | "close" | "discard"
  /** Whether the live UI session survives. */
  session: "keep" | "clear"
  reason: ReconciliationReason
}

/** Whether history already holds a session for this workout or prescription.
 *  Closing the draft again would put the same work in twice, and the engine
 *  reads a double-counted prescription as volume that was really performed. */
function alreadyRecorded(
  training: PersistedTrainingStateLatest,
  draft: PersistedActiveWorkoutDraft
) {
  return training.sessions.some(
    (recorded) =>
      (draft.plannedSessionId !== undefined &&
        recorded.plannedSessionId === draft.plannedSessionId) ||
      (draft.sourceWorkoutId !== undefined &&
        recorded.sourceWorkoutId === draft.sourceWorkoutId &&
        recorded.startedAt === draft.startedAt)
  )
}

/**
 * Whether the shell, the draft and the program snapshot tell one story about
 * the prescription being performed.
 *
 * A planned workout must not come back as a free one and a free workout must
 * not acquire a lineage, so a disagreement in either direction fails. The
 * prescription itself is only ever read out of the immutable snapshot, and
 * only to confirm it is there: recovery never writes planned identity that the
 * program does not already carry.
 */
function plannedLineageHolds(
  training: PersistedTrainingStateLatest,
  workout: Workout | undefined,
  draft: PersistedActiveWorkoutDraft
) {
  if (workout) {
    const shell = workout.planned
    if (Boolean(shell) !== Boolean(draft.plannedSessionId)) return false
    if (
      shell &&
      (shell.programId !== draft.plannedProgramId ||
        shell.sessionId !== draft.plannedSessionId)
    )
      return false
  }
  if (!draft.plannedSessionId) return true
  const record = training.programs.find(
    (program) => program.id === draft.plannedProgramId
  )
  return Boolean(
    record?.snapshot.weeks.some((week) =>
      week.sessions.some((session) => session.id === draft.plannedSessionId)
    )
  )
}

/**
 * The decision, from the restored pieces alone.
 *
 * Pure and total: same input, same outcome, no stores and no clock. The rules
 * are tried in order, most specific first, so exactly one of them explains any
 * given state.
 */
export function planSessionReconciliation(input: {
  session: ActiveWorkoutSession | null
  training: PersistedTrainingStateLatest
  workouts: readonly Workout[]
}): SessionReconciliation {
  const { session, training, workouts } = input
  const draft = training.activeWorkout

  if (!draft)
    return session
      ? // The shell survived without the record behind it. It can no longer
        // log a set, and opening a draft for it now would be a session the
        // person never started, so the shell is what goes.
        { draft: "keep", session: "clear", reason: "session-without-draft" }
      : { draft: "keep", session: "keep", reason: "idle" }

  if (alreadyRecorded(training, draft))
    return { draft: "discard", session: "clear", reason: "already-recorded" }

  // The shell says which workout the set editor is pointed at and the draft
  // says which one the sets land in. When those differ, every set logged from
  // here would be recorded against the wrong workout.
  if (session && session.workoutId !== draft.sourceWorkoutId)
    return { draft: "close", session: "clear", reason: "workout-mismatch" }

  const workout = draft.sourceWorkoutId
    ? workouts.find((item) => item.id === draft.sourceWorkoutId)
    : undefined

  if (draft.sourceWorkoutId && !workout)
    return { draft: "close", session: "clear", reason: "workout-missing" }

  if (workout?.completion)
    return { draft: "close", session: "clear", reason: "workout-completed" }

  if (!plannedLineageHolds(training, workout, draft))
    return {
      draft: "close",
      session: "clear",
      reason: "planned-lineage-mismatch",
    }

  // The work is real and the prescription it answers is intact; only the shell
  // that was collecting it is missing. The sets belong in history.
  if (!session)
    return { draft: "close", session: "keep", reason: "draft-without-session" }

  return { draft: "keep", session: "keep", reason: "coherent" }
}

/**
 * Applies the draft half of the decision and reports it, so the caller can
 * apply the shell half against its own store.
 *
 * Idempotent by construction: every repair ends with the draft either coherent
 * or gone, so a second pass over the result decides `coherent` or `idle` and
 * writes nothing. A draft too corrupt to close is left exactly as it is —
 * observations are never destroyed to tidy up state, and a failed close
 * changes nothing for the next pass to disagree with.
 */
export function reconcileRestoredSession(
  session: ActiveWorkoutSession | null
): SessionReconciliation {
  const decision = planSessionReconciliation({
    session,
    training: useTrainingRecords.getState().data,
    workouts: useWorkouts.getState().workouts,
  })

  const draft = useTrainingRecords.getState().data.activeWorkout
  if (draft && decision.draft !== "keep") {
    try {
      if (decision.draft === "close")
        // Writes a partial session when the draft holds observations and
        // clears it when it does not, so nothing empty reaches history.
        useTrainingRecords.getState().abortWorkout(draftClosingTime(draft))
      else useTrainingRecords.getState().cancelWorkout()
    } catch {
      /* Unclosable means unreadable, not worthless: the draft stays put with
         its observations rather than being cleared to make the state tidy. */
    }
  }

  return decision
}
