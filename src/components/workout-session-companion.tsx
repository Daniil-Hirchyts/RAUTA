import { Rauta, type RautaMood } from "@/components/rauta"
import { RautaSpeech } from "@/components/rauta-speech"
import {
  sessionProgress,
  type ActiveWorkoutSession,
} from "@/lib/active-workout"
import { useTrainingRecords } from "@/store/use-training-records"

/**
 * RAUTA during a workout.
 *
 * It reacts to the session, and only to the session: how many sets have been
 * logged, how many exercises are done. Every line below is chosen by a
 * condition on that state — there is no model, no service and nothing
 * generated, so the character can never claim something the workout does not
 * say. One line, one glance; the set log stays the thing being used.
 */
function line(sets: number, completed: number, total: number) {
  if (sets === 0)
    return {
      mood: "focused" as RautaMood,
      text: "Log the first set when it's done. I'll keep the record.",
    }
  if (completed >= total && total > 0)
    return {
      mood: "proud" as RautaMood,
      text: `Every exercise done — ${sets} ${sets === 1 ? "set" : "sets"} on the board.`,
    }
  if (sets === 1)
    return {
      mood: "happy" as RautaMood,
      text: "First set logged. That one counts now.",
    }
  return {
    mood: "working" as RautaMood,
    text: `${sets} sets logged · ${completed} of ${total} exercises done.`,
  }
}

export function WorkoutSessionCompanion({
  session,
}: {
  session: ActiveWorkoutSession
}) {
  const draft = useTrainingRecords((state) => state.data.activeWorkout)
  const { completed, total } = sessionProgress(session)
  const sets =
    draft?.exercises.reduce(
      (count, exercise) =>
        count +
        exercise.sets.filter((set) => set.observation?.completed).length,
      0
    ) ?? 0
  const { mood, text } = line(sets, completed, total)

  // Nothing to react to before the draft exists — a session restored from
  // before structured logging keeps working without a companion.
  if (!draft) return null

  return (
    <div className="mx-(--app-content-inset) flex items-center gap-1.5">
      <Rauta
        label="RAUTA is following this workout"
        mood={mood}
        reactionKey={`${sets}:${completed}`}
        size={72}
      />
      <RautaSpeech className="min-w-0 flex-1">
        <p
          aria-live="polite"
          className="text-[13px] leading-snug font-semibold"
        >
          {text}
        </p>
      </RautaSpeech>
    </div>
  )
}
