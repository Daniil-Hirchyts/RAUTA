import { create } from "zustand"
import { persist } from "zustand/middleware"

import { EXERCISES_BY_ID } from "@/lib/exercises"
import { isRecord, validString, validUniqueStrings } from "@/store/persistence"

export type Workout = {
  id: string
  name: string
  date: string
  exerciseIds: string[]
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
}

type PersistedWorkoutsState = Pick<WorkoutsState, "workouts">

function sanitizeWorkoutsState(value: unknown): PersistedWorkoutsState {
  const state = isRecord(value) ? value : {}
  const rawWorkouts = Array.isArray(state.workouts) ? state.workouts : []

  return {
    workouts: rawWorkouts.flatMap((value) => {
      if (!isRecord(value)) return []

      const id = validString(value.id)
      const date = validString(value.date)
      if (!id || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return []

      return [
        {
          id,
          name: validString(value.name, "Workout").trim() || "Workout",
          date,
          exerciseIds: validUniqueStrings(value.exerciseIds, (exerciseId) =>
            EXERCISES_BY_ID.has(exerciseId)
          ),
          createdAt: validString(value.createdAt),
          updatedAt: validString(value.updatedAt),
        },
      ]
    }),
  }
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
          createdAt: now,
          updatedAt: now,
        }
        set((state) => ({ workouts: [...state.workouts, copy] }))
        return newId
      },
    }),
    {
      name: "gym-lib-workouts",
      version: 1,
      migrate: (persistedState) => sanitizeWorkoutsState(persistedState),
      merge: (persistedState, currentState) => ({
        ...currentState,
        ...sanitizeWorkoutsState(persistedState),
      }),
      partialize: ({ workouts }) => ({ workouts }),
    }
  )
)
