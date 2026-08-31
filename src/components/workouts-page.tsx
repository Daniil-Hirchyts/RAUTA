import { useState } from "react"
import {
  CalendarDays,
  ChevronRight,
  Copy,
  Settings,
  Trash2,
} from "lucide-react"

import { BodyPreview } from "@/components/body-map"
import { DeleteWorkoutConfirmation } from "@/components/delete-workout-confirmation"
import { SwipeableRow } from "@/components/swipeable-row"
import { WorkoutHeatmap } from "@/components/workout-heatmap"
import { Button } from "@/components/ui/button"
import { useElapsedMs } from "@/hooks/use-elapsed-ms"
import { formatDuration, sessionProgress } from "@/lib/active-workout"
import { formatDateShort } from "@/lib/date"
import { musclesForExerciseIds } from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useWorkouts, type Workout } from "@/store/use-workouts"

export function WorkoutsPage({
  onCreate,
  onSelect,
  onSettings,
}: {
  onCreate: () => void
  onSelect: (workout: Workout) => void
  onSettings: () => void
}) {
  const workouts = useWorkouts((state) => state.workouts)
  const deleteWorkout = useWorkouts((state) => state.deleteWorkout)
  const duplicateWorkout = useWorkouts((state) => state.duplicateWorkout)
  const sorted = [...workouts].sort((left, right) =>
    right.date.localeCompare(left.date)
  )

  const [openRowId, setOpenRowId] = useState<string | null>(null)
  const [pendingDelete, setPendingDelete] = useState<Workout | null>(null)

  // At most one workout is being performed, so the clock ticks once for the
  // whole list rather than once per row.
  const session = useActiveWorkout((state) => state.session)
  const elapsed = useElapsedMs(session)

  return (
    <>
      <header className="shrink-0 border-b border-white/[0.05] bg-background/80 px-5 pt-4 pb-4 backdrop-blur-xl">
        <div className="flex items-center justify-between gap-3">
          <h1 className="bg-gradient-to-r from-foreground to-foreground/75 bg-clip-text text-[30px] font-black tracking-[-0.03em] text-transparent">
            My workouts
          </h1>
          <Button
            aria-label="Settings"
            className="rounded-full"
            onClick={onSettings}
            size="icon"
            variant="secondary"
          >
            <Settings className="size-5" />
          </Button>
        </div>
      </header>

      <div className="flex min-h-0 flex-1 flex-col overflow-y-auto pt-5 pb-[calc(6.5rem+env(safe-area-inset-bottom))]">
        {sorted.length === 0 ? (
          <div className="flex flex-1 flex-col items-center justify-center gap-3 px-5 text-center">
            <CalendarDays className="size-7 text-[color-mix(in_oklch,var(--muted-foreground),var(--background)_35%)]" />
            <p className="max-w-[24rem] text-base text-muted-foreground">
              No workouts yet. Create one, choose muscles, and add your first
              exercises.
            </p>
          </div>
        ) : (
          <>
            <WorkoutHeatmap onSelectWorkout={onSelect} workouts={workouts} />
            <ul className="mt-5 space-y-3">
              {sorted.map((workout) => {
                const isOpen = openRowId === workout.id
                const isRunning = session?.workoutId === workout.id
                const targetMuscles = musclesForExerciseIds(workout.exerciseIds)
                return (
                  <li key={workout.id}>
                    <SwipeableRow
                      actionInset={20}
                      revealWidth={148}
                      action={
                        <div className="flex items-center gap-2">
                          <button
                            aria-label={`Duplicate ${formatDateShort(workout.date)} workout`}
                            className="grid size-14 shrink-0 place-items-center rounded-full bg-secondary text-secondary-foreground shadow-lg shadow-black/20 transition-transform duration-150 active:scale-90"
                            data-haptics="off"
                            onClick={() => {
                              duplicateWorkout(workout.id)
                              triggerHaptic("success")
                              setOpenRowId(null)
                            }}
                            type="button"
                          >
                            <Copy className="size-5" />
                          </button>
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
                        </div>
                      }
                      isOpen={isOpen}
                      onOpenChange={(open) => {
                        if (open) triggerHaptic("selection")
                        setOpenRowId(open ? workout.id : null)
                      }}
                    >
                      <button
                        className={`mx-5 flex w-[calc(100%-2.5rem)] items-center justify-between gap-3 rounded-2xl border p-4 text-left transition-colors duration-150 active:bg-muted ${
                          isRunning
                            ? "border-primary/55 bg-[color-mix(in_oklch,var(--card),var(--primary)_7%)]"
                            : "border-border bg-card"
                        }`}
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
                          {isRunning && session ? (
                            <p className="mt-0.5 flex items-center gap-1.5 text-sm font-semibold text-primary tabular-nums">
                              <span
                                aria-hidden="true"
                                className="size-1.5 animate-pulse rounded-full bg-primary"
                              />
                              {session.runningSince === null
                                ? "Paused"
                                : "In progress"}{" "}
                              · {formatDuration(elapsed)} ·{" "}
                              {sessionProgress(session).completed}/
                              {sessionProgress(session).total}
                            </p>
                          ) : (
                            <p className="mt-0.5 text-sm font-medium text-muted-foreground">
                              {workout.exerciseIds.length} exercise
                              {workout.exerciseIds.length === 1 ? "" : "s"}
                            </p>
                          )}
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
          </>
        )}
      </div>

      <footer className="bottom-controls-scrim absolute inset-x-0 bottom-0 z-20 px-5 pt-4 pb-[calc(1rem+env(safe-area-inset-bottom))]">
        <Button
          className="h-[3.25rem] w-full rounded-[26px] text-base font-semibold shadow-xl shadow-black/25"
          onClick={onCreate}
        >
          Add workout
        </Button>
      </footer>

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
