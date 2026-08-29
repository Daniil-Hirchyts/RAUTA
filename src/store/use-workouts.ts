import { create } from "zustand"
import { persist } from "zustand/middleware"

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

function makeId() {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`
}

export const useWorkouts = create<WorkoutsState>()(
  persist(
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
    { name: "gym-lib-workouts" }
  )
)
