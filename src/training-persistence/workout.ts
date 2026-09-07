import type { PlannedSession } from "../training/domain/types"
import type {
  PersistedActiveSetDraft,
  PersistedActiveWorkoutDraft,
  PersistedCompletedSession,
  PersistedResistance,
  PersistedSetObservation,
} from "./schema"
import { isValidIsoTimestamp, isValidPersistedResistance } from "./validation"

export type PersistenceIdFactory = (kind: "exercise" | "set") => string

function assertTimestamp(value: string, field: string) {
  if (!isValidIsoTimestamp(value)) throw new Error(`Invalid ${field}`)
}

function assertObservation(observation: PersistedSetObservation) {
  if (
    typeof observation.completed !== "boolean" ||
    (observation.reps !== undefined &&
      (!Number.isInteger(observation.reps) ||
        observation.reps < 0 ||
        observation.reps > 1000)) ||
    (observation.resistance !== undefined &&
      !isValidPersistedResistance(observation.resistance)) ||
    (observation.rir !== undefined &&
      (!Number.isFinite(observation.rir) ||
        observation.rir < 0 ||
        observation.rir > 10)) ||
    (observation.rpe !== undefined &&
      (!Number.isFinite(observation.rpe) ||
        observation.rpe < 0 ||
        observation.rpe > 10)) ||
    (observation.rir !== undefined &&
      observation.rpe !== undefined &&
      Math.abs(observation.rir + observation.rpe - 10) > 1) ||
    (observation.timestamp !== undefined &&
      !isValidIsoTimestamp(observation.timestamp))
  )
    throw new Error("Invalid set observation")
}

export function createActiveWorkoutFromPlannedSession(input: {
  draftId: string
  programId: string
  session: PlannedSession
  startedAt: string
  makeId: PersistenceIdFactory
  exerciseNameSnapshot?: (exerciseId: string) => string | undefined
  /** The application workout this planned session is being performed from,
   *  when the shell projected one. It keeps the two histories from counting
   *  the same session twice. */
  sourceWorkoutId?: string
}): PersistedActiveWorkoutDraft {
  assertTimestamp(input.startedAt, "workout start")
  if (!input.draftId || !input.programId || !input.session.id)
    throw new Error("Missing planned workout identity")

  return {
    id: input.draftId,
    ...(input.sourceWorkoutId
      ? { sourceWorkoutId: input.sourceWorkoutId }
      : {}),
    plannedProgramId: input.programId,
    plannedSessionId: input.session.id,
    startedAt: input.startedAt,
    exercises: input.session.exercises.map((exercise) => ({
      id: input.makeId("exercise"),
      exerciseId: exercise.exerciseId,
      plannedExerciseId: exercise.exerciseId,
      exerciseNameSnapshot: input.exerciseNameSnapshot?.(exercise.exerciseId),
      sets: [...exercise.warmupSets, ...exercise.workingSets].map((set) => ({
        id: input.makeId("set"),
        plannedSetId: set.id,
        setType: set.setType,
        side: set.side,
        target: {
          reps: { ...set.targetReps },
          rir: set.targetRir,
          resistance: structuredClone(set.resistance) as PersistedResistance,
        },
      })),
    })),
  }
}

export function createFreeWorkoutDraft(input: {
  draftId: string
  startedAt: string
  exerciseIds: string[]
  makeId: PersistenceIdFactory
  exerciseNameSnapshot?: (exerciseId: string) => string | undefined
  /** The application workout being performed, when the draft came from one. */
  sourceWorkoutId?: string
}): PersistedActiveWorkoutDraft {
  assertTimestamp(input.startedAt, "workout start")
  if (!input.draftId) throw new Error("Missing workout identity")
  return {
    id: input.draftId,
    ...(input.sourceWorkoutId
      ? { sourceWorkoutId: input.sourceWorkoutId }
      : {}),
    startedAt: input.startedAt,
    exercises: input.exerciseIds.map((exerciseId) => {
      if (!exerciseId) throw new Error("Missing exercise identity")
      return {
        id: input.makeId("exercise"),
        exerciseId,
        exerciseNameSnapshot: input.exerciseNameSnapshot?.(exerciseId),
        sets: [],
      }
    }),
  }
}

