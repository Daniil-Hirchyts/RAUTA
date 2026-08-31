import { useEffect, useReducer } from "react"

import { elapsedMs, type ActiveWorkoutSession } from "@/lib/active-workout"

/**
 * The live elapsed time of a session, re-read four times a second so the
 * seconds digit never lands more than a quarter second late. The clock is the
 * external system here — the value is derived at render time and the interval
 * only asks for another render, so nothing has to be kept in sync by hand.
 *
 * A paused session needs no ticking, and neither does an absent one. Every
 * store mutation produces a new session object, so a pause or a resume
 * re-runs the effect on its own.
 */
export function useElapsedMs(session: ActiveWorkoutSession | null) {
  const [, tick] = useReducer((count: number) => count + 1, 0)

  useEffect(() => {
    if (!session || session.runningSince === null) return

    const interval = window.setInterval(tick, 250)
    return () => window.clearInterval(interval)
  }, [session])

  return session ? elapsedMs(session) : 0
}
