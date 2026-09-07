import { useTrainingRecords } from "@/store/use-training-records"
import type { PlannedWorkoutReference } from "@/store/use-workouts"
import { toEngineProgramSnapshot } from "@/training-persistence/program"
import type {
  PersistedActiveExerciseDraft,
  PersistedActiveWorkoutDraft,
  PersistedTrainingStateLatest,
} from "@/training-persistence/schema"
import {
  plannedWorkCoverage,
  type PlannedWorkCoverage,
} from "@/training-persistence/workout"
import type { PlannedSession } from "@/training/domain/types"

/**
 * The seam between the workout a person is running and the structured record
 * of what they actually did.
 *
 * The app has always had two halves of a session: `useActiveWorkout` — the
 * clock, the current exercise, the check marks — and, since the persistence
 * pass, `useTrainingRecords`, which holds real observations the deterministic
 * engine can read. This file keeps exactly one draft alive alongside exactly
 * one running session, so a manually built workout produces the same structured
 * history a generated one will.
 *
 * Nothing here invents performance. Starting a workout creates an empty draft:
 * the exercises are listed, and not one set exists until a set is logged.
 */

/** The performed exercise inside the live draft, or null when the session has
 *  no structured draft (an old session restored from before this pass, or a
 *  draft the store refused). */
export function draftExercise(
  draft: PersistedActiveWorkoutDraft | null,
  exerciseId: string
): PersistedActiveExerciseDraft | null {
  return draft?.exercises.find((item) => item.exerciseId === exerciseId) ?? null
}

/** Exercises of the live draft that carry at least one performed set. A logged
 *  set is the stronger statement: an exercise nobody remembered to check off is
 *  still an exercise that was done. */
export function performedExerciseIds(): Set<string> {
  const draft = useTrainingRecords.getState().data.activeWorkout
  return new Set(
    draft?.exercises
      .filter((exercise) =>
        exercise.sets.some((set) => set.observation?.completed)
      )
      .map((exercise) => exercise.exerciseId) ?? []
  )
}

function draftHasObservations(draft: PersistedActiveWorkoutDraft | null) {
  return Boolean(
    draft?.exercises.some((exercise) =>
      exercise.sets.some((set) => set.observation?.completed)
    )
  )
}

/**
 * Opens the structured draft for a session that is starting.
 *
 * A draft left behind by an earlier session — a process killed mid-workout, a
 * restored backup — is closed first rather than discarded: whatever sets it
 * holds were genuinely performed, and they belong in history under their own
 * session, not in this one.
 *
 * A workout that stands for a planned session opens the *planned* draft: its
 * sets come from the program snapshot with their targets and their planned
 * program, session, exercise and set identities attached. A workout somebody
 * built by hand opens a free draft with none of those invented for it. A
 * planned workout must keep that lineage: when its planned draft cannot be
 * opened, this returns false and no free draft is substituted for it.
 */
export function beginTrainingDraft(
  exerciseIds: string[],
  startedAt: string,
  sourceWorkoutId: string,
  planned?: PlannedWorkoutReference
): boolean {
  const store = useTrainingRecords.getState()
  const stale = store.data.activeWorkout
  if (stale) store.abortWorkout(closingTime(stale, startedAt))
  if (planned) return startPlannedDraft(planned, startedAt, sourceWorkoutId)
  useTrainingRecords
    .getState()
    .startFreeWorkout(exerciseIds, startedAt, sourceWorkoutId)
  return true
}

function startPlannedDraft(
  planned: PlannedWorkoutReference,
  startedAt: string,
  sourceWorkoutId: string
) {
  try {
    useTrainingRecords
      .getState()
      .startPlannedWorkout(
        planned.programId,
        planned.sessionId,
        startedAt,
        sourceWorkoutId
      )
    return true
  } catch {
    return false
  }
}

/** When a stale draft is treated as having ended: now, or the moment of its own
 *  last recorded set if the device clock has since moved backwards. A session
 *  cannot have finished before the work it contains. */
function closingTime(draft: PersistedActiveWorkoutDraft, now: string) {
  const instants = [
    Date.parse(now),
    Date.parse(draft.startedAt),
    ...draft.exercises.flatMap((exercise) =>
      exercise.sets.flatMap((set) =>
        set.observation?.timestamp
          ? [Date.parse(set.observation.timestamp)]
          : []
      )
    ),
  ]
  return new Date(Math.max(...instants)).toISOString()
}

/**
 * Follows the workout being edited while it runs.
 *
 * Only additions are mirrored. An exercise dropped from the workout keeps its
 * draft entry, because removing it from the plan says nothing about whether it
 * was performed: entries that were never logged contribute nothing at
 * completion anyway, and entries that were logged must survive.
 */
export function syncTrainingDraftExercises(exerciseIds: readonly string[]) {
  const store = useTrainingRecords.getState()
  const draft = store.data.activeWorkout
  if (!draft) return
  for (const exerciseId of exerciseIds) {
    if (draft.exercises.some((item) => item.exerciseId === exerciseId)) continue
    useTrainingRecords.getState().addExercise(exerciseId)
  }
}

/** The planned session a draft is performing, read back out of the immutable
 *  snapshot it was opened from. Null for a free draft, and for a planned one
 *  whose program has since gone — which persistence validation refuses to
 *  store, and which coverage treats as an unverifiable prescription. */
function plannedSessionOf(
  data: PersistedTrainingStateLatest,
  draft: PersistedActiveWorkoutDraft
): PlannedSession | null {
  const record = data.programs.find(
    (program) => program.id === draft.plannedProgramId
  )
  if (!record) return null
  return (
    toEngineProgramSnapshot(record.snapshot)
      .weeks.flatMap((week) => week.sessions)
      .find((session) => session.id === draft.plannedSessionId) ?? null
  )
}

/**
 * How much of the running session's prescription has been performed, or null
 * when there is nothing prescribed — no draft at all, or a free workout, which
 * promises nothing and so can never fall short of it.
 */
export function activePlannedCoverage(
  data: PersistedTrainingStateLatest = useTrainingRecords.getState().data
): PlannedWorkCoverage | null {
  const draft = data.activeWorkout
  if (!draft) return null
  return plannedWorkCoverage(draft, plannedSessionOf(data, draft))
}

/**
 * Closes the draft the way the session ended.
 *
 * Only sets with a real observation are written, so a session abandoned after
 * two exercises persists those two exercises and nothing else. A draft with no
 * logged sets leaves no structured session at all — the legacy workout record
 * still carries that the workout happened.
 *
 * The status is what the evidence supports rather than which button was
 * pressed. A session walked away from is partial. A finished one is completed
 * only when every prescribed working set was actually performed: pressing
 * Finish with half the plan untouched records half a session, so the engine
 * reads a prescription that was cut short as exactly that. A free workout
 * prescribes nothing, so finishing it is always completion.
 */
export function endTrainingDraft(
  outcome: "finished" | "cancelled",
  completedAt = new Date().toISOString()
) {
  const store = useTrainingRecords.getState()
  if (!store.data.activeWorkout) return null
  if (!draftHasObservations(store.data.activeWorkout)) {
    store.cancelWorkout()
    return null
  }
  const covered = activePlannedCoverage(store.data)?.complete ?? true
  return store.completeWorkout(
    outcome === "finished" && covered ? "completed" : "partial",
    completedAt
  )
}
