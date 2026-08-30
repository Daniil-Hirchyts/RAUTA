import { useEffect, useState } from "react"
import { ChevronLeft, Copy, Pencil, Trash2 } from "lucide-react"

import { DeleteWorkoutConfirmation } from "@/components/delete-workout-confirmation"
import { ExerciseCard } from "@/components/exercise-card"
import { Button } from "@/components/ui/button"
import { EXERCISES_BY_ID } from "@/lib/exercises"
import { formatDateLong } from "@/lib/date"
import { triggerHaptic } from "@/lib/haptics"
import { useWorkouts, type Workout } from "@/store/use-workouts"
import type { ExerciseSummary } from "@/types"

export function WorkoutDetailPage({
  onBack,
  onDeleted,
  onDuplicated,
  onEdit,
  onOpenExercise,
  workoutId,
}: {
  onBack: () => void
  onDeleted: () => void
  onDuplicated: () => void
  onEdit: (workout: Workout) => void
  onOpenExercise: (exercise: ExerciseSummary) => void
  workoutId: string
}) {
  const workout = useWorkouts((state) =>
    state.workouts.find((item) => item.id === workoutId)
  )
  const duplicateWorkout = useWorkouts((state) => state.duplicateWorkout)
  const deleteWorkout = useWorkouts((state) => state.deleteWorkout)
  const [deleteOpen, setDeleteOpen] = useState(false)

  useEffect(() => {
    if (!workout) onBack()
  }, [onBack, workout])

  if (!workout) {
    return null
  }

  const exercises = workout.exerciseIds
    .map((id) => EXERCISES_BY_ID.get(id))
    .filter((exercise): exercise is ExerciseSummary => Boolean(exercise))

  return (
    <>
      <header className="shrink-0 border-b border-white/[0.05] bg-background/80 px-5 pt-4 pb-4 backdrop-blur-xl">
        <div className="mb-3 flex items-center justify-between gap-2">
          <Button
            aria-label="Back to workouts"
            className="shrink-0 rounded-full"
            onClick={onBack}
            size="icon"
            variant="secondary"
          >
            <ChevronLeft />
          </Button>
          <div className="flex shrink-0 gap-1">
            <Button
              aria-label="Edit workout"
              onClick={() => onEdit(workout)}
              size="icon"
              variant="ghost"
            >
              <Pencil />
            </Button>
            <Button
              aria-label="Duplicate workout"
              onClick={() => {
                duplicateWorkout(workout.id)
                onDuplicated()
              }}
              size="icon"
              variant="ghost"
            >
              <Copy />
            </Button>
            <Button
              aria-label="Delete workout"
              className="text-destructive hover:text-destructive"
              onClick={() => {
                triggerHaptic("warning")
                setDeleteOpen(true)
              }}
              size="icon"
              variant="ghost"
            >
              <Trash2 />
            </Button>
          </div>
        </div>
        <h1 className="text-[26px] font-black tracking-[-0.03em]">
          {formatDateLong(workout.date)}
        </h1>
        <p className="mt-1 text-sm font-medium text-muted-foreground">
          {exercises.length} exercise{exercises.length === 1 ? "" : "s"}
        </p>
      </header>

      <div className="flex-1 overflow-y-auto px-5 pt-5 pb-5">
        {exercises.length === 0 ? (
          <p className="py-12 text-center text-base text-muted-foreground">
            No exercises in this workout.
          </p>
        ) : (
          <div className="t-stagger is-shown grid grid-cols-2 gap-3.5">
            {exercises.map((exercise, index) => (
              <ExerciseCard
                exercise={exercise}
                index={index}
                key={exercise.id}
                onOpenDetail={onOpenExercise}
                onToggleSelect={() => {}}
                selectMode={false}
              />
            ))}
          </div>
        )}
      </div>

      <DeleteWorkoutConfirmation
        onConfirm={() => {
          deleteWorkout(workout.id)
          onDeleted()
        }}
        onOpenChange={setDeleteOpen}
        open={deleteOpen}
      />
    </>
  )
}
