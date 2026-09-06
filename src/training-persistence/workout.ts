import type { PlannedSession } from "../training/domain/types"
import type {
  PersistedActiveSetDraft,
  PersistedActiveWorkoutDraft,
  PersistedCompletedSession,
  PersistedResistance,
  PersistedSetObservation,
} from "./schema"
import { isValidIsoTimestamp, isValidPersistedResistance } from "./validation"

export type PersistenceIdFactory = (
  kind: "exercise" | "set"
) => string

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
}): PersistedActiveWorkoutDraft {
  assertTimestamp(input.startedAt, "workout start")
  if (!input.draftId || !input.programId || !input.session.id)
    throw new Error("Missing planned workout identity")

  return {
    id: input.draftId,
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
}): PersistedActiveWorkoutDraft {
  assertTimestamp(input.startedAt, "workout start")
  if (!input.draftId) throw new Error("Missing workout identity")
  return {
    id: input.draftId,
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
  const exercise = next.exercises.find((entry) => entry.id === input.exerciseEntryId)
  if (!exercise) throw new Error("Active workout exercise not found")
  if (next.exercises.some((entry) => entry.sets.some((set) => set.id === input.setDraftId)))
    throw new Error("Duplicate active set ID")
  exercise.sets.push({
    id: input.setDraftId,
    setType: input.setType,
    side: input.side,
    observation: input.observation ? structuredClone(input.observation) : undefined,
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
  const exercise = next.exercises.find((entry) => entry.id === input.exerciseEntryId)
  if (!exercise) throw new Error("Active workout exercise not found")
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

  return {
    id: input.sessionId,
    plannedProgramId: draft.plannedProgramId,
    plannedSessionId: draft.plannedSessionId,
    startedAt: draft.startedAt,
    completedAt: input.completedAt,
    durationSeconds: (Date.parse(input.completedAt) - Date.parse(draft.startedAt)) / 1000,
    status: input.status,
    exercises,
  }
}
