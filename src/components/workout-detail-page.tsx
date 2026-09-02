import { useEffect, useRef, useState } from "react"
import {
  Activity,
  Check,
  CheckCircle2,
  ChevronLeft,
  Clock3,
  Plus,
  Share,
  Trash2,
  X,
} from "lucide-react"

import { ActiveWorkoutHero } from "@/components/active-workout-hero"
import { ActiveWorkoutTimer } from "@/components/active-workout-timer"
import {
  AppControls,
  AppHeaderButton,
  AppScreen,
  AppShellHeader,
  AppSurface,
} from "@/components/app-shell"
import { DeleteWorkoutConfirmation } from "@/components/delete-workout-confirmation"
import { EndWorkoutConfirmation } from "@/components/end-workout-confirmation"
import { ExerciseSwapperDrawer } from "@/components/exercise-swapper-drawer"
import { FinishWorkoutConfirmation } from "@/components/finish-workout-confirmation"
import { SortableExerciseList } from "@/components/sortable-exercise-list"
import { Button } from "@/components/ui/button"
import { MatrixLoader } from "@/components/ui/matrix-loader"
import { WorkoutCountdown } from "@/components/workout-countdown"
import { WorkoutDateDrawer } from "@/components/workout-date-drawer"
import {
  currentExercise,
  exerciseStatus,
  formatDuration,
  nextPendingExerciseId,
} from "@/lib/active-workout"
import { formatDateLong } from "@/lib/date"
import { triggerHaptic } from "@/lib/haptics"
import { cn } from "@/lib/utils"
import { shareWorkout } from "@/lib/workout-sharing"
import { isPastWorkout } from "@/lib/workout-stats"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useWorkouts } from "@/store/use-workouts"
import type { ExerciseSummary } from "@/types"

