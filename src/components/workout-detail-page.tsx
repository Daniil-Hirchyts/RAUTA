import { useEffect, useState } from "react"
import { Check, ChevronLeft, Flag, Play, Plus, Trash2, X } from "lucide-react"

import { ActiveWorkoutHero } from "@/components/active-workout-hero"
import { ActiveWorkoutTimer } from "@/components/active-workout-timer"
import { DeleteWorkoutConfirmation } from "@/components/delete-workout-confirmation"
import { EndWorkoutConfirmation } from "@/components/end-workout-confirmation"
import { ExerciseSwapperDrawer } from "@/components/exercise-swapper-drawer"
import { SortableExerciseList } from "@/components/sortable-exercise-list"
import { Button } from "@/components/ui/button"
import { MatrixLoader } from "@/components/ui/matrix-loader"
import {
  currentExercise,
  exerciseStatus,
  nextPendingExerciseId,
} from "@/lib/active-workout"
import { formatDateLong } from "@/lib/date"
import { triggerHaptic } from "@/lib/haptics"
import { shareWorkout } from "@/lib/workout-sharing"
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
  const syncExercises = useActiveWorkout((state) => state.syncExercises)

  // A session belongs to exactly one workout: another workout's run must not
  // turn this page into a checklist.
  const session =
    runningSession?.workoutId === workoutId ? runningSession : null

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

  const setExerciseIds = (exerciseIds: string[]) => {
    updateWorkout(workout.id, { exerciseIds })
    if (session) syncExercises(exerciseIds)
  }

  const exercise = session ? currentExercise(session) : null
  const skipTarget =
    session && exercise ? nextPendingExerciseId(session, exercise.id) : null

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
          <Button
            aria-label={
              shareStatus === "copied" ? "Workout copied" : "Share workout"
            }
            className="shrink-0 rounded-full"
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
        </div>
        <h1 className="text-[26px] font-black tracking-[-0.03em]">
          {formatDateLong(workout.date)}
        </h1>
        <p className="mt-1 text-sm font-medium text-muted-foreground">
          {workout.exerciseIds.length} exercise
          {workout.exerciseIds.length === 1 ? "" : "s"}
        </p>
      </header>

      <div className="min-h-0 flex-1 space-y-5 overflow-y-auto pt-5 pb-[calc(6.5rem+env(safe-area-inset-bottom))]">
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
                  skipTarget ? () => setCurrentExercise(skipTarget) : undefined
                }
              />
            )}

            <SortableExerciseList
              exerciseIds={workout.exerciseIds}
              onFindAlternative={(candidate) => {
                triggerHaptic("light")
                setSwapExercise(candidate)
              }}
              onOpenExercise={onOpenExercise}
              onRemove={(id) => {
                triggerHaptic("warning")
                setExerciseIds(
                  workout.exerciseIds.filter((exerciseId) => exerciseId !== id)
                )
              }}
              onReorder={setExerciseIds}
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
              <Button
                className="h-[3.25rem] flex-1 rounded-[26px] text-base font-semibold"
                onClick={onAddExercise}
              >
                <Plus className="size-5" />
                Add exercise
              </Button>
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
                <Button
                  className="h-[3.25rem] flex-1 rounded-[26px] text-base font-semibold"
                  onClick={() => {
                    triggerHaptic("heavy")
                    startWorkout(workout)
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
    </>
  )
}
