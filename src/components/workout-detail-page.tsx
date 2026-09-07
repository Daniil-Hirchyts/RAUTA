import { useEffect, useMemo, useRef, useState } from "react"
import {
  Activity,
  Check,
  CheckCircle2,
  ChevronLeft,
  Clock3,
  Flag,
  Layers,
  ListChecks,
  Plus,
  Share,
  Trash2,
  X,
} from "lucide-react"

import { ActiveWorkoutHero } from "@/components/active-workout-hero"
import { ActiveWorkoutTimer } from "@/components/active-workout-timer"
import { ExerciseSetLog } from "@/components/exercise-set-log"
import { ConfirmModal, type ConfirmationKind } from "@/components/confirm-modal"
import { AppControlMorph } from "@/components/app-morph"
import { usePageLayer } from "@/hooks/use-app-shell"
import {
  AppControlButton,
  AppControls,
  AppHeaderButton,
  AppScreen,
  AppShellHeader,
  AppSurface,
} from "@/components/app-shell"
import { MorphingActionSlot } from "@/components/morphing-action-slot"
import { SortableExerciseList } from "@/components/sortable-exercise-list"
import { Button } from "@/components/ui/button"
import { MatrixLoader } from "@/components/ui/matrix-loader"
import { WorkoutCountdown } from "@/components/workout-countdown"
import { WorkoutDatePicker } from "@/components/workout-date-picker"
import { WorkoutSessionCompanion } from "@/components/workout-session-companion"
import {
  currentExercise,
  exerciseStatus,
  formatDuration,
  nextPendingExerciseId,
} from "@/lib/active-workout"
import { formatDateLong } from "@/lib/date"
import { triggerHaptic } from "@/lib/haptics"
import {
  formatPrescription,
  plannedSessionView,
  type PlannedSessionView,
} from "@/lib/training-plan"
import { activePlannedCoverage } from "@/lib/training-session"
import { cn } from "@/lib/utils"
import { shareWorkout } from "@/lib/workout-sharing"
import { isPastWorkout } from "@/lib/workout-stats"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useTrainingRecords } from "@/store/use-training-records"
import { isStartablePlannedSession } from "@/training-persistence/program"
import { useWorkouts } from "@/store/use-workouts"
import type { ExerciseSummary } from "@/types"

/**
 * The prescription, in the row of the exercise it belongs to.
 *
 * It is only ever read out of the immutable program snapshot, so what a
 * planned session promises before it is performed and what its sets were
 * measured against afterwards are one and the same statement.
 */
function PlannedTargets({
  exerciseId,
  session,
}: {
  exerciseId: string
  session: PlannedSessionView
}) {
  const item = session.prescription.find(
    (entry) => entry.exerciseId === exerciseId
  )
  if (!item) return null
  return (
    <p className="mx-(--app-content-inset) mt-1.5 overflow-x-auto rounded-2xl border border-border bg-card/60 px-3 py-2 text-[13px] font-semibold whitespace-nowrap text-muted-foreground tabular-nums">
      <span className="mr-2 font-black tracking-[0.14em] text-primary uppercase">
        Plan
      </span>
      {formatPrescription(item)}
    </p>
  )
}

