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
import { SlidingTabs } from "@/components/ui/sliding-tabs"
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
  sessionProgress,
} from "@/lib/active-workout"
import { formatDateLong } from "@/lib/date"
import { triggerHaptic } from "@/lib/haptics"
import { cueRauta } from "@/lib/rauta-cues"
import {
  plannedSessionView,
  type PlannedSessionView,
} from "@/lib/training-plan"
import { formatKg } from "@/lib/resistance"
import { activePlannedCoverage } from "@/lib/training-session"
import { cn } from "@/lib/utils"
import { shareWorkout } from "@/lib/workout-sharing"
import { duplicateWorkoutWithEngine } from "@/lib/engine-workout"
import {
  rescheduleWorkout,
  updateScheduledWorkoutExercises,
} from "@/lib/training-edits"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useTrainingRecords } from "@/store/use-training-records"
import { isStartablePlannedSession } from "@/training-persistence/program"
import { useWorkouts, type Workout } from "@/store/use-workouts"
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
  const reps =
    item.reps.min === item.reps.max
      ? `${item.reps.max}`
      : `${item.reps.min}–${item.reps.max}`
  return (
    <div className="workout-prescription overflow-x-auto tabular-nums">
      <div className="workout-prescription__item">
        <span className="workout-prescription__label">Sets</span>
        <strong className="workout-prescription__value">{item.sets}</strong>
      </div>
      <div className="workout-prescription__item">
        <span className="workout-prescription__label">Reps</span>
        <strong className="workout-prescription__value">{reps}</strong>
      </div>
      <div className="workout-prescription__item">
        <span className="workout-prescription__label">RIR</span>
        <strong className="workout-prescription__value">{item.rir}</strong>
      </div>
      {item.loadKg !== null ? (
        <div className="workout-prescription__item">
          <span className="workout-prescription__label">Load</span>
          <strong className="workout-prescription__value">
            {formatKg(item.loadKg)} kg
          </strong>
        </div>
      ) : null}
      <div className="workout-prescription__item">
        <span className="workout-prescription__label">Rest</span>
        <strong className="workout-prescription__value">
          {Math.round(item.restSeconds)}s
        </strong>
      </div>
    </div>
  )
}

