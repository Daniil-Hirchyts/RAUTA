import { elapsedMs, type ActiveWorkoutSession } from "@/lib/active-workout"
import { saveCompletedWorkoutToHealth } from "@/lib/health"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useSettings } from "@/store/use-settings"

function estimatedStrengthCalories(durationMs: number) {
  return Math.max(1, Math.round((durationMs / 60_000) * 6))
}

async function syncSession(session: ActiveWorkoutSession) {
  const settings = useSettings.getState()
  if (!settings.appleHealthEnabled || !settings.autoSyncWorkouts) return

  const durationMs = elapsedMs(session)
  await saveCompletedWorkoutToHealth({
    activeCalories: settings.syncActiveCalories
      ? estimatedStrengthCalories(durationMs)
      : undefined,
    endDate: new Date(session.startedAt + durationMs).toISOString(),
    startDate: new Date(session.startedAt).toISOString(),
    workoutId: session.workoutId,
    workoutName: session.workoutName,
  })
}

/** Syncs only intentional finishes; discarded sessions are never exported. */
export function startAppleHealthSync() {
  return useActiveWorkout.subscribe((state, previous) => {
    if (
      previous.session &&
      !state.session &&
      state.lastOutcome === "finished"
    ) {
      void syncSession(previous.session).catch(() => undefined)
    }
  })
}
