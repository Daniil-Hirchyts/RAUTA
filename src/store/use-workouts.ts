import { create } from "zustand"
import { persist } from "zustand/middleware"

import { EXERCISES_BY_ID } from "@/lib/exercises"
import { toISODate } from "@/lib/date"
import { isRecord, validString, validUniqueStrings } from "@/store/persistence"

export type HealthSyncStatus = "not-requested" | "pending" | "synced" | "failed"

export type WorkoutCompletion = {
  startedAt: string
  completedAt: string
  durationMs: number
  completedExerciseIds: string[]
  activeCalories: number
  healthSyncStatus: HealthSyncStatus
}

export type Workout = {
  id: string
  name: string
  date: string
  exerciseIds: string[]
  completion: WorkoutCompletion | null
  createdAt: string
  updatedAt: string
}

export type WorkoutsState = {
  workouts: Workout[]
  createWorkout: (input: {
    name: string
    date: string
    exerciseIds: string[]
  }) => string
  updateWorkout: (
    id: string,
    patch: Partial<Pick<Workout, "name" | "date" | "exerciseIds">>
  ) => void
  deleteWorkout: (id: string) => void
  duplicateWorkout: (id: string) => string | null
  completeWorkout: (id: string, completion: WorkoutCompletion) => void
  setHealthSyncStatus: (id: string, status: HealthSyncStatus) => void
}

type PersistedWorkoutsState = Pick<WorkoutsState, "workouts">

export function sanitizeWorkoutsState(value: unknown): PersistedWorkoutsState {
  const state = isRecord(value) ? value : {}
  const rawWorkouts = Array.isArray(state.workouts) ? state.workouts : []

  return {
    workouts: rawWorkouts.flatMap((value) => {
      if (!isRecord(value)) return []

      const id = validString(value.id)
      const date = validString(value.date)
      if (!id || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return []

      const exerciseIds = validUniqueStrings(value.exerciseIds, (exerciseId) =>
        EXERCISES_BY_ID.has(exerciseId)
      )
      const completionValue = isRecord(value.completion)
        ? value.completion
        : null
      const completedAt = completionValue
        ? validString(completionValue.completedAt)
        : ""
      const startedAt = completionValue
        ? validString(completionValue.startedAt)
        : ""
      const durationMs = completionValue
        ? validNonNegativeNumber(completionValue.durationMs)
        : null
      const activeCalories = completionValue
        ? validNonNegativeNumber(completionValue.activeCalories)
        : null
      const healthSyncStatus = completionValue
        ? validHealthSyncStatus(completionValue.healthSyncStatus)
        : null

      return [
        {
          id,
          name: validString(value.name, "Workout").trim() || "Workout",
          date,
          exerciseIds,
          completion:
            completedAt &&
            startedAt &&
            durationMs !== null &&
            activeCalories !== null
              ? {
                  activeCalories,
                  completedAt,
                  completedExerciseIds: validUniqueStrings(
                    completionValue?.completedExerciseIds,
                    (exerciseId) => exerciseIds.includes(exerciseId)
                  ),
                  durationMs,
                  healthSyncStatus: healthSyncStatus ?? "not-requested",
                  startedAt,
                }
              : null,
          createdAt: validString(value.createdAt),
          updatedAt: validString(value.updatedAt),
        },
      ]
    }),
  }
}

const HEALTH_SYNC_STATUSES = new Set<HealthSyncStatus>([
  "not-requested",
  "pending",
  "synced",
  "failed",
])

function validHealthSyncStatus(value: unknown): HealthSyncStatus | null {
  return typeof value === "string" &&
    HEALTH_SYNC_STATUSES.has(value as HealthSyncStatus)
    ? (value as HealthSyncStatus)
    : null
}

function validNonNegativeNumber(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? value
    : null
}

function makeId() {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`
}

export const useWorkouts = create<WorkoutsState>()(
  persist<WorkoutsState, [], [], PersistedWorkoutsState>(
    (set, get) => ({
      workouts: [],
      createWorkout: ({ name, date, exerciseIds }) => {
        const id = makeId()
        const now = new Date().toISOString()
        const workout: Workout = {
          id,
          name: name.trim() || "Workout",
          date,
          exerciseIds: [...new Set(exerciseIds)],
          completion: null,
          createdAt: now,
          updatedAt: now,
        }
        set((state) => ({ workouts: [...state.workouts, workout] }))
        return id
      },
      updateWorkout: (id, patch) =>
        set((state) => ({
          workouts: state.workouts.map((workout) =>
            workout.id === id
              ? {
                  ...workout,
                  ...patch,
                  name: patch.name?.trim() || workout.name,
                  updatedAt: new Date().toISOString(),
                }
              : workout
          ),
        })),
      deleteWorkout: (id) =>
        set((state) => ({
          workouts: state.workouts.filter((workout) => workout.id !== id),
        })),
      duplicateWorkout: (id) => {
        const source = get().workouts.find((workout) => workout.id === id)
        if (!source) return null
        const newId = makeId()
        const now = new Date().toISOString()
        const copy: Workout = {
          ...source,
          id: newId,
          name: `${source.name} copy`,
          date: toISODate(new Date()),
          completion: null,
          createdAt: now,
          updatedAt: now,
        }
        set((state) => ({ workouts: [...state.workouts, copy] }))
        return newId
      },
      completeWorkout: (id, completion) =>
        set((state) => ({
          workouts: state.workouts.map((workout) =>
            workout.id === id
              ? {
                  ...workout,
                  completion,
                  updatedAt: new Date().toISOString(),
                }
              : workout
          ),
        })),
      setHealthSyncStatus: (id, healthSyncStatus) =>
        set((state) => ({
          workouts: state.workouts.map((workout) =>
            workout.id === id && workout.completion
              ? {
                  ...workout,
                  completion: { ...workout.completion, healthSyncStatus },
                  updatedAt: new Date().toISOString(),
                }
              : workout
          ),
        })),
    }),
    {
      name: "gym-lib-workouts",
      version: 2,
      migrate: (persistedState) => sanitizeWorkoutsState(persistedState),
      merge: (persistedState, currentState) => ({
        ...currentState,
        ...sanitizeWorkoutsState(persistedState),
      }),
      partialize: ({ workouts }) => ({ workouts }),
    }
  )
)
