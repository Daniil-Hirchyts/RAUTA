import { useEffect, useState } from "react"
import { ChevronLeft, Plus, Trash2 } from "lucide-react"

import { DeleteWorkoutConfirmation } from "@/components/delete-workout-confirmation"
import { SortableExerciseList } from "@/components/sortable-exercise-list"
import { Button } from "@/components/ui/button"
import { formatDateLong } from "@/lib/date"
import { triggerHaptic } from "@/lib/haptics"
import { useWorkouts } from "@/store/use-workouts"
import type { ExerciseSummary } from "@/types"

export function WorkoutDetailPage({
  onAddExercise,
  onBack,
  onDeleted,
  onOpenExercise,
  workoutId,
}: {
  onAddExercise: () => void
  onBack: () => void
  onDeleted: () => void
  onOpenExercise: (exercise: ExerciseSummary) => void
  workoutId: string
}) {
  const workout = useWorkouts((state) =>
    state.workouts.find((item) => item.id === workoutId)
  )
  const updateWorkout = useWorkouts((state) => state.updateWorkout)
  const deleteWorkout = useWorkouts((state) => state.deleteWorkout)
  const [deleteOpen, setDeleteOpen] = useState(false)

  useEffect(() => {
    if (!workout) onBack()
  }, [onBack, workout])

  if (!workout) return null

  const setExerciseIds = (exerciseIds: string[]) =>
    updateWorkout(workout.id, { exerciseIds })

  return (
    <>
      <header className="shrink-0 border-b border-white/[0.05] bg-background/80 px-5 pt-4 pb-4 backdrop-blur-xl">
        <div className="mb-3 flex items-center gap-2">
          <Button
            aria-label="Back to workouts"
            className="shrink-0 rounded-full"
            onClick={onBack}
            size="icon"
            variant="secondary"
          >
            <ChevronLeft />
          </Button>
        </div>
        <h1 className="text-[26px] font-black tracking-[-0.03em]">
          {formatDateLong(workout.date)}
        </h1>
        <p className="mt-1 text-sm font-medium text-muted-foreground">
          {workout.exerciseIds.length} exercise
          {workout.exerciseIds.length === 1 ? "" : "s"}
        </p>
      </header>

      <div className="min-h-0 flex-1 overflow-y-auto pt-5 pb-[calc(6.5rem+env(safe-area-inset-bottom))]">
        {workout.exerciseIds.length === 0 ? (
          <div className="flex min-h-[18rem] flex-col items-center justify-center gap-3 px-8 text-center">
            <p className="text-base text-muted-foreground">
              This workout is empty. Add an exercise to start building it.
            </p>
          </div>
        ) : (
          <SortableExerciseList
            exerciseIds={workout.exerciseIds}
            onOpenExercise={onOpenExercise}
            onRemove={(id) => {
              triggerHaptic("warning")
              setExerciseIds(
                workout.exerciseIds.filter((exerciseId) => exerciseId !== id)
              )
            }}
            onReorder={setExerciseIds}
          />
        )}
      </div>

      <footer className="bottom-controls-scrim absolute inset-x-0 bottom-0 z-20 px-5 pt-4 pb-[calc(1rem+env(safe-area-inset-bottom))]">
        <div className="flex items-center gap-2.5">
          <Button
            aria-label="Delete workout"
            className="size-[3.25rem] rounded-[26px]"
            onClick={() => {
              triggerHaptic("warning")
              setDeleteOpen(true)
            }}
            size="icon"
            variant="destructive"
          >
            <Trash2 />
          </Button>
          <Button
            className="h-[3.25rem] flex-1 rounded-[26px] text-base font-semibold"
            onClick={onAddExercise}
          >
            <Plus className="size-5" />
            Add exercise
          </Button>
        </div>
      </footer>

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