export function recordSetObservation(
  draft: PersistedActiveWorkoutDraft,
  input: {
    exerciseEntryId: string
    setDraftId: string
    observation: PersistedSetObservation
  }
): PersistedActiveWorkoutDraft {
  assertObservation(input.observation)
  let found = false
  const next = structuredClone(draft)
  for (const exercise of next.exercises) {
    if (exercise.id !== input.exerciseEntryId) continue
    for (const set of exercise.sets) {
      if (set.id !== input.setDraftId) continue
      set.observation = structuredClone(input.observation)
      found = true
    }
  }
  if (!found) throw new Error("Active workout set not found")
  return next
}

export function addUnplannedSet(
  draft: PersistedActiveWorkoutDraft,
  input: {
    exerciseEntryId: string
    setDraftId: string
    setType: PersistedActiveSetDraft["setType"]
    side: PersistedActiveSetDraft["side"]
    observation?: PersistedSetObservation
  }
): PersistedActiveWorkoutDraft {
  if (input.observation) assertObservation(input.observation)
  const next = structuredClone(draft)
  const exercise = next.exercises.find(
    (entry) => entry.id === input.exerciseEntryId
  )
  if (!exercise) throw new Error("Active workout exercise not found")
  if (
    next.exercises.some((entry) =>
      entry.sets.some((set) => set.id === input.setDraftId)
    )
  )
    throw new Error("Duplicate active set ID")
  exercise.sets.push({
    id: input.setDraftId,
    setType: input.setType,
    side: input.side,
    observation: input.observation
      ? structuredClone(input.observation)
      : undefined,
  })
  return next
}

export function substituteDraftExercise(
  draft: PersistedActiveWorkoutDraft,
  input: {
    exerciseEntryId: string
    exerciseId: string
    exerciseNameSnapshot?: string
  }
): PersistedActiveWorkoutDraft {
  if (!input.exerciseId) throw new Error("Missing substitute exercise identity")
  const next = structuredClone(draft)
  const exercise = next.exercises.find(
    (entry) => entry.id === input.exerciseEntryId
  )
  if (!exercise) throw new Error("Active workout exercise not found")
  if (exercise.sets.some((set) => set.observation))
    throw new Error(
      "Keep the recorded exercise; add the replacement as a new exercise"
    )
  exercise.exerciseId = input.exerciseId
  exercise.exerciseNameSnapshot = input.exerciseNameSnapshot
  return next
}

/**
 * Deterministic completion transition. Planned targets without a completed observation
 * disappear from history; they remain available through the immutable program snapshot.
 */
