import { useEffect, useState } from "react"

import { playRestAlarm } from "@/lib/haptics"

/**
 * The rest between sets, counting down.
 *
 * It starts when a set is saved and it belongs beside the target it is resting
 * against, because the two answer the same question: what this exercise asks
 * of you, and when to do the next one. At zero it says so out loud once and
 * then gets out of the way — a rest that is over is not information.
 *
 * The clock it counts against is read when it mounts, not on every render, so
 * a re-render mid-rest cannot restart it. A new rest is a new one of these.
 */
export function RestCountdown({
  onDone,
  seconds,
}: {
  onDone: () => void
  /** How long the rest is, from the moment this appears. */
  seconds: number
}) {
  const [left, setLeft] = useState(seconds)

  useEffect(() => {
    const until = Date.now() + seconds * 1000
    const remaining = () => Math.max(0, Math.ceil((until - Date.now()) / 1000))
    const timer = window.setInterval(() => {
      const next = remaining()
      setLeft(next)
      if (next > 0) return
      window.clearInterval(timer)
      playRestAlarm()
      onDone()
    }, 250)
    return () => window.clearInterval(timer)
    // `onDone` is how the owner forgets this rest; re-subscribing on a new
    // identity of it would restart the interval on every render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [seconds])

  const minutes = Math.floor(left / 60)
  return (
    <span
      aria-label={`Rest, ${left} seconds left`}
      className="ml-auto shrink-0 rounded-full bg-muted/60 px-2.5 py-1 text-[11px] font-bold text-foreground tabular-nums"
      role="timer"
    >
      {minutes}:{String(left % 60).padStart(2, "0")}
    </span>
  )
}
