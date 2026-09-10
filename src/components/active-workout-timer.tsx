import { Pause, Play, SkipForward } from "lucide-react"

import { Button } from "@/components/ui/button"
import { useElapsedMs } from "@/hooks/use-elapsed-ms"
import { formatDuration, type ActiveWorkoutSession } from "@/lib/active-workout"
import { triggerHaptic } from "@/lib/haptics"
import { cueRauta } from "@/lib/rauta-cues"
import type { ExerciseSummary } from "@/types"

/**
 * The workout clock: elapsed time, and the two controls that change it. It
 * lives inside RAUTA's panel at the foot of the screen rather than in a bar of
 * its own, because it is the thing being glanced at mid-set and there is no
 * reason for the screen to keep two fixed bands. How far through the session
 * you are belongs under the page's title, where the workout is named — this is
 * the clock. It mirrors the Lock Screen card, so both readings agree.
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
  const isPaused = session.runningSince === null

  return (
    <div className="active-workout-timer pointer-events-auto flex items-center gap-2 min-[360px]:gap-2.5">
      {/* Centred in what the character leaves rather than pushed against it:
          the panel is shared, and the clock is what it is read for. */}
      <div className="min-w-0 flex-1 text-center">
        {/* Narrow phones give the dock about 290px. Everything in it is a
            fixed width, so on those the type steps down rather than the
            status wrapping over the clock. */}
        <p className="truncate text-[10px] font-bold tracking-[0.14em] text-primary uppercase">
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

      <div className="flex items-center gap-1.5">
        <Button
          aria-label={isPaused ? "Resume workout" : "Pause workout"}
          className="size-10 shrink-0 rounded-full min-[360px]:size-11"
          onClick={() => {
            triggerHaptic("medium")
            if (isPaused) {
              onResume()
              cueRauta("workout-resumed")
            } else {
              onPause()
              cueRauta("workout-paused")
            }
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
            if (onNext) cueRauta("exercise-skipped")
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
