import { useEffect, useRef, useState } from "react"

import { Button } from "@/components/ui/button"
import { triggerHaptic } from "@/lib/haptics"

const TICK_MS = 1000
const RADIUS = 74
const CIRCUMFERENCE = 2 * Math.PI * RADIUS

/**
 * The few seconds between pressing start and the clock running.
 *
 * Starting is a single tap on the screen a pocket is most likely to press, and
 * a session started by accident cannot be dismissed without losing the timer
 * that is already counting. So the start is announced before it happens: the
 * ring drains, every second ticks in the hand, and anything at all calls it
 * off. Anyone who does mean it can skip the wait by tapping the number.
 */
export function WorkoutCountdown({
  from = 3,
  onCancel,
  onComplete,
}: {
  from?: number
  onCancel: () => void
  onComplete: () => void
}) {
  const [remaining, setRemaining] = useState(from)
  const complete = useRef(onComplete)

  useEffect(() => {
    complete.current = onComplete
  }, [onComplete])

  // Each tick schedules the next one, so the countdown cannot drift into two
  // overlapping intervals if this remounts mid-count.
  useEffect(() => {
    if (remaining <= 0) {
      triggerHaptic("heavy")
      complete.current()
      return
    }

    triggerHaptic("light")
    const timeout = window.setTimeout(
      () => setRemaining((value) => value - 1),
      TICK_MS
    )
    return () => window.clearTimeout(timeout)
  }, [remaining])

  return (
    <div
      aria-label="Starting workout"
      aria-live="assertive"
      className="absolute inset-0 z-50 flex flex-col items-center justify-center gap-8 bg-background/92 backdrop-blur-xl"
      role="dialog"
    >
      <p className="text-xs font-bold tracking-[0.16em] text-primary uppercase">
        Get ready
      </p>

      <button
        aria-label="Start now"
        className="interactive-spring relative grid size-[11.5rem] place-items-center rounded-full"
        onClick={() => {
          triggerHaptic("heavy")
          setRemaining(0)
        }}
        type="button"
      >
        <svg
          aria-hidden="true"
          className="absolute inset-0 -rotate-90"
          viewBox="0 0 184 184"
        >
          <circle
            cx="92"
            cy="92"
            fill="none"
            r={RADIUS}
            stroke="var(--border)"
            strokeWidth="7"
          />
          <circle
            className="t-countdown-ring"
            cx="92"
            cy="92"
            fill="none"
            r={RADIUS}
            stroke="var(--primary)"
            strokeDasharray={CIRCUMFERENCE}
            strokeDashoffset={CIRCUMFERENCE * (1 - remaining / from)}
            strokeLinecap="round"
            strokeWidth="7"
          />
        </svg>
        <span
          className="t-countdown-digit text-[5.5rem] leading-none font-black tabular-nums"
          key={remaining}
        >
          {Math.max(remaining, 1)}
        </span>
      </button>

      <Button
        className="h-[3.25rem] w-[min(18rem,70%)] rounded-[26px] text-base font-semibold"
        onClick={() => {
          triggerHaptic("warning")
          onCancel()
        }}
        variant="secondary"
      >
        Cancel
      </Button>
    </div>
  )
}
