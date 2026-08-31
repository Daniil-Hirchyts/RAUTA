import { useState } from "react"
import { CalendarDays, ChevronLeft, ChevronRight, Trash2 } from "lucide-react"

import { BodyPreview } from "@/components/body-map"
import { DeleteWorkoutConfirmation } from "@/components/delete-workout-confirmation"
import { SwipeableRow } from "@/components/swipeable-row"
import { Button } from "@/components/ui/button"
import { formatDateShort } from "@/lib/date"
import { musclesForExerciseIds } from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { useWorkouts, type Workout } from "@/store/use-workouts"

export function WorkoutsPage({
  onBack,
  onSelect,
}: {
  onBack: () => void
  onSelect: (workout: Workout) => void
}) {
  const workouts = useWorkouts((state) => state.workouts)
  const deleteWorkout = useWorkouts((state) => state.deleteWorkout)
  const sorted = [...workouts].sort((left, right) =>
    left.date.localeCompare(right.date)
  )

  const [openRowId, setOpenRowId] = useState<string | null>(null)
  const [pendingDelete, setPendingDelete] = useState<Workout | null>(null)

  return (
    <>
      <header className="shrink-0 border-b border-white/[0.05] bg-background/80 px-5 pt-4 pb-4 backdrop-blur-xl">
        <div className="flex items-center gap-3">
          <Button
            aria-label="Back"
            className="shrink-0 rounded-full"
            onClick={onBack}
            size="icon"
            variant="secondary"
          >
            <ChevronLeft />
          </Button>
          <h1 className="bg-gradient-to-r from-foreground to-foreground/75 bg-clip-text text-[26px] font-black tracking-[-0.03em] text-transparent">
            My workouts
          </h1>
        </div>
      </header>

      <div className="flex min-h-0 flex-1 flex-col overflow-y-auto py-5">
        {sorted.length === 0 ? (
          <div className="flex flex-1 flex-col items-center justify-center gap-3 px-5 text-center">
            <CalendarDays className="size-7 text-[color-mix(in_oklch,var(--muted-foreground),var(--background)_35%)]" />
            <p className="max-w-[24rem] text-base text-muted-foreground">
              No workouts yet. Select exercises on the Exercises step and tap
              "Add to workout".
            </p>
          </div>
        ) : (
          <ul className="space-y-3">
            {sorted.map((workout) => {
              const isOpen = openRowId === workout.id
              const targetMuscles = musclesForExerciseIds(workout.exerciseIds)
              return (
                <li key={workout.id}>
                  <SwipeableRow
                    actionInset={20}
                    action={
                      <button
                        aria-label={`Delete ${formatDateShort(workout.date)} workout`}
                        className="text-destructive-foreground grid size-14 shrink-0 place-items-center rounded-full bg-destructive shadow-lg shadow-black/20 transition-transform duration-150 active:scale-90"
                        data-haptics="off"
                        onClick={() => {
                          triggerHaptic("warning")
                          setOpenRowId(null)
                          setPendingDelete(workout)
                        }}
                        type="button"
                      >
                        <Trash2 className="size-5" />
                      </button>
                    }
                    isOpen={isOpen}
                    onOpenChange={(open) => {
                      if (open) triggerHaptic("selection")
                      setOpenRowId(open ? workout.id : null)
                    }}
                  >
                    <button
                      className="mx-5 flex w-[calc(100%-2.5rem)] items-center justify-between gap-3 rounded-2xl border border-border bg-card p-4 text-left transition-colors duration-150 active:bg-muted"
                      data-haptics="off"
                      onClick={() => {
                        if (isOpen) {
                          setOpenRowId(null)
                          return
                        }
                        onSelect(workout)
                      }}
                      type="button"
                    >
                      <div className="min-w-0">
                        <p className="text-lg font-bold tracking-[-0.01em]">
                          {formatDateShort(workout.date)}
                        </p>
                        <p className="mt-0.5 text-sm font-medium text-muted-foreground">
                          {workout.exerciseIds.length} exercise
                          {workout.exerciseIds.length === 1 ? "" : "s"}
                        </p>
                      </div>
                      <BodyPreview
                        className="h-16 w-24 shrink-0"
                        selectedMuscles={targetMuscles}
                      />
                      <ChevronRight className="size-5 shrink-0 text-muted-foreground" />
                    </button>
                  </SwipeableRow>
                </li>
              )
            })}
          </ul>
        )}
      </div>

      <DeleteWorkoutConfirmation
        onConfirm={() => {
          if (pendingDelete) deleteWorkout(pendingDelete.id)
        }}
        onOpenChange={(open) => {
          if (!open) setPendingDelete(null)
        }}
        open={pendingDelete !== null}
      />
    </>
  )
}
