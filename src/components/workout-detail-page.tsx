import { useEffect, useState } from "react"
import { ChevronLeft, Copy, Trash2 } from "lucide-react"

import { DeleteWorkoutConfirmation } from "@/components/delete-workout-confirmation"
import { ExerciseCard } from "@/components/exercise-card"
import { Button } from "@/components/ui/button"
import { useLoadMoreOnScroll } from "@/hooks/use-load-more-on-scroll"
import { EXERCISE_PAGE_SIZE, EXERCISES_BY_ID } from "@/lib/exercises"
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

  // exercises/the hook below must run before the early return — hooks
  // can't follow a conditional return without breaking React's rule that
  // the same hooks run in the same order on every render.
  const exercises = (workout?.exerciseIds ?? [])
    .map((id) => EXERCISES_BY_ID.get(id))
    .filter((exercise): exercise is ExerciseSummary => Boolean(exercise))

  const {
    hasMore,
    rootRef: scrollRef,
    sentinelRef,
    visibleCount,
  } = useLoadMoreOnScroll<HTMLDivElement>(exercises.length, EXERCISE_PAGE_SIZE)
  const pagedExercises = exercises.slice(0, visibleCount)

  if (!workout) {
    return null
  }

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
          {exercises.length} exercise{exercises.length === 1 ? "" : "s"}
        </p>
      </header>

      <div className="flex-1 overflow-y-auto px-5 pt-5 pb-5" ref={scrollRef}>
        {exercises.length === 0 ? (
          <p className="py-12 text-center text-base text-muted-foreground">
            No exercises in this workout.
          </p>
        ) : (
          <>
            <div className="t-stagger is-shown grid grid-cols-2 gap-3.5">
              {pagedExercises.map((exercise, index) => (
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
            {hasMore && (
              <div aria-hidden="true" className="h-1" ref={sentinelRef} />
            )}
          </>
        )}
      </div>

      <footer className="bottom-controls-scrim shrink-0 px-5 pt-4 pb-[calc(1rem+env(safe-area-inset-bottom))]">
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
            aria-label="Duplicate workout"
            className="size-[3.25rem] rounded-[26px]"
            onClick={() => {
              duplicateWorkout(workout.id)
              onDuplicated()
            }}
            size="icon"
            variant="secondary"
          >
            <Copy />
          </Button>
          <Button
            aria-label="Edit workout"
            className="h-[3.25rem] flex-1 rounded-[26px] text-base font-semibold"
            onClick={() => onEdit(workout)}
          >
            Edit
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
