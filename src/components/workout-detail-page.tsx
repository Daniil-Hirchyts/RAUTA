import { useEffect, useState } from "react"
import {
  Activity,
  Check,
  CheckCircle2,
  ChevronLeft,
  Clock3,
  Copy,
  Flag,
  Play,
  Plus,
  Trash2,
  X,
} from "lucide-react"

import { ActiveWorkoutHero } from "@/components/active-workout-hero"
import { ActiveWorkoutTimer } from "@/components/active-workout-timer"
import { DeleteWorkoutConfirmation } from "@/components/delete-workout-confirmation"
import { EndWorkoutConfirmation } from "@/components/end-workout-confirmation"
import { ExerciseSwapperDrawer } from "@/components/exercise-swapper-drawer"
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
import { shareWorkout } from "@/lib/workout-sharing"
import { isPastWorkout } from "@/lib/workout-stats"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useWorkouts } from "@/store/use-workouts"
import type { ExerciseSummary } from "@/types"

function IosShareIcon() {
  return (
    <svg
      aria-hidden="true"
      fill="none"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2"
      viewBox="0 0 24 24"
    >
      <path d="M12 3v12" />
      <path d="m8 7 4-4 4 4" />
      <path d="M7 10H5.75A1.75 1.75 0 0 0 4 11.75v7.5C4 20.22 4.78 21 5.75 21h12.5c.97 0 1.75-.78 1.75-1.75v-7.5A1.75 1.75 0 0 0 18.25 10H17" />
    </svg>
  )
}

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
    <Button
      aria-label={shareStatus === "copied" ? "Workout copied" : "Share workout"}
      className="size-[3.25rem] rounded-[26px]"
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
      size="icon"
      variant="secondary"
    >
      {shareStatus === "sharing" ? (
        <MatrixLoader label="Sharing workout" rounded variant="orbit" />
      ) : shareStatus === "copied" ? (
        <Check />
      ) : (
        <IosShareIcon />
      )}
    </Button>
  )

  return (
    <div className="app-screen" data-bottom-controls="true">
      <div className="app-surface">
        <header className="app-shell-header shrink-0 px-5 pt-4 pb-4">
          <div className="flex items-center gap-3">
            <Button
              aria-label="Back to workouts"
              className="shrink-0 rounded-full"
              onClick={onBack}
              size="icon"
              variant="secondary"
            >
              <ChevronLeft />
            </Button>
            <div className="min-w-0">
              {isPast ? (
                <h1 className="truncate text-[26px] leading-none font-black tracking-[-0.03em]">
                  {formatDateLong(workout.date)}
                </h1>
              ) : (
                <button
                  aria-label={`Change date, currently ${formatDateLong(workout.date)}`}
                  className="min-w-0 text-left"
                  onClick={() => {
                    triggerHaptic("light")
                    setDateOpen(true)
                  }}
                  type="button"
                >
                  <h1 className="truncate text-[26px] leading-none font-black tracking-[-0.03em]">
                    {formatDateLong(workout.date)}
                  </h1>
                </button>
              )}
            </div>
          </div>
        </header>

        <div className="app-scroll-region min-h-0 flex-1 space-y-5 overflow-y-auto pt-5 pb-6">
          {isPast ? (
            <section
              aria-label="Workout stats"
              className="mx-4 grid grid-cols-3 gap-2 rounded-[22px] border border-border bg-card/70 p-3"
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
          {session && (
            <ActiveWorkoutTimer
              onPause={pauseWorkout}
              onResume={resumeWorkout}
              session={session}
            />
          )}

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
      </div>

      <footer className="bottom-controls-scrim absolute inset-x-0 bottom-0 z-20 px-5 pt-4 pb-[calc(1rem+env(safe-area-inset-bottom))]">
        {session ? (
          <div className="flex items-center gap-2.5">
            <Button
              aria-label="Discard session"
              className="size-[3.25rem] rounded-[26px]"
              onClick={() => {
                triggerHaptic("warning")
                setDiscardOpen(true)
              }}
              size="icon"
              variant="secondary"
            >
              <X />
            </Button>
            <Button
              aria-label="Add exercise"
              className="size-[3.25rem] rounded-[26px]"
              onClick={onAddExercise}
              size="icon"
              variant="secondary"
            >
              <Plus className="size-5" />
            </Button>
            {shareButton}
            <Button
              className="h-[3.25rem] flex-1 rounded-[26px] text-base font-semibold"
              onClick={() => {
                triggerHaptic("success")
                finishWorkout()
              }}
            >
              <Flag className="size-5" />
              Finish workout
            </Button>
          </div>
        ) : isPast ? (
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
            {shareButton}
            <Button
              className="h-[3.25rem] flex-1 rounded-[26px] text-base font-semibold"
              onClick={() => {
                const copiedId = duplicateWorkout(workout.id)
                if (!copiedId) return
                triggerHaptic("success")
                onCopied?.(copiedId)
              }}
            >
              <Copy className="size-5" />
              Copy to today
            </Button>
          </div>
        ) : (
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
            {workout.exerciseIds.length === 0 ? (
              <>
                {shareButton}
                <Button
                  className="h-[3.25rem] flex-1 rounded-[26px] text-base font-semibold"
                  onClick={onAddExercise}
                >
                  <Plus className="size-5" />
                  Add exercise
                </Button>
              </>
            ) : (
              <>
                <Button
                  aria-label="Add exercise"
                  className="size-[3.25rem] rounded-[26px]"
                  onClick={onAddExercise}
                  size="icon"
                  variant="secondary"
                >
                  <Plus className="size-5" />
                </Button>
                {shareButton}
                <Button
                  className="h-[3.25rem] flex-1 rounded-[26px] text-base font-semibold"
                  onClick={() => {
                    triggerHaptic("heavy")
                    setCountingDown(true)
                  }}
                >
                  <Play className="size-5" />
                  Start workout
                </Button>
              </>
            )}
          </div>
        )}
      </footer>

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
    </div>
  )
}
