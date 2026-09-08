import { Pause, Play, SkipForward } from "lucide-react"

import { Button } from "@/components/ui/button"
import { useElapsedMs } from "@/hooks/use-elapsed-ms"
import {
  formatDuration,
  sessionProgress,
  type ActiveWorkoutSession,
} from "@/lib/active-workout"
import { triggerHaptic } from "@/lib/haptics"
import type { ExerciseSummary } from "@/types"

/**
 * The workout clock: elapsed time, how much of the session is done, and the
 * one control that changes either. Its parent keeps it in the fixed bottom
 * dock rather than letting it scroll with the exercise list, because it is
 * the thing being glanced at mid-set — and it mirrors the Lock Screen card,
 * so both readings agree.
 */
export function ActiveWorkoutTimer({
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
  const elapsed = useElapsedMs(session)
  const { completed, total } = sessionProgress(session)
  const isPaused = session.runningSince === null

  return (
    <div className="frosted-glass active-workout-timer pointer-events-auto flex items-center gap-2 rounded-full border py-3 pr-2.5 pl-4 min-[360px]:gap-2.5 min-[360px]:pr-3 min-[360px]:pl-5">
      <div className="min-w-0 flex-1">
        {/* Narrow phones give the dock about 290px. Everything in it is a
            fixed width, so on those the type steps down rather than the
            status wrapping over the clock. */}
        <p className="truncate text-[11px] font-bold tracking-[0.1em] text-primary uppercase min-[360px]:text-[13px] min-[360px]:tracking-[0.16em]">
          {isPaused ? "Paused" : "In progress"}
        </p>
        <p
          aria-label={`Elapsed time ${formatDuration(elapsed)}`}
          className="mt-0.5 font-readout text-[32px] leading-none font-black tracking-[-0.02em] tabular-nums"
          role="timer"
        >
          {formatDuration(elapsed)}
        </p>
      </div>

      <div className="flex shrink-0 flex-col items-end gap-1.5">
        <p className="text-[13px] font-semibold whitespace-nowrap text-muted-foreground tabular-nums min-[360px]:text-[15px]">
          {/* The narrow phone keeps the count and gives the room back to the
              status beside it, which is the half that reads as a sentence. */}
          <span className="min-[360px]:hidden">
            {completed}/{total}
          </span>
          <span className="hidden min-[360px]:inline">
            {completed} of {total} done
          </span>
        </p>
        <ol
          aria-hidden="true"
          className="flex w-full max-w-[96px] items-center justify-end gap-1"
        >
          {session.exerciseIds.map((exerciseId) => (
            <li
              className={`h-1 shrink rounded-full transition-[width,background-color] duration-250 ${
                session.completedIds.includes(exerciseId)
                  ? "w-2.5 min-w-1 bg-primary-gradient"
                  : exerciseId === session.currentExerciseId
                    ? "w-4 min-w-2 bg-primary/55"
                    : "w-2.5 min-w-1 bg-white/12"
              }`}
              key={exerciseId}
            />
          ))}
        </ol>
      </div>

      <div className="flex items-center gap-1.5">
        <Button
          aria-label={isPaused ? "Resume workout" : "Pause workout"}
          className="size-10 shrink-0 rounded-full min-[360px]:size-11"
          onClick={() => {
            triggerHaptic("medium")
            if (isPaused) onResume()
            else onPause()
          }}
          size="icon"
          variant="secondary"
        >
          {isPaused ? (
            <Play className="size-5" />
          ) : (
            <Pause className="size-5" />
          )}
        </Button>

        <Button
          aria-label={exercise ? `Skip ${exercise.name}` : "Next exercise"}
          className="size-10 shrink-0 rounded-full min-[360px]:size-11"
          disabled={!onNext}
          onClick={() => {
            triggerHaptic("light")
            onNext?.()
          }}
          size="icon"
          variant="secondary"
        >
          <SkipForward className="size-5" />
        </Button>
      </div>
    </div>
  )
}
