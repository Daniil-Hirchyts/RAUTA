import { useMemo, useRef, useState } from "react"
import {
  CalendarDays,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  ChevronUp,
  Clock3,
  Copy,
  Settings,
  Trash2,
} from "lucide-react"

import { AppControlMorph } from "@/components/app-morph"
import {
  AppControls,
  AppHeaderButton,
  AppScreen,
  AppShellHeader,
  AppSurface,
} from "@/components/app-shell"
import { BodyPreview } from "@/components/body-map"
import { ConfirmModal } from "@/components/confirm-modal"
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

/** A workout row is tall and carries a body map; a screenful is roughly this
 *  many. Longer histories grow a page at a time from the button below. */
const WORKOUT_PAGE_SIZE = 6

function SectionHeading({ count, title }: { count: number; title: string }) {
  return (
    <div className="mx-(--app-content-inset) mb-2.5 flex items-center justify-between">
      <h2 className="text-xs font-bold tracking-[0.15em] text-muted-foreground uppercase">
        {title}
      </h2>
      <span className="text-xs font-semibold text-muted-foreground tabular-nums">
        {count}
      </span>
    </div>
  )
}

function SectionFooter({
  onLess,
  onMore,
  remaining,
  showLess,
}: {
  onLess: () => void
  onMore: () => void
  remaining: number
  showLess: boolean
}) {
  if (remaining === 0 && !showLess) return null

  return (
    <div className="mx-(--app-content-inset) mt-3 flex gap-2">
      {remaining > 0 ? (
        <Button className="flex-1" onClick={onMore} variant="ghost">
          Load more
          <span className="text-muted-foreground tabular-nums">
            ({remaining})
          </span>
          <ChevronDown className="size-4" data-icon="inline-end" />
        </Button>
      ) : null}
      {showLess ? (
        <Button
          className={remaining > 0 ? "" : "flex-1"}
          onClick={onLess}
          variant="ghost"
        >
          Show less
          <ChevronUp className="size-4" data-icon="inline-end" />
        </Button>
      ) : null}
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
            className="interactive-spring grid size-14 shrink-0 place-items-center rounded-full border border-border bg-card text-primary shadow-lg shadow-black/20 active:bg-card/90 active:text-white"
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
        className={`mx-(--app-content-inset) flex w-[calc(100%_-_2_*_var(--app-content-inset))] items-center gap-2 rounded-3xl border p-1.5 transition-[border-color,background-color] duration-200 ${
          isRunning
            ? "border-primary/55 bg-[color-mix(in_oklch,var(--card),var(--primary)_7%)]"
            : "border-border bg-card"
        }`}
      >
        <button
          className="interactive-spring flex min-w-0 flex-1 items-center gap-3 rounded-2xl p-2 text-left active:bg-muted/80"
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
  onDelete,
  onSelect,
  onSettings,
}: {
  onCreate: () => void
  onDelete: (workoutId: string) => void
  onSelect: (workout: Workout) => void
  onSettings: () => void
}) {
  const scrollRef = useRef<HTMLDivElement>(null)
  const workouts = useWorkouts((state) => state.workouts)
  const duplicateWorkout = useWorkouts((state) => state.duplicateWorkout)
  const [openRowId, setOpenRowId] = useState<string | null>(null)
  const [pendingDeleteId, setPendingDeleteId] = useState<string | null>(null)
  const [upcomingLimit, setUpcomingLimit] = useState(WORKOUT_PAGE_SIZE)
  const [pastLimit, setPastLimit] = useState(WORKOUT_PAGE_SIZE)

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
              setPendingDeleteId(workout.id)
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
    <AppScreen bottomControls>
      <AppSurface>
        <AppShellHeader
          right={
            <AppHeaderButton aria-label="Settings" onClick={onSettings}>
              <Settings className="size-5" />
            </AppHeaderButton>
          }
          scrollRef={scrollRef}
          title="My workouts"
        />

        <div
          className="app-scroll-region flex min-h-0 flex-1 flex-col overflow-y-auto pt-5 pb-6"
          ref={scrollRef}
          tabIndex={-1}
        >
          <div className="space-y-7">
            {upcoming.length > 0 ? (
              <section aria-labelledby="upcoming-workouts-heading">
                <div id="upcoming-workouts-heading">
                  <SectionHeading
                    count={upcoming.length}
                    title="Next workouts"
                  />
                </div>
                {renderRows(upcoming.slice(0, upcomingLimit), false)}
                <SectionFooter
                  onLess={() => setUpcomingLimit(WORKOUT_PAGE_SIZE)}
                  onMore={() =>
                    setUpcomingLimit((limit) => limit + WORKOUT_PAGE_SIZE)
                  }
                  remaining={Math.max(0, upcoming.length - upcomingLimit)}
                  showLess={upcomingLimit > WORKOUT_PAGE_SIZE}
                />
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
                {renderRows(past.slice(0, pastLimit), true)}
                <SectionFooter
                  onLess={() => setPastLimit(WORKOUT_PAGE_SIZE)}
                  onMore={() =>
                    setPastLimit((limit) => limit + WORKOUT_PAGE_SIZE)
                  }
                  remaining={Math.max(0, past.length - pastLimit)}
                  showLess={pastLimit > WORKOUT_PAGE_SIZE}
                />
              </section>
            ) : null}

            {workouts.length === 0 ? (
              <div className="flex flex-col items-center gap-3 px-4 text-center">
                <CalendarDays className="size-7 text-[color-mix(in_oklch,var(--muted-foreground),var(--background)_35%)]" />
                <p className="max-w-[24rem] text-base text-muted-foreground">
                  No workouts yet. Start a new one, pick the muscles you want to
                  train, and it will fill with exercises you can do.
                </p>
              </div>
            ) : null}
          </div>
        </div>
      </AppSurface>

      <ConfirmModal
        kind={pendingDeleteId ? "delete-workout" : null}
        onCancel={() => setPendingDeleteId(null)}
        onConfirm={() => {
          if (pendingDeleteId) onDelete(pendingDeleteId)
          setPendingDeleteId(null)
          setOpenRowId(null)
        }}
      />

      <AppControls transitionKey="workouts:add">
        <AppControlMorph className="w-full" role="primary">
          <Button
            size="cta"
            className="w-full shadow-xl shadow-black/25"
            onClick={onCreate}
          >
            New workout
          </Button>
        </AppControlMorph>
      </AppControls>
    </AppScreen>
  )
}