export function WorkoutDetailPage({
  onAddExercise,
  onBack,
  onCopied,
  onDeleted,
  onOpenExercise,
  workoutId,
}: {
  onAddExercise: () => void
  onBack: () => void
  onCopied?: (workoutId: string) => void
  onDeleted: () => void
  onOpenExercise: (exercise: ExerciseSummary) => void
  workoutId: string
}) {
  const scrollRef = useRef<HTMLDivElement>(null)
  const workout = useWorkouts((state) =>
    state.workouts.find((item) => item.id === workoutId)
  )
  const updateWorkout = useWorkouts((state) => state.updateWorkout)
  const deleteWorkout = useWorkouts((state) => state.deleteWorkout)
  const duplicateWorkout = useWorkouts((state) => state.duplicateWorkout)

  const runningSession = useActiveWorkout((state) => state.session)
  const startWorkout = useActiveWorkout((state) => state.start)
  const finishWorkout = useActiveWorkout((state) => state.finish)
  const cancelWorkout = useActiveWorkout((state) => state.cancel)
  const pauseWorkout = useActiveWorkout((state) => state.pause)
  const resumeWorkout = useActiveWorkout((state) => state.resume)
  const completeCurrent = useActiveWorkout((state) => state.completeCurrent)
  const setCurrentExercise = useActiveWorkout(
    (state) => state.setCurrentExercise
  )
  const toggleComplete = useActiveWorkout((state) => state.toggleComplete)

  // A session belongs to exactly one workout: another workout's run must not
  // turn this page into a checklist.
  const session =
    runningSession?.workoutId === workoutId ? runningSession : null

  const [countingDown, setCountingDown] = useState(false)
  const [dateOpen, setDateOpen] = useState(false)
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [discardOpen, setDiscardOpen] = useState(false)
  const [finishOpen, setFinishOpen] = useState(false)
  const [swapExercise, setSwapExercise] = useState<ExerciseSummary | null>(null)
  const [shareStatus, setShareStatus] = useState<"idle" | "sharing" | "copied">(
    "idle"
  )

  useEffect(() => {
    if (!workout) onBack()
  }, [onBack, workout])

  if (!workout) return null

  const isPast = !session && isPastWorkout(workout)
  const completion = workout.completion

  // A running session mirrors the saved workout through the store, so an edit
  // made here — or from the find-an-exercise flow — reaches it either way.
  const setExerciseIds = (exerciseIds: string[]) => {
    updateWorkout(workout.id, { exerciseIds })
  }

  const exercise = session ? currentExercise(session) : null
  const skipTarget =
    session && exercise ? nextPendingExerciseId(session, exercise.id) : null

  const shareButton = (
    <AppHeaderButton
      aria-label={shareStatus === "copied" ? "Workout copied" : "Share workout"}
      disabled={shareStatus === "sharing"}
      onClick={async () => {
        setShareStatus("sharing")
        try {
          const result = await shareWorkout(workout)
          triggerHaptic("success")
          if (result === "copied") {
            setShareStatus("copied")
            window.setTimeout(() => setShareStatus("idle"), 1800)
          } else {
            setShareStatus("idle")
          }
        } catch (error) {
          const message = String(error).toLowerCase()
          if (!message.includes("cancel") && !message.includes("abort")) {
            triggerHaptic("warning")
          }
          setShareStatus("idle")
        }
      }}
    >
      {shareStatus === "sharing" ? (
        <MatrixLoader label="Sharing workout" rounded variant="orbit" />
      ) : shareStatus === "copied" ? (
        <Check />
      ) : (
        <Share className="size-5" />
      )}
    </AppHeaderButton>
  )

  return (
    <AppScreen bottomControls>
      <AppSurface>
        <AppShellHeader
          left={
            <AppHeaderButton aria-label="Back to workouts" onClick={onBack}>
              <ChevronLeft />
            </AppHeaderButton>
          }
          right={shareButton}
          scrollRef={scrollRef}
          title={
            isPast ? (
              formatDateLong(workout.date)
            ) : (
              <button
                aria-label={`Change date, currently ${formatDateLong(workout.date)}`}
                className="max-w-full truncate text-center"
                onClick={() => {
                  triggerHaptic("light")
                  setDateOpen(true)
                }}
                type="button"
              >
                {formatDateLong(workout.date)}
              </button>
            )
          }
        />

        <div
          className={cn(
            "app-scroll-region min-h-0 flex-1 space-y-5 overflow-y-auto pt-5",
            session ? "pb-28" : "pb-6"
          )}
          ref={scrollRef}
          tabIndex={-1}
        >
          {isPast ? (
            <section
              aria-label="Workout stats"
              className="mx-4 grid grid-cols-3 gap-2 rounded-3xl border border-border bg-card/70 p-3"
            >
              <div className="rounded-2xl bg-muted/45 p-3 text-center">
                <Clock3 className="mx-auto size-4 text-primary" />
                <p className="mt-1.5 text-base font-black tabular-nums">
                  {completion ? formatDuration(completion.durationMs) : "—"}
                </p>
                <p className="text-[11px] font-semibold text-muted-foreground">
                  Duration
                </p>
              </div>
              <div className="rounded-2xl bg-muted/45 p-3 text-center">
                <Activity className="mx-auto size-4 text-primary" />
                <p className="mt-1.5 text-base font-black tabular-nums">
                  {completion ? completion.activeCalories : "—"}
                </p>
                <p className="text-[11px] font-semibold text-muted-foreground">
                  kcal
                </p>
              </div>
              <div className="rounded-2xl bg-muted/45 p-3 text-center">
                <CheckCircle2 className="mx-auto size-4 text-primary" />
                <p className="mt-1.5 text-base font-black tabular-nums">
                  {completion
                    ? `${completion.completedExerciseIds.length}/${workout.exerciseIds.length}`
                    : "—"}
                </p>
                <p className="text-[11px] font-semibold text-muted-foreground">
                  Completed
                </p>
              </div>
            </section>
          ) : null}
          {workout.exerciseIds.length === 0 ? (
            <div className="flex min-h-[18rem] flex-col items-center justify-center gap-3 px-8 text-center">
              <p className="text-base text-muted-foreground">
                This workout is empty. Add an exercise to start building it.
              </p>
            </div>
          ) : (
            <>
              {session && exercise && (
                <ActiveWorkoutHero
                  exercise={exercise}
                  onComplete={completeCurrent}
                  onOpenExercise={onOpenExercise}
                  onSkip={
                    skipTarget
                      ? () => setCurrentExercise(skipTarget)
                      : undefined
                  }
                />
              )}

              <SortableExerciseList
                exerciseIds={workout.exerciseIds}
                onFindAlternative={
                  isPast
                    ? undefined
                    : (candidate) => {
                        triggerHaptic("light")
                        setSwapExercise(candidate)
                      }
                }
                onOpenExercise={onOpenExercise}
                onRemove={
                  isPast
                    ? undefined
                    : (id) => {
                        triggerHaptic("warning")
                        setExerciseIds(
                          workout.exerciseIds.filter(
                            (exerciseId) => exerciseId !== id
                          )
                        )
                      }
                }
                onReorder={isPast ? undefined : setExerciseIds}
                onToggleComplete={
                  session
                    ? (id) => {
                        triggerHaptic("selection")
                        toggleComplete(id)
                      }
                    : undefined
                }
                statusOf={
                  session ? (id) => exerciseStatus(session, id) : undefined
                }
              />
            </>
          )}
        </div>

        {session ? (
          <div className="app-surface-bottom-dock active-workout-dock">
            <ActiveWorkoutTimer
              onPause={pauseWorkout}
              onResume={resumeWorkout}
              session={session}
            />
          </div>
        ) : null}
      </AppSurface>

      <AppControls>
        {session ? (
          <div className="flex items-center gap-2.5">
            <Button
              aria-label="Discard session"
              onClick={() => {
                triggerHaptic("warning")
                setDiscardOpen(true)
              }}
              size="icon-cta"
              variant="secondary"
            >
              <X />
            </Button>
            <Button
              aria-label="Add exercise"
              onClick={onAddExercise}
              size="icon-cta"
              variant="secondary"
            >
              <Plus className="size-5" />
            </Button>
            <Button
              size="cta"
              className="flex-1"
              onClick={() => {
                triggerHaptic("medium")
                setFinishOpen(true)
              }}
            >
              Finish workout
            </Button>
          </div>
        ) : isPast ? (
          <div className="flex items-center gap-2.5">
            <Button
              aria-label="Delete workout"
              onClick={() => {
                triggerHaptic("warning")
                setDeleteOpen(true)
              }}
              size="icon-cta"
              variant="destructive"
            >
              <Trash2 />
            </Button>
            <Button
              size="cta"
              className="flex-1"
              onClick={() => {
                const copiedId = duplicateWorkout(workout.id)
                if (!copiedId) return
                triggerHaptic("success")
                onCopied?.(copiedId)
              }}
            >
              Copy to today
            </Button>
          </div>
        ) : (
          <div className="flex items-center gap-2.5">
            <Button
              aria-label="Delete workout"
              onClick={() => {
                triggerHaptic("warning")
                setDeleteOpen(true)
              }}
              size="icon-cta"
              variant="destructive"
            >
              <Trash2 />
            </Button>
            {workout.exerciseIds.length === 0 ? (
              <>
                <Button size="cta" className="flex-1" onClick={onAddExercise}>
                  <Plus className="size-5" />
                  Add exercise
                </Button>
              </>
            ) : (
              <>
                <Button
                  aria-label="Add exercise"
                  onClick={onAddExercise}
                  size="icon-cta"
                  variant="secondary"
                >
                  <Plus className="size-5" />
                </Button>
                <Button
                  size="cta"
                  className="flex-1"
                  onClick={() => {
                    triggerHaptic("heavy")
                    setCountingDown(true)
                  }}
                >
                  Start workout
                </Button>
              </>
            )}
          </div>
        )}
      </AppControls>

      {countingDown && (
        <WorkoutCountdown
          onCancel={() => setCountingDown(false)}
          onComplete={() => {
            setCountingDown(false)
            startWorkout(workout)
          }}
        />
      )}

      <WorkoutDateDrawer
        date={workout.date}
        onOpenChange={setDateOpen}
        onSelect={(date) => updateWorkout(workout.id, { date })}
        open={dateOpen}
      />

      <DeleteWorkoutConfirmation
        onConfirm={() => {
          deleteWorkout(workout.id)
          onDeleted()
        }}
        onOpenChange={setDeleteOpen}
        open={deleteOpen}
      />

      <EndWorkoutConfirmation
        onConfirm={cancelWorkout}
        onOpenChange={setDiscardOpen}
        open={discardOpen}
      />

      <FinishWorkoutConfirmation
        onConfirm={finishWorkout}
        onOpenChange={setFinishOpen}
        open={finishOpen}
      />

      <ExerciseSwapperDrawer
        excludedExerciseIds={workout.exerciseIds}
        exercise={swapExercise}
        onOpenChange={(open) => {
          if (!open) setSwapExercise(null)
        }}
        onSwap={(replacement) => {
          if (!swapExercise) return
          setExerciseIds(
            workout.exerciseIds.map((id) =>
              id === swapExercise.id ? replacement.id : id
            )
          )
          triggerHaptic("success")
          setSwapExercise(null)
        }}
        open={swapExercise !== null}
      />
    </AppScreen>
  )
}
