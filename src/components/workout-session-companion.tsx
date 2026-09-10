import { ActiveWorkoutTimer } from "@/components/active-workout-timer"
import { Rauta, type RautaMood } from "@/components/rauta"
import {
  sessionProgress,
  type ActiveWorkoutSession,
} from "@/lib/active-workout"
import { activePlannedCoverage } from "@/lib/training-session"
import { useTrainingRecords } from "@/store/use-training-records"
import type { ExerciseSummary } from "@/types"

/**
 * RAUTA during a workout.
 *
 * It reacts to the session, and only to the session: how many sets have been
 * logged, how many exercises are done. Every line below is chosen by a
 * condition on that state — there is no model, no service and nothing
 * generated, so the character can never claim something the workout does not
 * say. One line, one glance; the set log stays the thing being used.
 */
function line(
  sets: number,
  completed: number,
  total: number,
  /** Prescribed working sets still unlogged, or null for a free workout. */
  outstanding: number | null
) {
  const setBeat = [
    "Steady work. I have every set.",
    "Logged cleanly. Keep your pace.",
    "Another one recorded. Breathe, then go.",
    "The board is moving. Stay with it.",
  ][sets % 4]
  if (sets === 0)
    return {
      mood: "focused" as RautaMood,
      text: "Log the first set when it's done. I'll keep the record.",
    }
  if (outstanding === -1)
    return {
      mood: "thinking" as RautaMood,
      text: "I can't verify the plan. Logged sets will be saved as partial.",
    }
  // The prescription is finished: that is the one moment worth celebrating.
  if (outstanding === 0)
    return {
      mood: "excited" as RautaMood,
      text: `Whole session done — ${sets} ${sets === 1 ? "set" : "sets"} against the plan.`,
    }
  if (outstanding === null && completed >= total && total > 0)
    return {
      mood: "proud" as RautaMood,
      text: `Every exercise done — ${sets} ${sets === 1 ? "set" : "sets"} on the board.`,
    }
  // Prescribed work left over reads as thinking rather than as disapproval:
  // finishing here is allowed, and it is recorded as a partial session.
  if (
    outstanding !== null &&
    outstanding > 0 &&
    completed >= total &&
    total > 0
  )
    return {
      mood: "thinking" as RautaMood,
      text: `${outstanding} prescribed ${outstanding === 1 ? "set" : "sets"} still open. Finishing now saves this as partial.`,
    }
  if (sets === 1)
    return {
      mood: "happy" as RautaMood,
      text: [
        "First set logged. That one counts now.",
        "We're underway. First set is in.",
      ][completed % 2],
    }
  if (outstanding !== null)
    return {
      mood: "working" as RautaMood,
      text: `${setBeat} ${outstanding} prescribed ${outstanding === 1 ? "set" : "sets"} to go.`,
    }
  return {
    mood: "working" as RautaMood,
    text: `${setBeat} ${completed} of ${total} exercises done.`,
  }
}

export function WorkoutSessionCompanion({
  exercise,
  onNext,
  onPause,
  onResume,
  session,
}: {
  exercise?: ExerciseSummary | null
  onNext?: () => void
  onPause: () => void
  onResume: () => void
  session: ActiveWorkoutSession
}) {
  const data = useTrainingRecords((state) => state.data)
  const draft = data.activeWorkout
  const { completed, total } = sessionProgress(session)
  const sets =
    draft?.exercises.reduce(
      (count, exercise) =>
        count +
        exercise.sets.filter((set) => set.observation?.completed).length,
      0
    ) ?? 0
  // Read straight off the prescription, so what RAUTA says about the session
  // and what will actually be written to history are the same judgement.
  const coverage = activePlannedCoverage(data)
  const outstanding = coverage
    ? coverage.verified
      ? coverage.prescribed - coverage.performed
      : -1
    : null
  const { mood, text } = line(sets, completed, total, outstanding)

  // Nothing to react to before the draft exists — a session restored from
  // before structured logging keeps working without a companion.
  if (!draft) return null

  // One band at the foot of the screen, not two: the clock is the thing being
  // glanced at mid-set, and the character stands on the same panel it is in.
  // What RAUTA says is a passing remark — a workout is not a conversation —
  // but the panel stays, because the clock is in it.
  return (
    <Rauta
      footer={
        <ActiveWorkoutTimer
          exercise={exercise}
          onNext={onNext}
          onPause={onPause}
          onResume={onResume}
          session={session}
        />
      }
      label="RAUTA is following this workout"
      mood={mood}
      place="bottom"
      size={96}
      speech={text}
      transient
    />
  )
}
