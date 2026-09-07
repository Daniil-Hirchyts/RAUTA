import {
  createTrainingWeek,
  plannedWorkoutFor,
  type PlannedSessionView,
} from "@/lib/training-plan"
import { endTrainingDraft } from "@/lib/training-session"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useFilters } from "@/store/use-filters"
import { DEFAULT_SETTINGS, useSettings } from "@/store/use-settings"
import { useTrainingProfile } from "@/store/use-training-profile"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts } from "@/store/use-workouts"
import { createEmptyPersistedTrainingState } from "@/training-persistence/schema"

export const ADAPT_NOW = "2026-09-15T12:00:00.000Z"
export const records = () => useTrainingRecords.getState()

export function adaptationWeek() {
  localStorage.clear()
  useTrainingRecords.setState({
    data: createEmptyPersistedTrainingState(),
    persistenceIssues: [],
  })
  useWorkouts.setState({ workouts: [] })
  useActiveWorkout.setState({ session: null, lastOutcome: null })
  useTrainingProfile.getState().resetTrainingProfile()
  useSettings.setState(DEFAULT_SETTINGS)
  useFilters.setState({
    equipmentPresets: [],
    gymEquipment: ["dumbbell"],
    selectedEquipment: [],
    selectedMuscles: [],
  })
  const result = createTrainingWeek({
    days: [0, 2, 4],
    now: "2026-09-07T10:00:00.000Z",
  })
  if (result.status !== "created") throw new Error(result.message)
  return result.sessions
}

export function logPlannedSession(
  session: PlannedSessionView,
  status: "completed" | "partial" = "completed",
  options: {
    empty?: boolean
    date?: string
    exerciseId?: string
    sets?: number
    reps?: number
    rir?: number
    loadKg?: number
    stationId?: string
    basis?: "total" | "per_implement"
  } = {}
) {
  const date = options.date ?? session.date
  const workout = plannedWorkoutFor(session)!
  records().startPlannedWorkout(
    session.programId,
    session.sessionId,
    `${date}T10:00:00.000Z`,
    workout.id
  )
  if (
    options.exerciseId &&
    !records().data.activeWorkout!.exercises.some(
      (item) => item.exerciseId === options.exerciseId
    )
  ) {
    records().substituteExercise(
      records().data.activeWorkout!.exercises[0].id,
      options.exerciseId
    )
  }
  const exercise = records().data.activeWorkout!.exercises.find(
    (item) => !options.exerciseId || item.exerciseId === options.exerciseId
  )!
  if (!options.empty) {
    for (let index = 0; index < (options.sets ?? 1); index++) {
      const set = exercise.sets.filter((item) => item.setType === "working")[
        index
      ]
      const observation = {
        reps: options.reps ?? 13,
        rir: options.rir ?? 2,
        resistance: {
          type: "external_load" as const,
          kg: options.loadKg ?? 40,
          stationId: options.stationId ?? "Rack A",
          basis: options.basis ?? ("total" as const),
        },
        completed: true,
        timestamp: `${date}T10:05:00.000Z`,
      }
      if (set)
        records().recordSet({
          exerciseEntryId: exercise.id,
          setDraftId: set.id,
          observation,
        })
      else
        records().addUnplannedSet({
          exerciseEntryId: exercise.id,
          setType: "working",
          side: "both",
          observation,
        })
    }
  }
  const id = endTrainingDraft(
    status === "completed" ? "finished" : "cancelled",
    `${date}T10:30:00.000Z`
  )!
  if (status === "completed")
    useWorkouts.getState().completeWorkout(workout.id, {
      startedAt: `${date}T10:00:00.000Z`,
      completedAt: `${date}T10:30:00.000Z`,
      durationMs: 1800000,
      activeCalories: 100,
      completedExerciseIds: options.empty ? [] : [exercise.exerciseId],
      healthSyncStatus: "not-requested",
    })
  return id
}
