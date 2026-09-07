import { create } from "zustand"
import { persist } from "zustand/middleware"

import {
  elapsedMs,
  nextPendingExerciseId,
  type ActiveWorkoutSession,
} from "@/lib/active-workout"
import { EXERCISES_BY_ID } from "@/lib/exercises"
import {
  beginTrainingDraft,
  endTrainingDraft,
  performedExerciseIds,
  syncTrainingDraftExercises,
} from "@/lib/training-session"
import { estimateStrengthCalories, isPastWorkout } from "@/lib/workout-stats"
import { isRecord, validString, validUniqueStrings } from "@/store/persistence"
import { useSettings } from "@/store/use-settings"
import { useWorkouts, type Workout } from "@/store/use-workouts"

/** Why the last session stopped. Read by the Live Activity sync to decide
 *  between a lingering "workout complete" card and an immediate dismissal. */
export type ActiveWorkoutOutcome = "finished" | "cancelled"

export type ActiveWorkoutState = {
  session: ActiveWorkoutSession | null
  lastOutcome: ActiveWorkoutOutcome | null
  start: (workout: Workout) => boolean
  finish: () => void
  cancel: () => void
  pause: () => void
  resume: () => void
  setCurrentExercise: (exerciseId: string) => void
  toggleComplete: (exerciseId: string) => void
  completeCurrent: () => void
  /** Keeps a running session aligned with edits made to the saved workout. */
  syncExercises: (exerciseIds: string[], movedExerciseId?: string) => void
  /** The same, for every part of the workout the session mirrors. */
  syncWorkout: (workout: Workout) => void
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

function sameOrder(left: string[], right: string[]) {
  return (
    left.length === right.length &&
    left.every((value, index) => value === right[index])
  )
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
    (set, get) => ({
      session: null,
      lastOutcome: null,
      start: (workout) => {
        if (isPastWorkout(workout)) return false
        const exerciseIds = workout.exerciseIds.filter((id) =>
          EXERCISES_BY_ID.has(id)
        )
        if (exerciseIds.length === 0) return false

        const now = Date.now()
        // Open the structured record before exposing a running session. A
        // planned workout whose program/session can no longer be resolved must
        // not silently become a free workout or leave a shell session behind.
        const draftStarted = beginTrainingDraft(
          exerciseIds,
          new Date(now).toISOString(),
          workout.id,
          workout.planned
        )
        if (!draftStarted) return false

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
        return true
      },
      finish: () => {
        const { session } = get()
        if (!session) return

        const durationMs = elapsedMs(session)
        const settings = useSettings.getState()
        const completedAt = new Date().toISOString()
        const shouldSync =
          settings.appleHealthEnabled && settings.autoSyncWorkouts
        // An exercise counts as performed if it was checked off or if it holds
        // real sets, so the saved workout cannot claim less work than the
        // structured session it was recorded alongside.
        const performed = performedExerciseIds()

        useWorkouts.getState().completeWorkout(session.workoutId, {
          activeCalories: estimateStrengthCalories(
            durationMs,
            settings.healthBodyWeightKg
          ),
          completedAt,
          completedExerciseIds: session.exerciseIds.filter(
            (id) => session.completedIds.includes(id) || performed.has(id)
          ),
          durationMs,
          healthSyncStatus: shouldSync ? "pending" : "not-requested",
          startedAt: new Date(session.startedAt).toISOString(),
        })
        // Both records close together: the legacy workout keeps duration,
        // calories and which exercises were checked off, while the structured
        // session keeps the sets that were really performed.
        endTrainingDraft("finished", completedAt)
        set({ session: null, lastOutcome: "finished" })
      },
      cancel: () => {
        // A discarded session is still evidence of the sets it did produce, so
        // they are kept as a partial session rather than thrown away.
        if (get().session) endTrainingDraft("cancelled")
        set({ session: null, lastOutcome: "cancelled" })
      },
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
      syncExercises: (exerciseIds, movedExerciseId) => {
        const wasRunning = get().session !== null
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
          let currentExerciseId =
            session.currentExerciseId &&
            next.includes(session.currentExerciseId)
              ? session.currentExerciseId
              : (next.find((id) => !completedIds.includes(id)) ?? null)

          // The active marker represents the current position in the workout.
          // If that row itself is moved, keep the position active and advance
          // to the first unfinished exercise now occupying/after that slot.
          if (
            movedExerciseId === session.currentExerciseId &&
            session.currentExerciseId
          ) {
            const previousIndex = session.exerciseIds.indexOf(
              session.currentExerciseId
            )
            const startIndex = Math.min(
              Math.max(previousIndex, 0),
              next.length - 1
            )
            const fromCurrentSlot = [
              ...next.slice(startIndex),
              ...next.slice(0, startIndex),
            ]
            currentExerciseId =
              fromCurrentSlot.find((id) => !completedIds.includes(id)) ?? null
          }

          return {
            session: {
              ...session,
              exerciseIds: next,
              completedIds,
              currentExerciseId,
            },
          }
        })

        if (!wasRunning) return
        const running = get().session
        if (running) syncTrainingDraftExercises(running.exerciseIds)
        else endTrainingDraft("cancelled")
      },
      syncWorkout: (workout) => {
        const { session } = get()
        if (!session || session.workoutId !== workout.id) return

        // The date is on the Lock Screen card, so moving a workout has to
        // reach the session too — otherwise the card keeps naming the day the
        // workout used to be on.
        if (
          session.workoutDate !== workout.date ||
          session.workoutName !== workout.name
        ) {
          set(
            patchSession((current) => ({
              ...current,
              workoutDate: workout.date,
              workoutName: workout.name,
            }))
          )
        }

        // Compared after the same filtering `syncExercises` applies, so an
        // id the library does not know cannot make the two look forever out
        // of step and re-sync on every unrelated change.
        const exerciseIds = workout.exerciseIds.filter((id) =>
          EXERCISES_BY_ID.has(id)
        )
        if (!sameOrder(session.exerciseIds, exerciseIds)) {
          get().syncExercises(exerciseIds)
        }
      },
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
 * A session follows the workout it is performing, wherever that workout is
 * edited from. Workouts can be deleted from the list, from the detail page and
 * from a swipe action, and exercises can be added to a running one from the
 * whole find-an-exercise flow — so the invariant lives here rather than at
 * every call site. One missed path leaves a Live Activity counting for a
 * workout that no longer exists, or a session that never hears about the
 * exercise just added to it.
 *
 * `useWorkouts` is fully hydrated by the time this module finishes importing,
 * and subscribers only hear about later changes, so a session restored from
 * storage is never mistaken for an orphan.
 */
useWorkouts.subscribe((state) => {
  const { session } = useActiveWorkout.getState()
  if (!session) return

  const workout = state.workouts.find((item) => item.id === session.workoutId)
  if (!workout) {
    useActiveWorkout.getState().cancel()
    return
  }

  useActiveWorkout.getState().syncWorkout(workout)
})
