import { create } from "zustand"
import { persist } from "zustand/middleware"

import {
  elapsedMs,
  nextPendingExerciseId,
  type ActiveWorkoutSession,
} from "@/lib/active-workout"
import { EXERCISES_BY_ID } from "@/lib/exercises"
import { isRecord, validString, validUniqueStrings } from "@/store/persistence"
import { useWorkouts, type Workout } from "@/store/use-workouts"

/** Why the last session stopped. Read by the Live Activity sync to decide
 *  between a lingering "workout complete" card and an immediate dismissal. */
export type ActiveWorkoutOutcome = "finished" | "cancelled"

export type ActiveWorkoutState = {
  session: ActiveWorkoutSession | null
  lastOutcome: ActiveWorkoutOutcome | null
  start: (workout: Workout) => void
  finish: () => void
  cancel: () => void
  pause: () => void
  resume: () => void
  setCurrentExercise: (exerciseId: string) => void
  toggleComplete: (exerciseId: string) => void
  completeCurrent: () => void
  /** Keeps a running session aligned with edits made to the saved workout. */
  syncExercises: (exerciseIds: string[]) => void
}

type PersistedActiveWorkoutState = Pick<ActiveWorkoutState, "session">

function sanitizeSession(value: unknown): ActiveWorkoutSession | null {
  if (!isRecord(value)) return null

  const workoutId = validString(value.workoutId)
  if (!workoutId) return null

  const exerciseIds = validUniqueStrings(value.exerciseIds, (id) =>
    EXERCISES_BY_ID.has(id)
  )
  if (exerciseIds.length === 0) return null

  const completedIds = validUniqueStrings(value.completedIds, (id) =>
    exerciseIds.includes(id)
  )
  const currentExerciseId = validString(value.currentExerciseId)
  const runningSince = validTimestamp(value.runningSince)

  return {
    workoutId,
    workoutName: validString(value.workoutName, "Workout").trim() || "Workout",
    workoutDate: validString(value.workoutDate),
    exerciseIds,
    completedIds,
    currentExerciseId: exerciseIds.includes(currentExerciseId)
      ? currentExerciseId
      : null,
    runningSince,
    accumulatedMs: Math.max(0, validNumber(value.accumulatedMs)),
    startedAt: validTimestamp(value.startedAt) ?? Date.now(),
  }
}

function validNumber(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? value : 0
}

function validTimestamp(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? value
    : null
}

function sanitizeActiveWorkoutState(
  value: unknown
): PersistedActiveWorkoutState {
  const state = isRecord(value) ? value : {}
  return { session: sanitizeSession(state.session) }
}

/** Applies `patch` to the live session, or does nothing when idle. */
function patchSession(
  update: (session: ActiveWorkoutSession) => ActiveWorkoutSession
) {
  return (state: ActiveWorkoutState) =>
    state.session ? { session: update(state.session) } : {}
}

export const useActiveWorkout = create<ActiveWorkoutState>()(
  persist<ActiveWorkoutState, [], [], PersistedActiveWorkoutState>(
    (set) => ({
      session: null,
      lastOutcome: null,
      start: (workout) => {
        const exerciseIds = workout.exerciseIds.filter((id) =>
          EXERCISES_BY_ID.has(id)
        )
        if (exerciseIds.length === 0) return

        const now = Date.now()
        set({
          lastOutcome: null,
          session: {
            workoutId: workout.id,
            workoutName: workout.name,
            workoutDate: workout.date,
            exerciseIds,
            completedIds: [],
            currentExerciseId: exerciseIds[0],
            runningSince: now,
            accumulatedMs: 0,
            startedAt: now,
          },
        })
      },
      finish: () => set({ session: null, lastOutcome: "finished" }),
      cancel: () => set({ session: null, lastOutcome: "cancelled" }),
      pause: () =>
        set(
          patchSession((session) =>
            session.runningSince === null
              ? session
              : {
                  ...session,
                  accumulatedMs: elapsedMs(session),
                  runningSince: null,
                }
          )
        ),
      resume: () =>
        set(
          patchSession((session) =>
            session.runningSince === null
              ? { ...session, runningSince: Date.now() }
              : session
          )
        ),
      setCurrentExercise: (exerciseId) =>
        set(
          patchSession((session) =>
            session.exerciseIds.includes(exerciseId)
              ? {
                  ...session,
                  // Re-selecting a finished exercise means it is being done
                  // again, so it goes back to being the one in progress.
                  completedIds: session.completedIds.filter(
                    (id) => id !== exerciseId
                  ),
                  currentExerciseId: exerciseId,
                }
              : session
          )
        ),
      toggleComplete: (exerciseId) =>
        set(
          patchSession((session) => {
            if (!session.exerciseIds.includes(exerciseId)) return session

            if (session.completedIds.includes(exerciseId)) {
              return {
                ...session,
                completedIds: session.completedIds.filter(
                  (id) => id !== exerciseId
                ),
                currentExerciseId: session.currentExerciseId ?? exerciseId,
              }
            }

            const completed = {
              ...session,
              completedIds: [...session.completedIds, exerciseId],
            }

            return exerciseId === session.currentExerciseId
              ? {
                  ...completed,
                  currentExerciseId: nextPendingExerciseId(
                    completed,
                    exerciseId
                  ),
                }
              : completed
          })
        ),
      completeCurrent: () =>
        set(
          patchSession((session) => {
            const exerciseId = session.currentExerciseId
            if (!exerciseId || session.completedIds.includes(exerciseId)) {
              return session
            }

            const completed = {
              ...session,
              completedIds: [...session.completedIds, exerciseId],
            }
            return {
              ...completed,
              currentExerciseId: nextPendingExerciseId(completed, exerciseId),
            }
          })
        ),
      syncExercises: (exerciseIds) =>
        set((state) => {
          const { session } = state
          if (!session) return {}

          const next = exerciseIds.filter((id) => EXERCISES_BY_ID.has(id))
          // Emptying the workout leaves nothing to perform, so the session
          // ends rather than lingering with no current exercise.
          if (next.length === 0) {
            return { session: null, lastOutcome: "cancelled" as const }
          }

          const completedIds = session.completedIds.filter((id) =>
            next.includes(id)
          )
          const currentExerciseId =
            session.currentExerciseId &&
            next.includes(session.currentExerciseId)
              ? session.currentExerciseId
              : (next.find((id) => !completedIds.includes(id)) ?? null)

          return {
            session: {
              ...session,
              exerciseIds: next,
              completedIds,
              currentExerciseId,
            },
          }
        }),
    }),
    {
      name: "gym-lib-active-workout",
      version: 1,
      migrate: (persistedState) => sanitizeActiveWorkoutState(persistedState),
      merge: (persistedState, currentState) => ({
        ...currentState,
        ...sanitizeActiveWorkoutState(persistedState),
      }),
      partialize: ({ session }) => ({ session }),
    }
  )
)

/**
 * A session cannot outlive the workout it is performing. Workouts can be
 * deleted from the list, from the detail page, and from a swipe action, so the
 * invariant lives here rather than at every call site — otherwise one missed
 * path leaves a Live Activity counting for a workout that no longer exists.
 *
 * `useWorkouts` is fully hydrated by the time this module finishes importing,
 * and subscribers only hear about later changes, so a session restored from
 * storage is never mistaken for an orphan.
 */
useWorkouts.subscribe((state) => {
  const { session } = useActiveWorkout.getState()
  if (!session) return
  if (state.workouts.some((workout) => workout.id === session.workoutId)) return

  useActiveWorkout.getState().cancel()
})
