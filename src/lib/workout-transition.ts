import type { ActiveWorkoutSession } from "@/lib/active-workout"
import {
  activePlannedCoverage,
  draftClosingTime,
  performedExerciseIds,
} from "@/lib/training-session"
import { estimateStrengthCalories } from "@/lib/workout-stats"
import { useSettings } from "@/store/use-settings"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts, type Workout } from "@/store/use-workouts"
import type { PersistedTransitionIntent } from "@/training-persistence/schema"
import {
  planTransitionRecovery,
  type TransitionRecovery,
} from "@/training-persistence/transition"

/**
 * Starting, finishing and cancelling a workout, as transitions that survive
 * being interrupted.
 *
 * Each of those actions is one thing to the person doing it and several writes
 * to separately persisted stores underneath. This module writes down what is
 * about to happen before it happens, runs the steps, and clears the note when
 * they have all landed. A relaunch in the middle finds the note and finishes
 * the same steps rather than inferring what probably happened.
 *
 * The rules the journal itself enforces live in
 * `@/training-persistence/transition`; what lives here is the ordering and the
 * one thing the pure layer cannot do — read the stores. The shell half is
 * handed back to the caller rather than applied, because the store that owns
 * the shell is the one that calls this.
 */

function pendingIntent(
  kind: PersistedTransitionIntent["kind"],
  workoutId: string
) {
  const pending = useTrainingRecords.getState().data.transition
  if (
    pending &&
    (pending.kind !== kind || pending.sourceWorkoutId !== workoutId)
  )
    throw new Error("Finish recovering the pending workout transition first")
  return pending
}

function makeId(prefix: string) {
  const uuid = globalThis.crypto?.randomUUID?.()
  return uuid
    ? `${prefix}-${uuid}`
    : `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`
}

/**
 * Writes the intent to start `workout` before its draft exists.
 *
 * The shell the start will expose is fixed here too, so a relaunch between the
 * draft landing and the shell appearing can put back the session the person
 * was already looking at instead of losing it.
 */
export function recordStartIntent(workout: Workout, startedAtMs: number) {
  const pending = pendingIntent("start", workout.id)
  if (pending) return pending
  const intent: PersistedTransitionIntent = {
    id: makeId("transition"),
    kind: "start",
    recordedAt: new Date(startedAtMs).toISOString(),
    sourceWorkoutId: workout.id,
    ...(workout.planned ? { planned: { ...workout.planned } } : {}),
    shell: {
      workoutName: workout.name,
      workoutDate: workout.date,
      exerciseIds: [...workout.exerciseIds],
      startedAtMs,
    },
  }
  useTrainingRecords.getState().beginTransition(intent)
  return intent
}

/**
 * Writes the intent to finish `session`, with every identity and instant the
 * finish will use already decided.
 *
 * One completion instant is read from the clock here and reused by every step,
 * including a replay: recovery that read the clock again would give a resumed
 * finish a different duration and a different completion time than the one the
 * person saw. The status comes from prescription coverage at this moment for
 * the same reason — recovery must not re-judge work it can no longer see.
 */
export function recordFinishIntent(
  session: ActiveWorkoutSession,
  input: { durationMs: number; completedAt?: string }
) {
  const pending = pendingIntent("finish", session.workoutId)
  if (pending) return pending
  const completedAt = input.completedAt ?? new Date().toISOString()
  const settings = useSettings.getState()
  const draft = useTrainingRecords.getState().data.activeWorkout
  if (draft && draft.sourceWorkoutId !== session.workoutId)
    throw new Error("The active workout and its training draft do not match")
  // An exercise counts as performed if it was checked off or if it holds real
  // sets, so the saved workout cannot claim less than the structured session.
  const performed = performedExerciseIds()
  const covered = activePlannedCoverage()?.complete ?? true

  const intent: PersistedTransitionIntent = {
    id: makeId("transition"),
    kind: "finish",
    recordedAt: completedAt,
    sourceWorkoutId: session.workoutId,
    ...(draft?.id ? { draftId: draft.id } : {}),
    ...(draft?.plannedProgramId && draft.plannedSessionId
      ? {
          planned: {
            programId: draft.plannedProgramId,
            sessionId: draft.plannedSessionId,
          },
        }
      : {}),
    completedAt,
    sessionId: makeId("training-session"),
    status: covered ? "completed" : "partial",
    legacy: {
      startedAt: new Date(session.startedAt).toISOString(),
      completedAt,
      durationMs: input.durationMs,
      activeCalories: estimateStrengthCalories(
        input.durationMs,
        settings.healthBodyWeightKg
      ),
      completedExerciseIds: session.exerciseIds.filter(
        (id) => session.completedIds.includes(id) || performed.has(id)
      ),
      healthSyncStatus:
        settings.appleHealthEnabled && settings.autoSyncWorkouts
          ? "pending"
          : "not-requested",
    },
  }
  useTrainingRecords.getState().beginTransition(intent)
  return intent
}

