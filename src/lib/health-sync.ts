import { elapsedMs, type ActiveWorkoutSession } from "@/lib/active-workout"
import { saveCompletedWorkoutToHealth } from "@/lib/health"
import { estimateStrengthCalories } from "@/lib/workout-stats"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useSettings } from "@/store/use-settings"
import { useWorkouts } from "@/store/use-workouts"

async function syncSession(session: ActiveWorkoutSession) {
  const settings = useSettings.getState()
  if (!settings.appleHealthEnabled || !settings.autoSyncWorkouts) return

  const durationMs = elapsedMs(session)
  const workout = useWorkouts
    .getState()
    .workouts.find((item) => item.id === session.workoutId)
  const activeCalories =
    workout?.completion?.activeCalories ??
    estimateStrengthCalories(durationMs, settings.healthBodyWeightKg)

  const success = await saveCompletedWorkoutToHealth({
    activeCalories:
      settings.syncActiveCalories && activeCalories !== undefined
        ? activeCalories
        : undefined,
    endDate: new Date(session.startedAt + durationMs).toISOString(),
    startDate: new Date(session.startedAt).toISOString(),
    workoutId: session.workoutId,
  })
  useWorkouts
    .getState()
    .setHealthSyncStatus(session.workoutId, success ? "synced" : "failed")
}

/** Syncs only intentional finishes; discarded sessions are never exported. */
export function startAppleHealthSync() {
  return useActiveWorkout.subscribe((state, previous) => {
    if (
      previous.session &&
      !state.session &&
      state.lastOutcome === "finished"
    ) {
      void syncSession(previous.session).catch(() => {
        useWorkouts
          .getState()
          .setHealthSyncStatus(previous.session!.workoutId, "failed")
      })
    }
  })
}
