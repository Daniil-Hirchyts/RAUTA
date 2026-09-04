import { Pause, Play } from "lucide-react"

import { Button } from "@/components/ui/button"
import { useElapsedMs } from "@/hooks/use-elapsed-ms"
import {
  formatDuration,
  sessionProgress,
  type ActiveWorkoutSession,
} from "@/lib/active-workout"
import { triggerHaptic } from "@/lib/haptics"

/**
 * The workout clock: elapsed time, how much of the session is done, and the
 * one control that changes either. Its parent keeps it in the fixed bottom
 * dock rather than letting it scroll with the exercise list, because it is
 * the thing being glanced at mid-set — and it mirrors the Lock Screen card,
 * so both readings agree.
 */
export function ActiveWorkoutTimer({
  onPause,
  onResume,
  session,
}: {
  onPause: () => void
  onResume: () => void
  session: ActiveWorkoutSession
}) {
  const elapsed = useElapsedMs(session)
  const { completed, total } = sessionProgress(session)
  const isPaused = session.runningSince === null

  return (
    <div className="active-workout-timer pointer-events-auto flex items-center gap-3 rounded-3xl border border-primary/25 bg-background/85 p-3.5 shadow-lg shadow-black/40 backdrop-blur-xl">
      <div className="min-w-0 flex-1">
        <p className="text-xs font-bold tracking-[0.16em] text-primary uppercase">
          {isPaused ? "Paused" : "In progress"}
        </p>
        <p
          aria-label={`Elapsed time ${formatDuration(elapsed)}`}
          className="mt-0.5 text-[28px] leading-none font-black tracking-[-0.02em] tabular-nums"
          role="timer"
        >
          {formatDuration(elapsed)}
        </p>
      </div>

      <div className="flex flex-col items-end gap-1.5">
        <p className="text-sm font-semibold text-muted-foreground tabular-nums">
          {completed} of {total} done
        </p>
        <ol aria-hidden="true" className="flex items-center gap-1">
          {session.exerciseIds.map((exerciseId) => (
            <li
              className={`h-1.5 rounded-full transition-[width,background-color] duration-250 ${
                session.completedIds.includes(exerciseId)
                  ? "w-4 bg-primary"
                  : exerciseId === session.currentExerciseId
                    ? "w-6 bg-primary/55"
                    : "w-4 bg-white/12"
              }`}
              key={exerciseId}
            />
          ))}
        </ol>
      </div>

      <Button
        aria-label={isPaused ? "Resume workout" : "Pause workout"}
        className="size-11 shrink-0 rounded-full"
        onClick={() => {
          triggerHaptic("medium")
          if (isPaused) onResume()
          else onPause()
        }}
        size="icon"
        variant="secondary"
      >
        {isPaused ? <Play className="size-5" /> : <Pause className="size-5" />}
      </Button>
    </div>
  )
}
