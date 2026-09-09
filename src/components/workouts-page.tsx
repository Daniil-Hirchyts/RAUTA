import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from "react"
import {
  ChevronDown,
  ChevronUp,
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
import { WorkoutCompanion } from "@/components/workout-companion"
import { WorkoutStreak } from "@/components/workout-streak"
import { useElapsedMs } from "@/hooks/use-elapsed-ms"
import { formatDuration, sessionProgress } from "@/lib/active-workout"
import { isObsoleteProjection } from "@/lib/training-adaptation"
import {
  formatDateShort,
  formatDayOfMonth,
  formatMonthShort,
  formatWeekdayShort,
  toISODate,
} from "@/lib/date"
import { duplicateWorkoutWithEngine } from "@/lib/engine-workout"
import { musclesForExerciseIds } from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { MUSCLE_LABELS } from "@/lib/muscles"
import { countLabel } from "@/lib/text"
import {
  activePlannedSessions,
  ensurePlannedWorkout,
  isPlannedSessionRecorded,
} from "@/lib/training-plan"
import { cn } from "@/lib/utils"
import { isCompletedWorkout, isPastWorkout } from "@/lib/workout-stats"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts, type Workout } from "@/store/use-workouts"
import type { MuscleId } from "@/types"

type ActiveSession = ReturnType<typeof useActiveWorkout.getState>["session"]

/** A workout card carries a body map and a rail of figures; a screenful is
 *  roughly this many. Longer histories grow a page at a time from the button
 *  below. */
const WORKOUT_PAGE_SIZE = 6

/** How many muscles a card names before it stops listing and starts counting.
 *  The body map beside the line already carries the rest. */
const NAMED_MUSCLES = 3

/** The muscles a workout trains, in a card's words. */
function muscleSummary(muscles: MuscleId[]) {
  if (muscles.length === 0) return "No target muscles"
  const named = muscles.slice(0, NAMED_MUSCLES).map((id) => MUSCLE_LABELS[id])
  const rest = muscles.length - named.length
  return rest > 0 ? `${named.join(" · ")} +${rest}` : named.join(" · ")
}

type TabDef = { label: string; count: number }

/**
 * Sliding-pill tab bar.
 *
 * The pill's position (translateX + width) is measured from the active
 * button's layout, then written as inline styles so CSS transitions can
 * tween between positions.  First paint and resize snap without animation.
 */
