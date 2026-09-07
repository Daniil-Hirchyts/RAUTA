import { replacementIds } from "@/lib/training-workflow"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts } from "@/store/use-workouts"

/**
 * Replaces one exercise while a planned workout is actually being performed.
 *
 * The program snapshot remains immutable. The structured draft changes first,
 * preserving its plannedExerciseId/set lineage, then the legacy workout shell
 * is updated so the existing timer/checklist UI follows the performed exercise.
 */
export function substituteRunningPlannedExercise(
  workoutId: string,
  exerciseId: string,
  replacementId: string
) {
  const workouts = useWorkouts.getState()
  const workout = workouts.workouts.find((item) => item.id === workoutId)
  const running = useActiveWorkout.getState().session
  const records = useTrainingRecords.getState()
  const draft = records.data.activeWorkout

  if (!workout?.planned || running?.workoutId !== workoutId)
    throw new Error("Start this planned workout before changing an exercise.")
  if (
    !draft ||
    draft.sourceWorkoutId !== workoutId ||
    draft.plannedProgramId !== workout.planned.programId ||
    draft.plannedSessionId !== workout.planned.sessionId
  )
    throw new Error(
      "The active training record no longer matches this workout."
    )
  if (workout.exerciseIds.includes(replacementId))
    throw new Error("That exercise is already in this workout.")
  if (!replacementIds(exerciseId).includes(replacementId))
    throw new Error("That alternative no longer fits this training session.")

  const entry = draft.exercises.find(
    (item) => item.exerciseId === exerciseId && item.plannedExerciseId
  )
  if (!entry)
    throw new Error("Planned exercise not found in the active workout.")

  // This must happen before updateWorkout: that update synchronizes the legacy
  // active session immediately, and its subscriber mirrors new IDs into the
  // structured draft. Substituting first prevents the replacement from being
  // mistaken for an additional unplanned exercise.
  records.substituteExercise(entry.id, replacementId)
  workouts.updateWorkout(workoutId, {
    exerciseIds: workout.exerciseIds.map((id) =>
      id === exerciseId ? replacementId : id
    ),
  })
}