/** Writes the intent to discard `session`. A cancelled session is partial
 *  however much of it was performed, so no status has to be decided. */
export function recordCancelIntent(session: ActiveWorkoutSession) {
  const pending = pendingIntent("cancel", session.workoutId)
  if (pending) return pending
  const draft = useTrainingRecords.getState().data.activeWorkout
  const intent: PersistedTransitionIntent = {
    id: makeId("transition"),
    kind: "cancel",
    recordedAt: new Date().toISOString(),
    sourceWorkoutId: session.workoutId,
    ...(draft?.id ? { draftId: draft.id } : {}),
    completedAt: draft ? draftClosingTime(draft) : new Date().toISOString(),
    sessionId: makeId("training-session"),
  }
  useTrainingRecords.getState().beginTransition(intent)
  return intent
}

/** Applies the legacy completion an intent still owes. An existing completion
 *  is never replaced: the first one the person saw is the one that stands. */
function applyLegacy(recovery: TransitionRecovery) {
  const owed = recovery.legacy
  if (!owed) return
  const { workoutId, ...completion } = owed
  const previous = useWorkouts.getState().workouts
  try {
    useWorkouts.getState().completeWorkout(workoutId, {
      ...completion,
      completedExerciseIds: [...completion.completedExerciseIds],
    })
  } catch (error) {
    try {
      useWorkouts.setState({ workouts: previous })
    } catch {
      /* Memory restored. */
    }
    throw error
  }
}

/** Closes the draft under the identity and instant the intent fixed, so a
 *  replay lands on the same session rather than adding another. */
function applyDraft(recovery: TransitionRecovery) {
  const store = useTrainingRecords.getState()
  if (!store.data.activeWorkout) return
  if (recovery.draft === "discard") {
    store.cancelWorkout()
    return
  }
  if (recovery.draft !== "close") return
  const close = recovery.close
  const draft = store.data.activeWorkout
  const hasObservations = draft.exercises.some((exercise) =>
    exercise.sets.some((set) => set.observation?.completed)
  )
  // Nothing performed leaves no structured session at all, whatever the intent
  // hoped for: an interrupted finish must not become fictional history.
  if (!hasObservations) {
    store.cancelWorkout()
    return
  }
  store.completeWorkout(
    close?.status === "completed" && (activePlannedCoverage()?.complete ?? true)
      ? "completed"
      : "partial",
    close?.completedAt ?? draftClosingTime(draft),
    close?.sessionId
  )
}

/**
 * Finishes whatever transition was in flight when the app stopped.
 *
 * Returns the shell half for the caller to apply. Safe to run repeatedly: each
 * step is guarded by whether its own effect is already visible, and the note is
 * cleared by the caller after persisting the shell.
 *
 * A step that throws leaves the journal entry in place rather than clearing it.
 * The caller must leave this intent pending and retry before fallback recovery.
 */
export function recoverWorkoutTransition(
  shellWorkoutId?: string,
  shellStartedAtMs?: number
): TransitionRecovery {
  const store = useTrainingRecords.getState()
  const intent = store.data.transition
  const draft = store.data.activeWorkout
  const workout = useWorkouts
    .getState()
    .workouts.find((item) => item.id === intent?.sourceWorkoutId)

  const recovery = planTransitionRecovery({
    intent,
    draft,
    sessions: store.data.sessions,
    workoutCompleted: Boolean(workout?.completion),
    workoutExists: Boolean(workout),
    shellWorkoutId,
    shellStartedAtMs,
  })
  if (recovery.reason === "none") return recovery

  // The caller must persist the shell before clearing the intent. Let storage
  // failures propagate: a failed write must never look like a successful finish.
  applyLegacy(recovery)
  applyDraft(recovery)

  return recovery
}

/** Clears the journal entry for a transition that ran to completion. */
export function settleWorkoutTransition() {
  useTrainingRecords.getState().clearTransition()
}