export function WorkoutDetailPage({
  onAddExercise,
  onBack,
  onCountdownChange,
  onCopied,
  onFindAlternative,
  onDelete,
  onDiscard,
  onFinish,
  onOpenExercise,
  workoutId,
}: {
  onAddExercise: () => void
  onBack: () => void
  onCountdownChange?: (countingDown: boolean) => void
  onCopied?: (workoutId: string) => void
  onFindAlternative: (exercise: ExerciseSummary) => void
  onDelete: () => void
  onDiscard: () => void
  onFinish: () => void
  onOpenExercise: (exercise: ExerciseSummary) => void
  workoutId: string
}) {
  const scrollRef = useRef<HTMLDivElement>(null)
  const [confirming, setConfirming] = useState<ConfirmationKind | null>(null)
  // At most one set editor is open at a time, and only where it was asked for.
  const [editingExerciseId, setEditingExerciseId] = useState<string | null>(
    null
  )
  const [actionIssue, setActionIssue] = useState<string | null>(null)
  const workout = useWorkouts((state) =>
    state.workouts.find((item) => item.id === workoutId)
  )
  const trainingData = useTrainingRecords((state) => state.data)
  const programId = workout?.planned?.programId
  const plannedSessionId = workout?.planned?.sessionId
  // Read back out of the stored program every time the program changes, and
  // never copied into state: the snapshot is the prescription, and this page
  // must not hold a second version of it that could drift.
  const plannedSession = useMemo(
    () =>
      programId && plannedSessionId
        ? plannedSessionView(programId, plannedSessionId, trainingData)
        : null,
    [plannedSessionId, programId, trainingData]
  )
  // Exactly the question the domain answers when the session is written, asked
  // one tap earlier so the confirmation can say what is about to be recorded.
  // The policy itself stays in `activePlannedCoverage`; this only reads it.
  const finishRecordsPartial = useMemo(
    () => activePlannedCoverage(trainingData)?.complete === false,
    [trainingData]
  )
  const updateWorkout = useWorkouts((state) => state.updateWorkout)
  const duplicateWorkout = useWorkouts((state) => state.duplicateWorkout)

  const runningSession = useActiveWorkout((state) => state.session)
  const startWorkout = useActiveWorkout((state) => state.start)
  const pauseWorkout = useActiveWorkout((state) => state.pause)
  const resumeWorkout = useActiveWorkout((state) => state.resume)
  const completeCurrent = useActiveWorkout((state) => state.completeCurrent)
  const setCurrentExercise = useActiveWorkout(
    (state) => state.setCurrentExercise
  )
  const syncExercises = useActiveWorkout((state) => state.syncExercises)
  const toggleComplete = useActiveWorkout((state) => state.toggleComplete)

  // A session belongs to exactly one workout: another workout's run must not
  // turn this page into a checklist.
  const session =
    runningSession?.workoutId === workoutId ? runningSession : null

  const page = usePageLayer()
  const [countingDown, setCountingDown] = useState(false)
  const [shareStatus, setShareStatus] = useState<"idle" | "sharing" | "copied">(
    "idle"
  )

  // Only while this page is the one on screen. A deleted workout also empties
  // this page on the frame it is dissolving away on, and a page on its way
  // out asking to go back would pop whatever had already replaced it.
  useEffect(() => {
    if (!workout && page.active) onBack()
  }, [onBack, page.active, workout])

  if (!workout) return null

  const isPlanned = Boolean(workout.planned)
  const plannedUnavailable =
    isPlanned &&
    (!plannedSession ||
      !isStartablePlannedSession(trainingData, programId!, plannedSessionId!))
  const isPast = !session && isPastWorkout(workout)
  const completion = workout.completion

  // A running session mirrors the saved workout through the store, so an edit
  // made here — or from the find-an-exercise flow — reaches it either way.
  const setExerciseIds = (exerciseIds: string[], movedExerciseId?: string) => {
    if (movedExerciseId) syncExercises(exerciseIds, movedExerciseId)
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
            // A planned session sits on the day the program gave it; moving it
            // would leave the plan and the workout describing different weeks.
            isPast || isPlanned ? (
              formatDateLong(workout.date)
            ) : (
              <WorkoutDatePicker
                ariaLabel={`Change date, currently ${formatDateLong(workout.date)}`}
                className="max-w-full truncate text-center"
                date={workout.date}
                onSelect={(date) => updateWorkout(workout.id, { date })}
              >
                {formatDateLong(workout.date)}
              </WorkoutDatePicker>
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
              className="mx-(--app-content-inset) grid grid-cols-3 gap-1.5 rounded-3xl border border-border bg-card/70 p-1.5"
            >
              <div className="rounded-2xl bg-muted/45 p-3 text-center">
                <Clock3 className="mx-auto size-4 text-primary" />
                <p className="mt-1.5 text-xl font-black tracking-tight tabular-nums">
                  {completion ? formatDuration(completion.durationMs) : "—"}
                </p>
                <p className="text-xs font-semibold text-muted-foreground">
                  Duration
                </p>
              </div>
              <div className="rounded-2xl bg-muted/45 p-3 text-center">
                <Activity className="mx-auto size-4 text-primary" />
                <p className="mt-1.5 text-xl font-black tracking-tight tabular-nums">
                  {completion ? completion.activeCalories : "—"}
                </p>
                <p className="text-xs font-semibold text-muted-foreground">
                  kcal
                </p>
              </div>
              <div className="rounded-2xl bg-muted/45 p-3 text-center">
                <CheckCircle2 className="mx-auto size-4 text-primary" />
                <p className="mt-1.5 text-xl font-black tracking-tight tabular-nums">
                  {completion
                    ? `${completion.completedExerciseIds.length}/${workout.exerciseIds.length}`
                    : "—"}
                </p>
                <p className="text-xs font-semibold text-muted-foreground">
                  Completed
                </p>
              </div>
            </section>
          ) : null}
          {plannedSession && !session && !isPast ? (
            <section
              aria-label="Planned session"
              className="mx-(--app-content-inset) grid grid-cols-3 gap-1.5 rounded-3xl border border-border bg-card/70 p-1.5"
            >
              <div className="rounded-2xl bg-muted/45 p-3 text-center">
                <ListChecks className="mx-auto size-4 text-primary" />
                <p className="mt-1.5 text-xl font-black tracking-tight tabular-nums">
                  {plannedSession.prescription.length}
                </p>
                <p className="text-xs font-semibold text-muted-foreground">
                  Exercises
                </p>
              </div>
              <div className="rounded-2xl bg-muted/45 p-3 text-center">
                <Layers className="mx-auto size-4 text-primary" />
                <p className="mt-1.5 text-xl font-black tracking-tight tabular-nums">
                  {plannedSession.workingSets}
                </p>
                <p className="text-xs font-semibold text-muted-foreground">
                  Sets
                </p>
              </div>
              <div className="rounded-2xl bg-muted/45 p-3 text-center">
                <Clock3 className="mx-auto size-4 text-primary" />
                <p className="mt-1.5 text-xl font-black tracking-tight tabular-nums">
                  {plannedSession.minutes}
                </p>
                <p className="text-xs font-semibold text-muted-foreground">
                  Minutes
                </p>
              </div>
            </section>
          ) : null}
          {plannedUnavailable || actionIssue ? (
            <div
              className="mx-(--app-content-inset) rounded-3xl border border-destructive/40 bg-destructive/10 p-4 text-sm font-semibold text-foreground"
              role="alert"
            >
              {actionIssue ??
                "This planned session is no longer available. Create a current plan from My workouts."}
            </div>
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
                  onOpenExercise={onOpenExercise}
                />
              )}

              {session && <WorkoutSessionCompanion session={session} />}

              <SortableExerciseList
                exerciseIds={workout.exerciseIds}
                onFindAlternative={
                  isPast || (isPlanned && !session)
                    ? undefined
                    : (candidate) => {
                        if (isPlanned) {
                          const draftExercise =
                            trainingData.activeWorkout?.exercises.find(
                              (item) => item.exerciseId === candidate.id
                            )
                          if (
                            draftExercise?.sets.some((set) => set.observation)
                          ) {
                            triggerHaptic("warning")
                            setActionIssue(
                              "This exercise already has recorded sets, so it can’t be replaced in this session."
                            )
                            return
                          }
                        }
                        setActionIssue(null)
                        triggerHaptic("light")
                        onFindAlternative(candidate)
                      }
                }
                onOpenExercise={onOpenExercise}
                onRemove={
                  // A planned session's exercises are the plan's, not this
                  // page's: dropping one here would leave the projection
                  // describing a session the program never prescribed.
                  isPast || isPlanned
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
                onReorder={isPast || isPlanned ? undefined : setExerciseIds}
                renderBelow={(exerciseId) => (
                  <>
                    {plannedSession && !session ? (
                      <PlannedTargets
                        exerciseId={exerciseId}
                        session={plannedSession}
                      />
                    ) : null}
                    {session ? (
                      <ExerciseSetLog
                        editing={editingExerciseId === exerciseId}
                        exerciseId={exerciseId}
                        onEditingChange={(editing) =>
                          setEditingExerciseId(editing ? exerciseId : null)
                        }
                      />
                    ) : null}
                  </>
                )}
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
              exercise={exercise}
              onNext={
                skipTarget ? () => setCurrentExercise(skipTarget) : undefined
              }
              onPause={pauseWorkout}
              onResume={resumeWorkout}
              session={session}
            />
          </div>
        ) : null}
      </AppSurface>

      <AppControls
        transitionKey={`workout:${
          session
            ? "running"
            : isPast
              ? "past"
              : isPlanned
                ? "prescribed"
                : "planned"
        }`}
      >
        {session ? (
          <div className="flex items-center gap-2.5">
            <AppControlButton
              aria-label="Discard session"
              onClick={() => {
                triggerHaptic("warning")
                setConfirming("discard-session")
              }}
            >
              <X />
            </AppControlButton>
            {isPlanned ? null : (
              <AppControlButton
                aria-label="Add exercise"
                onClick={onAddExercise}
              >
                <Plus />
              </AppControlButton>
            )}
            <AppControlButton
              aria-label="Finish workout"
              onClick={() => {
                triggerHaptic("medium")
                setConfirming(
                  finishRecordsPartial
                    ? "finish-workout-partial"
                    : "finish-workout"
                )
              }}
            >
              <Flag />
            </AppControlButton>
            <AppControlMorph className="app-command-fill" role="primary">
              <Button
                size="cta"
                className="w-full"
                disabled={!exercise}
                onClick={() => {
                  triggerHaptic("success")
                  completeCurrent()
                }}
              >
                Mark done
              </Button>
            </AppControlMorph>
          </div>
        ) : isPast ? (
          <div className="flex items-center gap-2.5">
            <AppControlButton
              aria-label="Delete workout"
              onClick={() => {
                triggerHaptic("warning")
                setConfirming("delete-workout")
              }}
              variant="destructive"
            >
              <Trash2 />
            </AppControlButton>
            <AppControlMorph className="app-command-fill" role="primary">
              <Button
                size="cta"
                className="w-full"
                onClick={() => {
                  const copiedId = duplicateWorkout(workout.id)
                  if (!copiedId) return
                  triggerHaptic("success")
                  onCopied?.(copiedId)
                }}
              >
                Copy to today
              </Button>
            </AppControlMorph>
          </div>
        ) : (
          <div className="flex min-w-0 items-center">
            {/* A planned session is the program's to withdraw, not this
                page's: there is nothing here to delete or add to. */}
            {isPlanned ? null : (
              <>
                <AppControlButton
                  aria-label="Delete workout"
                  className="mr-2.5"
                  onClick={() => {
                    triggerHaptic("warning")
                    setConfirming("delete-workout")
                  }}
                  variant="destructive"
                >
                  <Trash2 />
                </AppControlButton>
                <MorphingActionSlot visible={workout.exerciseIds.length > 0}>
                  <AppControlButton
                    aria-label="Add exercise"
                    onClick={onAddExercise}
                  >
                    <Plus />
                  </AppControlButton>
                </MorphingActionSlot>
              </>
            )}
            <AppControlMorph className="app-command-fill" role="primary">
              <Button
                className="w-full"
                disabled={plannedUnavailable}
                onClick={() => {
                  if (workout.exerciseIds.length === 0) {
                    onAddExercise()
                    return
                  }
                  triggerHaptic("heavy")
                  setCountingDown(true)
                  onCountdownChange?.(true)
                }}
                size="cta"
              >
                {plannedUnavailable ? (
                  "Plan unavailable"
                ) : workout.exerciseIds.length === 0 ? (
                  <>
                    <Plus className="size-5" />
                    Add exercise
                  </>
                ) : (
                  "Start workout"
                )}
              </Button>
            </AppControlMorph>
          </div>
        )}
      </AppControls>

      {countingDown && (
        <WorkoutCountdown
          onCancel={() => {
            setCountingDown(false)
            onCountdownChange?.(false)
          }}
          onComplete={() => {
            setCountingDown(false)
            onCountdownChange?.(false)
            if (!startWorkout(workout)) {
              triggerHaptic("warning")
              setActionIssue(
                "This planned session can’t be started from this plan. Create a current plan from My workouts."
              )
            }
          }}
        />
      )}

      <ConfirmModal
        kind={confirming}
        onCancel={() => setConfirming(null)}
        onConfirm={() => {
          setConfirming(null)
          if (confirming === "delete-workout") onDelete()
          else if (confirming === "discard-session") onDiscard()
          else if (
            confirming === "finish-workout" ||
            confirming === "finish-workout-partial"
          )
            onFinish()
        }}
      />
    </AppScreen>
  )
}