function WorkoutOverview({
  completion,
  exerciseCount,
  past,
  plannedSession,
  structuredDurationSeconds,
  structuredExerciseCount,
}: {
  completion: NonNullable<Workout["completion"]> | null
  exerciseCount: number
  past: boolean
  plannedSession: PlannedSessionView | null
  structuredDurationSeconds?: number
  structuredExerciseCount?: number
}) {
  const primary = past
    ? {
        icon: <CheckCircle2 />,
        value:
          completion || structuredExerciseCount !== undefined
            ? `${completion?.completedExerciseIds.length ?? structuredExerciseCount}/${exerciseCount}`
            : "—",
        label: "Completed",
      }
    : {
        icon: <ListChecks />,
        value: plannedSession?.prescription.length ?? exerciseCount,
        label: "Exercises",
      }
  const secondary = past
    ? [
        {
          icon: <Clock3 />,
          value:
            completion || structuredDurationSeconds !== undefined
              ? formatDuration(
                  completion?.durationMs ?? structuredDurationSeconds! * 1000
                )
              : "—",
          label: "Duration",
        },
        {
          icon: <Activity />,
          value: completion?.activeCalories ?? "—",
          label: "kcal",
        },
      ]
    : [
        {
          icon: <Layers />,
          value: plannedSession?.workingSets ?? "—",
          label: "Sets",
        },
        {
          icon: <Clock3 />,
          value: plannedSession?.minutes ?? "—",
          label: "Minutes",
        },
      ]

  const primaryValue =
    typeof primary.value === "number"
      ? String(primary.value).padStart(2, "0")
      : primary.value

  return (
    <section
      aria-label={past ? "Workout stats" : "Planned session"}
      className={`workout-overview ${past ? "workout-overview--past" : ""}`}
    >
      <div className="workout-overview__hero">
        <div>
          <p className="workout-overview__eyebrow">{primary.label}</p>
          <p className="workout-overview__value tabular-nums">{primaryValue}</p>
        </div>
        <span className="workout-overview__mark" aria-hidden="true">
          {primary.icon}
        </span>
      </div>
      <div className="workout-overview__rail">
        {secondary.map((item) => (
          <div className="workout-overview__metric" key={item.label}>
            <span className="workout-overview__metric-icon">{item.icon}</span>
            <p className="workout-overview__metric-value font-readout tabular-nums">
              {item.value}
            </p>
            <p className="workout-overview__metric-label">{item.label}</p>
          </div>
        ))}
      </div>
    </section>
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
  /** Which half of a running session is on screen: the exercise being
   *  performed, on its own, or the whole workout it belongs to. Without a
   *  session there is only the workout, so there is nothing to choose. */
  const [tab, setTab] = useState<0 | 1>(0)
  const [confirming, setConfirming] = useState<ConfirmationKind | null>(null)
  const [confirmationIssue, setConfirmationIssue] = useState<string | null>(
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
  /** Whether the page is showing the whole workout rather than the one
   *  exercise being performed. Without a session there is nothing else to
   *  show. */
  const showPlan = !session || tab === 1
  const progress = session ? sessionProgress(session) : null
  const isPast =
    !session &&
    (Boolean(workout.completion) ||
      Boolean(
        plannedSessionId &&
        trainingData.sessions.some(
          (item) => item.plannedSessionId === plannedSessionId
        )
      ))
  const completion = workout.completion
  const structuredCompletion = plannedSessionId
    ? trainingData.sessions.find(
        (item) => item.plannedSessionId === plannedSessionId
      )
    : trainingData.sessions.find((item) => item.sourceWorkoutId === workout.id)
  const completedExerciseIds = completion
    ? new Set(completion.completedExerciseIds)
    : new Set(
        structuredCompletion?.exercises
          .filter((item) => item.sets.some((set) => set.completed))
          .map((item) => item.exerciseId) ?? []
      )

  // A running session mirrors the saved workout through the store, so an edit
  // made here — or from the find-an-exercise flow — reaches it either way.
  const setExerciseIds = (exerciseIds: string[], movedExerciseId?: string) => {
    if (movedExerciseId) syncExercises(exerciseIds, movedExerciseId)
    if (session) updateWorkout(workout.id, { exerciseIds })
    else updateScheduledWorkoutExercises(workout.id, exerciseIds)
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
          subtitle={
            session && progress ? (
              // How far through the workout you are, under the day it is on:
              // the panel at the foot of the screen is for the clock, and this
              // is for the shape of the session.
              <span className="flex items-center justify-center gap-2">
                <span className="tabular-nums">
                  {progress.completed} of {progress.total} done
                </span>
                <span
                  aria-hidden="true"
                  className="flex max-w-[6rem] items-center gap-1"
                >
                  {session.exerciseIds.map((id) => (
                    <span
                      className={cn(
                        "h-1 shrink rounded-full transition-[width,background-color] duration-250",
                        session.completedIds.includes(id)
                          ? "w-2.5 min-w-1 bg-primary-gradient"
                          : id === session.currentExerciseId
                            ? "w-4 min-w-2 bg-primary/55"
                            : "w-2.5 min-w-1 bg-white/12"
                      )}
                      key={id}
                    />
                  ))}
                </span>
              </span>
            ) : undefined
          }
          title={
            isPast || session ? (
              formatDateLong(workout.date)
            ) : (
              <WorkoutDatePicker
                ariaLabel={`Change date, currently ${formatDateLong(workout.date)}`}
                className="max-w-full truncate text-center"
                date={workout.date}
                onSelect={(date) => {
                  try {
                    rescheduleWorkout(workout.id, date)
                    setActionIssue(null)
                  } catch (error) {
                    setActionIssue(
                      error instanceof Error
                        ? error.message
                        : "Couldn’t move this workout. Please try again."
                    )
                  }
                }}
              >
                {formatDateLong(workout.date)}
              </WorkoutDatePicker>
            )
          }
        />

        <div
          className={cn(
            "app-scroll-region min-h-0 flex-1 space-y-5 overflow-y-auto pt-5",
            // The foot of the screen belongs to the character's panel, and it
            // has the clock in it.
            session ? "pb-44" : "pb-6"
          )}
          ref={scrollRef}
          tabIndex={-1}
        >
          {session ? (
            <div className="mx-(--app-content-inset)">
              <SlidingTabs
                activeIndex={tab}
                onChange={(index) => setTab(index === 1 ? 1 : 0)}
                tabs={[{ label: "Exercise" }, { label: "Workout" }]}
              />
            </div>
          ) : null}
          {showPlan && (isPast || plannedSession) ? (
            <WorkoutOverview
              completion={completion}
              exerciseCount={workout.exerciseIds.length}
              past={isPast}
              plannedSession={plannedSession}
              structuredDurationSeconds={structuredCompletion?.durationSeconds}
              structuredExerciseCount={
                structuredCompletion ? completedExerciseIds.size : undefined
              }
            />
          ) : null}
          {(!isPast && plannedUnavailable) || actionIssue ? (
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
              {/* The exercise being performed, on its own: the demonstration
                  once, the sets under it, and nothing else to scroll past
                  mid-set. The rest of the workout is one tap away. */}
              {session && !showPlan ? (
                exercise ? (
                  <>
                    <ActiveWorkoutHero
                      exercise={exercise}
                      onOpenExercise={onOpenExercise}
                    />
                    <ExerciseSetLog
                      exerciseId={exercise.id}
                      restSeconds={
                        plannedSession?.prescription.find(
                          (item) => item.exerciseId === exercise.id
                        )?.restSeconds
                      }
                    />
                  </>
                ) : (
                  <p className="px-8 text-center text-sm text-muted-foreground">
                    Every exercise in this workout is done.
                  </p>
                )
              ) : null}

              {showPlan ? (
                <SortableExerciseList
                  exerciseIds={workout.exerciseIds}
                  onFindAlternative={
                    isPast || plannedUnavailable
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
                  renderBelow={
                    plannedSession
                      ? (exerciseId) => (
                          // What the week asked of this exercise. The sets
                          // performed against it are logged on its own tab,
                          // where there is room to do it one exercise at a time.
                          <PlannedTargets
                            exerciseId={exerciseId}
                            session={plannedSession}
                          />
                        )
                      : undefined
                  }
                  onToggleComplete={
                    session
                      ? (id) => {
                          triggerHaptic("selection")
                          toggleComplete(id)
                        }
                      : undefined
                  }
                  statusOf={
                    session
                      ? (id) => exerciseStatus(session, id)
                      : isPast
                        ? (id) =>
                            completedExerciseIds.has(id)
                              ? "completed"
                              : "pending"
                        : undefined
                  }
                  // The same card whether the workout has started or not: a
                  // running session does not change what an exercise is.
                  variant="overview"
                />
              ) : null}
            </>
          )}
        </div>

        {/* One band at the foot of the screen: the character and the clock in
            the same panel, rather than a fixed bar with a companion beside
            it. */}
        {session ? (
          <WorkoutSessionCompanion
            exercise={exercise}
            onNext={
              skipTarget ? () => setCurrentExercise(skipTarget) : undefined
            }
            onPause={pauseWorkout}
            onResume={resumeWorkout}
            session={session}
          />
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
            <AppControlButton aria-label="Add exercise" onClick={onAddExercise}>
              <Plus />
            </AppControlButton>
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
              {/* Nothing left to mark done: the only thing left is to finish,
                  so that is what the band offers. */}
              {exercise ? (
                <Button
                  size="cta"
                  className="w-full"
                  onClick={() => {
                    triggerHaptic("success")
                    completeCurrent()
                    cueRauta("exercise-completed")
                  }}
                >
                  Mark done
                </Button>
              ) : (
                <Button
                  size="cta"
                  className="w-full"
                  onClick={() => {
                    triggerHaptic("medium")
                    setConfirming(
                      finishRecordsPartial
                        ? "finish-workout-partial"
                        : "finish-workout"
                    )
                  }}
                >
                  Finish
                </Button>
              )}
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
                  const copiedId = duplicateWorkoutWithEngine(
                    workout.id,
                    new Date().toISOString().slice(0, 10)
                  )
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
              cueRauta("action-blocked")
              setActionIssue(
                "This planned session can’t be started from this plan. Create a current plan from My workouts."
              )
            } else {
              cueRauta("workout-started")
            }
          }}
        />
      )}

      <ConfirmModal
        error={confirmationIssue}
        kind={confirming}
        onCancel={() => {
          setConfirming(null)
          setConfirmationIssue(null)
        }}
        onConfirm={() => {
          try {
            if (confirming === "delete-workout") onDelete()
            else if (confirming === "discard-session") onDiscard()
            else if (
              confirming === "finish-workout" ||
              confirming === "finish-workout-partial"
            ) {
              onFinish()
              cueRauta("workout-finished")
            }
            setConfirming(null)
            setConfirmationIssue(null)
          } catch {
            triggerHaptic("warning")
            cueRauta("action-blocked")
            setConfirmationIssue("Couldn’t save this change. Please try again.")
          }
        }}
      />
    </AppScreen>
  )
}
