import { adaptLegacyWorkout } from "../training/data/legacy"
import type {
  CompletedExercise,
  CompletedSession,
  ResistanceValue,
  TrainingHistory,
} from "../training/domain/types"
import type {
  PersistedCompletedSession,
  PersistedTrainingStateLatest,
} from "./schema"

export type LegacyWorkoutObservation = {
  id: string
  completion: null | {
    startedAt: string
    completedAt: string
    durationMs: number
    completedExerciseIds: string[]
  }
}

function toEngineCompletedSession(session: PersistedCompletedSession): CompletedSession {
  const exercises = new Map<string, CompletedExercise>()
  for (const entry of session.exercises) {
    const existing = exercises.get(entry.exerciseId) ?? {
      exerciseId: entry.exerciseId,
      sets: [],
    }
    existing.sets.push(
      ...entry.sets.map((set) => ({
        id: set.id,
        plannedSetId: set.plannedSetId,
        reps: set.reps,
        resistance: structuredClone(set.resistance) as ResistanceValue,
        rir: set.rir,
        rpe: set.rpe,
        completed: set.completed,
        setType: set.setType,
        side: set.side,
        timestamp: set.timestamp,
      }))
    )
    exercises.set(entry.exerciseId, existing)
  }
  return {
    id: session.id,
    plannedSessionId: session.plannedSessionId,
    startedAt: session.startedAt,
    completedAt: session.completedAt,
    durationSeconds: session.durationSeconds,
    status: session.status,
    exercises: [...exercises.values()],
  }
}

/** Structured sessions are lossless; legacy workouts contribute identity/time and zero fictional sets. */
export function toTrainingHistory(
  state: PersistedTrainingStateLatest,
  legacyWorkouts: readonly LegacyWorkoutObservation[] = []
): TrainingHistory {
  const structured = state.sessions.map(toEngineCompletedSession)
  // A workout performed with structured logging is one session, not two: its
  // legacy record names the same workout and would otherwise be counted again
  // as a second, set-less exposure.
  const structuredIds = new Set(
    state.sessions.flatMap((session) => [
      session.id,
      ...(session.sourceWorkoutId ? [session.sourceWorkoutId] : []),
    ])
  )
  const legacy = legacyWorkouts.flatMap((workout) => {
    if (structuredIds.has(workout.id)) return []
    const adapted = adaptLegacyWorkout(structuredClone(workout))
    return adapted ? [adapted] : []
  })
  const sessions = [...structured, ...legacy].sort((left, right) => {
    const time = left.startedAt.localeCompare(right.startedAt)
    return time || left.id.localeCompare(right.id)
  })

  const coverage = state.settings.historyCoverage
  return coverage.status === "complete"
    ? {
        sessions,
        coverage: "complete",
        coverageStart: coverage.coverageStart,
      }
    : { sessions, coverage: "unknown" }
}