function SlidingTabs({
  activeIndex,
  onChange,
  tabs,
}: {
  activeIndex: number
  onChange: (index: number) => void
  tabs: TabDef[]
}) {
  const barRef = useRef<HTMLDivElement>(null)
  const pillRef = useRef<HTMLSpanElement>(null)

  const syncPill = useCallback(
    (animate: boolean) => {
      const bar = barRef.current
      const pill = pillRef.current
      if (!bar || !pill) return
      const btn = bar.querySelectorAll<HTMLButtonElement>('[role="tab"]')[
        activeIndex
      ]
      if (!btn) return

      if (!animate) {
        pill.style.transition = "none"
        // Force reflow so the "none" is flushed before we restore
        void pill.offsetWidth
      }
      pill.style.transform = `translateX(${btn.offsetLeft}px)`
      pill.style.width = `${btn.offsetWidth}px`
      if (!animate) {
        // Restore after one frame
        requestAnimationFrame(() => {
          pill.style.transition = ""
        })
      }
    },
    [activeIndex]
  )

  // Snap on first paint and whenever the active tab changes
  useLayoutEffect(() => {
    syncPill(true)
  }, [syncPill])

  // Snap (no animation) on first mount
  useEffect(() => {
    syncPill(false)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Snap (no animation) on resize
  useEffect(() => {
    const onResize = () => syncPill(false)
    window.addEventListener("resize", onResize)
    return () => window.removeEventListener("resize", onResize)
  }, [syncPill])

  return (
    <div className="t-tabs" ref={barRef} role="tablist">
      <span className="t-tabs-pill" ref={pillRef} aria-hidden="true" />
      {tabs.map((tab, i) => (
        <button
          aria-selected={i === activeIndex}
          className="t-tab"
          key={tab.label}
          onClick={() => onChange(i)}
          role="tab"
          type="button"
        >
          {tab.label}
          <span
            className={cn(
              "ml-1.5 rounded-full px-1.5 py-0.5 text-[10px] font-bold tabular-nums transition-colors",
              i === activeIndex
                ? "bg-black/15 text-primary-foreground"
                : "bg-muted/60 text-muted-foreground"
            )}
          >
            {tab.count}
          </span>
        </button>
      ))}
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

/**
 * The date a card is about, stamped rather than spelled out.
 *
 * Weekday over day-of-month is how a training week is actually read, and a
 * column of stamps down the list lines the figures up the way the week strip
 * at the top of the page does. History adds the month, because it outruns the
 * current one; a plan never does. The stamp is decoration for a screen
 * reader — the card's own label says the whole date.
 */
function DayStamp({
  date,
  tone,
  withMonth = false,
}: {
  date: string
  tone: "live" | "past" | "plan" | "today"
  withMonth?: boolean
}) {
  return (
    <div
      aria-hidden="true"
      className={cn(
        "flex w-[3.25rem] shrink-0 flex-col items-center justify-center gap-0.5 rounded-2xl border px-1 py-2",
        tone === "live" &&
          "border-primary/70 bg-primary-gradient text-primary-foreground",
        tone === "today" && "border-primary/45 bg-primary/15 text-primary",
        tone === "plan" && "border-border bg-muted/45 text-foreground",
        tone === "past" &&
          "border-transparent bg-muted/35 text-muted-foreground"
      )}
    >
      <span className="text-[9px] leading-none font-bold tracking-[0.14em] uppercase opacity-75">
        {formatWeekdayShort(date)}
      </span>
      <span className="font-readout text-[21px] leading-none font-black">
        {formatDayOfMonth(date)}
      </span>
      {withMonth ? (
        <span className="text-[9px] leading-none font-bold tracking-[0.14em] uppercase opacity-60">
          {formatMonthShort(date)}
        </span>
      ) : null}
    </div>
  )
}

/** One instrument on a finished workout's rail: the figure, then what it is. */
function Stat({
  caption,
  children,
  className,
}: {
  caption: string
  children: ReactNode
  className?: string
}) {
  return (
    <div className="min-w-0">
      <p
        className={cn(
          "truncate font-readout text-[15px] leading-none font-black tracking-tight tabular-nums",
          className
        )}
      >
        {children}
      </p>
      <p className="mt-1 truncate text-[9px] font-bold tracking-[0.1em] text-muted-foreground uppercase">
        {caption}
      </p>
    </div>
  )
}

/** How much of a workout was got through, as a bar. The track is always
 *  drawn, so a part-finished session reads as partly done rather than broken. */
function ProgressRail({
  className,
  completed,
  total,
}: {
  className?: string
  completed: number
  total: number
}) {
  const share = total > 0 ? Math.min(1, Math.max(0, completed / total)) : 0
  return (
    <div aria-hidden="true" className={cn("workout-progress", className)}>
      <i style={{ width: `${Math.round(share * 100)}%` }} />
    </div>
  )
}

/** What a finished day amounts to: the three figures every session leaves
 *  behind, over the share of it that was actually got through. */
function CompletedRecord({ workout }: { workout: Workout }) {
  const completion = workout.completion!
  const done = completion.completedExerciseIds.length

  return (
    <>
      <div className="grid grid-cols-3 gap-2">
        <Stat caption="Duration">{formatDuration(completion.durationMs)}</Stat>
        <Stat caption="Energy" className="text-gold">
          {completion.activeCalories} kcal
        </Stat>
        <Stat caption="Completed" className="text-success">
          {done}/{workout.exerciseIds.length}
        </Stat>
      </div>
      <ProgressRail
        className="mt-2.5"
        completed={done}
        total={workout.exerciseIds.length}
      />
    </>
  )
}

/** What a card says about itself out loud, where the stamp and the figures
 *  say it in shorthand. */
function workoutLabel(workout: Workout, isRunning: boolean) {
  const date = formatDateShort(workout.date)
  const exercises = countLabel(workout.exerciseIds.length, "exercise")
  if (isRunning) return `${date} workout, in progress`
  const completion = workout.completion
  if (completion) {
    return `${date} workout, ${formatDuration(completion.durationMs)}, ${
      completion.activeCalories
    } kcal, ${completion.completedExerciseIds.length} of ${
      workout.exerciseIds.length
    } exercises completed`
  }
  if (isPastWorkout(workout)) return `${date} workout, overdue`
  return `${date} workout, ${exercises}`
}

function WorkoutCard({
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
  const completed = isPast && workout.completion !== null
  const progress = isRunning && session ? sessionProgress(session) : null

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
      <button
        aria-label={workoutLabel(workout, isRunning)}
        className={cn(
          "workout-card interactive-spring mx-(--app-content-inset) flex w-[calc(100%_-_2_*_var(--app-content-inset))] items-center gap-3 rounded-3xl p-3 text-left",
          isRunning && "content-glow content-glow--subtle"
        )}
        data-haptics="off"
        data-state={
          isRunning
            ? "live"
            : completed
              ? "past"
              : isPast
                ? "unfinished"
                : "plan"
        }
        onClick={() => {
          if (isOpen) {
            onOpenChange(false)
            return
          }
          onSelect()
        }}
        type="button"
      >
        <DayStamp
          date={workout.date}
          tone={isRunning ? "live" : isPast ? "past" : "plan"}
          withMonth={isPast}
        />
        <div className="min-w-0 flex-1">
          {isRunning && progress ? (
            <>
              <p className="flex items-center gap-1.5 text-[13px] font-bold text-primary tabular-nums">
                <span
                  aria-hidden="true"
                  className="size-1.5 animate-pulse rounded-full bg-primary"
                />
                {session?.runningSince === null ? "Paused" : "In progress"} ·{" "}
                {formatDuration(elapsed)} · {progress.completed}/
                {progress.total}
              </p>
              <ProgressRail
                className="mt-2.5"
                completed={progress.completed}
                total={progress.total}
              />
            </>
          ) : completed ? (
            <CompletedRecord workout={workout} />
          ) : isPast ? (
            <p className="text-[13px] font-semibold text-muted-foreground">
              Not completed ·{" "}
              {countLabel(workout.exerciseIds.length, "exercise")}
            </p>
          ) : (
            <>
              <p className="text-[15px] font-bold tracking-[-0.01em]">
                {workout.planned ? `${workout.name} · ` : ""}
                {countLabel(workout.exerciseIds.length, "exercise")}
              </p>
              <p className="mt-1 truncate text-[11px] font-medium text-muted-foreground">
                {muscleSummary(targetMuscles)}
              </p>
            </>
          )}
        </div>
        <BodyPreview
          className={cn("h-12 w-[4.25rem] shrink-0", isPast && "opacity-70")}
          selectedMuscles={targetMuscles}
        />
      </button>
    </SwipeableRow>
  )
}

export function WorkoutsPage({
  onCreate,
  onCreatePlan,
  onDelete,
  onSelect,
  onSettings,
}: {
  onCreate: () => void
  onCreatePlan: (sourceProgramId?: string) => void
  onDelete: (workoutId: string) => void
  onSelect: (workout: Workout) => void
  onSettings: () => void
}) {
  const scrollRef = useRef<HTMLDivElement>(null)
  const workouts = useWorkouts((state) => state.workouts)
  const trainingData = useTrainingRecords((state) => state.data)
  const [openRowId, setOpenRowId] = useState<string | null>(null)
  const [pendingDeleteId, setPendingDeleteId] = useState<string | null>(null)
  const [upcomingLimit, setUpcomingLimit] = useState(WORKOUT_PAGE_SIZE)
  const [pastLimit, setPastLimit] = useState(WORKOUT_PAGE_SIZE)
  const [activeTab, setActiveTab] = useState(0)

  const session = useActiveWorkout((state) => state.session)
  const elapsed = useElapsedMs(session)
  const { completed, past, upcoming } = useMemo(() => {
    const pastWorkouts: Workout[] = []
    const upcomingWorkouts: Workout[] = []
    const missing = activePlannedSessions(trainingData)
      .filter(
        (view) =>
          !isPlannedSessionRecorded(view.sessionId, trainingData) &&
          !workouts.some(
            (workout) => workout.planned?.sessionId === view.sessionId
          )
      )
      .map((view) => ({
        id: `planned-${view.sessionId}`,
        name: view.title,
        date: view.date,
        exerciseIds: view.exerciseIds,
        completion: null,
        createdAt: "",
        updatedAt: "",
        planned: { programId: view.programId, sessionId: view.sessionId },
      }))
    for (const workout of [...workouts, ...missing]) {
      if (isObsoleteProjection(workout, trainingData)) continue
      const running = session?.workoutId === workout.id
      if (
        !running &&
        (workout.completion ||
          (workout.planned &&
            isPlannedSessionRecorded(workout.planned.sessionId, trainingData)))
      )
        pastWorkouts.push(workout)
      else upcomingWorkouts.push(workout)
    }
    upcomingWorkouts.sort((left, right) => left.date.localeCompare(right.date))
    pastWorkouts.sort((left, right) => right.date.localeCompare(left.date))
    return {
      completed: pastWorkouts.filter(isCompletedWorkout),
      past: pastWorkouts,
      upcoming: upcomingWorkouts,
    }
  }, [session?.workoutId, trainingData, workouts])

  const openWorkout = (workout: Workout) => {
    if (
      workout.planned &&
      !useWorkouts.getState().workouts.some((item) => item.id === workout.id)
    ) {
      const view = activePlannedSessions(trainingData).find(
        (item) => item.sessionId === workout.planned?.sessionId
      )
      if (!view) return
      const id = ensurePlannedWorkout(view)
      onSelect(useWorkouts.getState().workouts.find((item) => item.id === id)!)
    } else onSelect(workout)
  }

  const copyWorkout = (workout: Workout) => {
    duplicateWorkoutWithEngine(workout.id, toISODate(new Date()))
    triggerHaptic("success")
    setOpenRowId(null)
  }

  const renderCards = (items: Workout[], arePast: boolean) => (
    <ul className="space-y-2.5">
      {items.map((workout) => (
        <li className="relative" key={workout.id}>
          <WorkoutCard
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
            onSelect={() => openWorkout(workout)}
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

        {/* The list ends well above the surface floor: RAUTA's dock stands
            there, and the last card has to be able to clear it. */}
        <div
          className="app-scroll-region flex min-h-0 flex-1 flex-col overflow-y-auto pt-5 pb-36"
          ref={scrollRef}
          tabIndex={-1}
        >
          <div>
            <WorkoutStreak workouts={completed} />

            <div className="mx-(--app-content-inset) mt-5">
              <SlidingTabs
                activeIndex={activeTab}
                onChange={setActiveTab}
                tabs={[
                  { label: "Next", count: upcoming.length },
                  { label: "Past", count: past.length },
                ]}
              />
            </div>

            <div className="mt-4">
            {activeTab === 0 ? (
              upcoming.length > 0 ? (
                <section aria-label="Next workouts">
                  {renderCards(upcoming.slice(0, upcomingLimit), false)}
                  <SectionFooter
                    onLess={() => setUpcomingLimit(WORKOUT_PAGE_SIZE)}
                    onMore={() =>
                      setUpcomingLimit((limit) => limit + WORKOUT_PAGE_SIZE)
                    }
                    remaining={Math.max(0, upcoming.length - upcomingLimit)}
                    showLess={upcomingLimit > WORKOUT_PAGE_SIZE}
                  />
                </section>
              ) : (
                <p className="mx-(--app-content-inset) text-center text-[13px] text-muted-foreground">
                  No upcoming workouts
                </p>
              )
            ) : past.length > 0 ? (
              <section aria-label="Past workouts">
                {renderCards(past.slice(0, pastLimit), true)}
                <SectionFooter
                  onLess={() => setPastLimit(WORKOUT_PAGE_SIZE)}
                  onMore={() =>
                    setPastLimit((limit) => limit + WORKOUT_PAGE_SIZE)
                  }
                  remaining={Math.max(0, past.length - pastLimit)}
                  showLess={pastLimit > WORKOUT_PAGE_SIZE}
                />
              </section>
            ) : (
              <p className="mx-(--app-content-inset) text-center text-[13px] text-muted-foreground">
                No past workouts yet
              </p>
            )}
            </div>
          </div>
        </div>

        {/* RAUTA holds the floor of the page rather than the head of the
            list: it is the one thing here that is always in the same place,
            so it can be reached without scrolling back for it. */}
        <div className="app-surface-bottom-dock workouts-companion-dock">
          <WorkoutCompanion
            onCreate={onCreate}
            onCreatePlan={onCreatePlan}
            onSettings={onSettings}
            onResume={
              session && workouts.some((w) => w.id === session.workoutId)
                ? () =>
                    onSelect(workouts.find((w) => w.id === session.workoutId)!)
                : undefined
            }
          />
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
