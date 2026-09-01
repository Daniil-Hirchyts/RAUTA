import { useMemo, useState } from "react"
import {
  CalendarDays,
  CheckCircle2,
  ChevronRight,
  Clock3,
  Copy,
  Settings,
  Trash2,
} from "lucide-react"

import { BodyPreview } from "@/components/body-map"
import { DeleteWorkoutConfirmation } from "@/components/delete-workout-confirmation"
import { SwipeableRow } from "@/components/swipeable-row"
import { Button } from "@/components/ui/button"
import { WorkoutHeatmap } from "@/components/workout-heatmap"
import { useElapsedMs } from "@/hooks/use-elapsed-ms"
import { formatDuration, sessionProgress } from "@/lib/active-workout"
import { formatDateShort } from "@/lib/date"
import { musclesForExerciseIds } from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { isCompletedWorkout, isPastWorkout } from "@/lib/workout-stats"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useWorkouts, type Workout } from "@/store/use-workouts"

type ActiveSession = ReturnType<typeof useActiveWorkout.getState>["session"]

function SectionHeading({ count, title }: { count: number; title: string }) {
  return (
    <div className="mx-5 mb-2.5 flex items-center justify-between">
      <h2 className="text-xs font-bold tracking-[0.15em] text-muted-foreground uppercase">
        {title}
      </h2>
      <span className="text-xs font-semibold text-muted-foreground tabular-nums">
        {count}
      </span>
    </div>
  )
}

function PastStats({ workout }: { workout: Workout }) {
  const completion = workout.completion
  if (!completion) {
    return (
      <p className="mt-1 text-sm font-medium text-muted-foreground">
        Not completed · {workout.exerciseIds.length} exercise
        {workout.exerciseIds.length === 1 ? "" : "s"}
      </p>
    )
  }

  return (
    <div className="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm font-semibold text-muted-foreground tabular-nums">
      <span className="flex items-center gap-1">
        <Clock3 className="size-3.5" />
        {formatDuration(completion.durationMs)}
      </span>
      <span>{completion.activeCalories} kcal</span>
      <span className="flex items-center gap-1">
        <CheckCircle2 className="size-3.5" />
        {completion.completedExerciseIds.length}/{workout.exerciseIds.length}
      </span>
    </div>
  )
}