export function completeWorkoutDraft(
  draft: PersistedActiveWorkoutDraft,
  input: {
    sessionId: string
    completedAt: string
    status: "completed" | "partial"
    makeId: PersistenceIdFactory
  }
): PersistedCompletedSession {
  assertTimestamp(input.completedAt, "workout completion")
  if (!input.sessionId) throw new Error("Missing completed session identity")
  if (Date.parse(input.completedAt) < Date.parse(draft.startedAt))
    throw new Error("Workout completion predates start")

  const exercises = draft.exercises.flatMap((exercise) => {
    const sets = exercise.sets.flatMap((set) => {
      const observation = set.observation
      if (!observation?.completed) return []
      assertObservation(observation)
      if (
        observation.reps === undefined ||
        observation.reps < 1 ||
        observation.resistance === undefined
      )
        throw new Error("Completed set is missing actual reps or resistance")
      if (
        observation.timestamp &&
        (Date.parse(observation.timestamp) < Date.parse(draft.startedAt) ||
          Date.parse(observation.timestamp) > Date.parse(input.completedAt))
      )
        throw new Error("Completed set timestamp is outside workout")
      return [
        {
          id: input.makeId("set"),
          plannedSetId: set.plannedSetId,
          reps: observation.reps,
          resistance: structuredClone(observation.resistance),
          rir: observation.rir,
          rpe: observation.rpe,
          completed: true,
          setType: set.setType,
          side: set.side,
          timestamp: observation.timestamp,
        },
      ]
    })
    if (!sets.length) return []
    return [
      {
        id: input.makeId("exercise"),
        exerciseId: exercise.exerciseId,
        plannedExerciseId: exercise.plannedExerciseId,
        exerciseNameSnapshot: exercise.exerciseNameSnapshot,
        sets,
      },
    ]
  })

  if (!exercises.length)
    throw new Error("Complete at least one set before saving")
  return {
    id: input.sessionId,
    sourceWorkoutId: draft.sourceWorkoutId,
    plannedProgramId: draft.plannedProgramId,
    plannedSessionId: draft.plannedSessionId,
    startedAt: draft.startedAt,
    completedAt: input.completedAt,
    durationSeconds:
      (Date.parse(input.completedAt) - Date.parse(draft.startedAt)) / 1000,
    status: input.status,
    exercises,
  }
}

/** How much of a planned session's prescribed work has actually been done. */
export type PlannedWorkCoverage = {
  /** Working sets the prescription asked for. */
  prescribed: number
  /** Of those, the ones answered by a real completed observation. */
  performed: number
  /** Whether the prescription itself could be read out of its snapshot. */
  verified: boolean
  /** Whether the whole prescription was verifiably carried out. */
  complete: boolean
}

/**
 * Coverage of a planned session's prescription by the work really performed.
 *
 * The immutable snapshot is the prescription, and its `workingSets` are what
 * was asked for — the domain keeps warmups in a separate array precisely
 * because they prepare for the prescription rather than being it, so an
 * unlogged warmup never makes a session partial. The draft says only what was
 * performed and never gets a say in what was asked for: a draft that was
 * edited, restored, or otherwise diverged cannot widen, narrow or stale the
 * prescription it is measured against.
 *
 * A set counts as performed only when it carries a completed observation. A
 * check mark, a target, or a row the UI shows as done is not evidence that
 * anything was lifted.
 *
 * Coverage follows planned identity rather than exercise identity, so a
 * substituted exercise still answers the prescription its `plannedSetId`
 * lineage points at, while an extra set — which has no `plannedSetId` — is
 * real work that can never stand in for a prescribed set nobody performed.
 *
 * Returns null for a free workout: there is no prescription to cover.
 */
export function plannedWorkCoverage(
  draft: PersistedActiveWorkoutDraft,
  session: PlannedSession | null
): PlannedWorkCoverage | null {
  if (!draft.plannedSessionId) return null

  const source = session?.id === draft.plannedSessionId ? session : null
  const prescribed = new Set(
    source
      ? source.exercises.flatMap((exercise) =>
          exercise.workingSets.map((set) => set.id)
        )
      : // Its snapshot is unreadable, so there is nothing to be measured
        // against. What the draft still lists says how much work is in flight,
        // but a prescription nobody can read is never certified as carried out.
        draft.exercises.flatMap((exercise) =>
          exercise.sets.flatMap((set) =>
            set.plannedSetId && set.setType !== "warmup"
              ? [set.plannedSetId]
              : []
          )
        )
  )

  const performed = new Set<string>()
  for (const exercise of draft.exercises)
    for (const set of exercise.sets)
      if (
        set.plannedSetId &&
        set.observation?.completed &&
        prescribed.has(set.plannedSetId)
      )
        performed.add(set.plannedSetId)

  return {
    prescribed: prescribed.size,
    performed: performed.size,
    verified: source !== null,
    complete: source !== null && performed.size === prescribed.size,
  }
}