function WorkoutRow({
  elapsed,
  isOpen,
  isPast,
  isRunning,
  onCopy,
  onDelete,
  onOpenChange,
  onSelect,
  session,
  workout,
}: {
  elapsed: number
  isOpen: boolean
  isPast: boolean
  isRunning: boolean
  onCopy: () => void
  onDelete: () => void
  onOpenChange: (open: boolean) => void
  onSelect: () => void
  session: ActiveSession
  workout: Workout
}) {
  const targetMuscles = musclesForExerciseIds(workout.exerciseIds)

  return (
    <SwipeableRow
      actionInset={20}
      revealWidth={148}
      action={
        <div className="flex items-center gap-2">
          <button
            aria-label={`Copy ${formatDateShort(workout.date)} workout to today`}
            className="interactive-spring grid size-14 shrink-0 place-items-center rounded-full bg-secondary text-secondary-foreground shadow-lg shadow-black/20"
            data-haptics="off"
            onClick={onCopy}
            type="button"
          >
            <Copy className="size-5" />
          </button>
          <button
            aria-label={`Delete ${formatDateShort(workout.date)} workout`}
            className="interactive-spring grid size-14 shrink-0 place-items-center rounded-full border border-primary bg-card text-primary shadow-lg shadow-black/20"
            data-haptics="off"
            onClick={onDelete}
            type="button"
          >
            <Trash2 className="size-5" />
          </button>
        </div>
      }
      isOpen={isOpen}
      onOpenChange={onOpenChange}
    >
      <div
        className={`mx-5 flex w-[calc(100%-2.5rem)] items-center gap-2 rounded-2xl border p-2 pr-2.5 transition-[border-color,background-color] duration-200 ${
          isRunning
            ? "border-primary/55 bg-[color-mix(in_oklch,var(--card),var(--primary)_7%)]"
            : "border-border bg-card"
        }`}
      >
        <button
          className="interactive-spring flex min-w-0 flex-1 items-center gap-3 rounded-xl p-2 text-left active:bg-muted/80"
          data-haptics="off"
          onClick={() => {
            if (isOpen) {
              onOpenChange(false)
              return
            }
            onSelect()
          }}
          type="button"
        >
          <div className="min-w-0 flex-1">
            <p className="text-lg font-bold tracking-[-0.01em]">
              {formatDateShort(workout.date)}
            </p>
            {isRunning && session ? (
              <p className="mt-0.5 flex items-center gap-1.5 text-sm font-semibold text-primary tabular-nums">
                <span
                  aria-hidden="true"
                  className="size-1.5 animate-pulse rounded-full bg-primary"
                />
                {session.runningSince === null ? "Paused" : "In progress"} ·{" "}
                {formatDuration(elapsed)} · {sessionProgress(session).completed}
                /{sessionProgress(session).total}
              </p>
            ) : isPast ? (
              <PastStats workout={workout} />
            ) : (
              <p className="mt-0.5 text-sm font-medium text-muted-foreground">
                {workout.exerciseIds.length} exercise
                {workout.exerciseIds.length === 1 ? "" : "s"}
              </p>
            )}
          </div>
          <BodyPreview
            className="h-14 w-20 shrink-0"
            selectedMuscles={targetMuscles}
          />
          <ChevronRight className="size-5 shrink-0 text-muted-foreground" />
        </button>
      </div>
    </SwipeableRow>
  )
}

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
  const [openRowId, setOpenRowId] = useState<string | null>(null)
  const [pendingDelete, setPendingDelete] = useState<Workout | null>(null)

  const session = useActiveWorkout((state) => state.session)
  const elapsed = useElapsedMs(session)
  const { completed, past, upcoming } = useMemo(() => {
    const pastWorkouts: Workout[] = []
    const upcomingWorkouts: Workout[] = []
    for (const workout of workouts) {
      const running = session?.workoutId === workout.id
      if (!running && isPastWorkout(workout)) pastWorkouts.push(workout)
      else upcomingWorkouts.push(workout)
    }
    upcomingWorkouts.sort((left, right) => left.date.localeCompare(right.date))
    pastWorkouts.sort((left, right) => right.date.localeCompare(left.date))
    return {
      completed: pastWorkouts.filter(isCompletedWorkout),
      past: pastWorkouts,
      upcoming: upcomingWorkouts,
    }
  }, [session?.workoutId, workouts])

  const copyWorkout = (workout: Workout) => {
    duplicateWorkout(workout.id)
    triggerHaptic("success")
    setOpenRowId(null)
  }

  const renderRows = (items: Workout[], arePast: boolean) => (
    <ul className="space-y-3">
      {items.map((workout) => (
        <li key={workout.id}>
          <WorkoutRow
            elapsed={elapsed}
            isOpen={openRowId === workout.id}
            isPast={arePast}
            isRunning={session?.workoutId === workout.id}
            onCopy={() => copyWorkout(workout)}
            onDelete={() => {
              triggerHaptic("warning")
              setOpenRowId(null)
              setPendingDelete(workout)
            }}
            onOpenChange={(open) => {
              if (open) triggerHaptic("selection")
              setOpenRowId(open ? workout.id : null)
            }}
            onSelect={() => onSelect(workout)}
            session={session}
            workout={workout}
          />
        </li>
      ))}
    </ul>
  )

  return (
    <div className="app-screen" data-bottom-controls="true">
      <div className="app-surface">
        <header className="app-shell-header shrink-0 px-5 pt-4 pb-4">
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

        <div className="app-scroll-region flex min-h-0 flex-1 flex-col overflow-y-auto pt-5 pb-6">
          <div className="space-y-7">
            {upcoming.length > 0 ? (
              <section aria-labelledby="upcoming-workouts-heading">
                <div id="upcoming-workouts-heading">
                  <SectionHeading
                    count={upcoming.length}
                    title="Next workouts"
                  />
                </div>
                {renderRows(upcoming, false)}
              </section>
            ) : null}

            {/* The year of training is the page's fixture, not a reward for
              having finished something: an empty grid is what a first
              workout is measured against. */}
            <WorkoutHeatmap onSelectWorkout={onSelect} workouts={completed} />

            {past.length > 0 ? (
              <section aria-labelledby="past-workouts-heading">
                <div id="past-workouts-heading">
                  <SectionHeading count={past.length} title="Past workouts" />
                </div>
                {renderRows(past, true)}
              </section>
            ) : null}

            {workouts.length === 0 ? (
              <div className="flex flex-col items-center gap-3 px-5 text-center">
                <CalendarDays className="size-7 text-[color-mix(in_oklch,var(--muted-foreground),var(--background)_35%)]" />
                <p className="max-w-[24rem] text-base text-muted-foreground">
                  No workouts yet. Create one, choose muscles, and add your
                  first exercises.
                </p>
              </div>
            ) : null}
          </div>
        </div>
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
    </div>
  )
}
