import { registerPlugin } from "@capacitor/core"

import { isNative } from "@/lib/native"

/**
 * Everything the Lock Screen card and the Dynamic Island need for one frame.
 *
 * The timer is deliberately *not* a duration: the native side is handed the
 * wall-clock instant the stopwatch effectively started and lets ActivityKit
 * count on its own, so a running workout needs no per-second updates. A paused
 * workout has no instant to count from, so it sends the frozen elapsed time
 * instead — which keeps every field here a pure function of the session and
 * lets the sync skip updates that would not change a pixel.
 */
export type LiveActivityContent = {
  /** Identifies the card: a different workout replaces it rather than
   *  updating it, because ActivityKit attributes are immutable. */
  workoutId: string
  workoutName: string
  workoutDate: string
  /** Selects the demonstration frame the extension renders; "" when done. */
  exerciseId: string
  exerciseName: string
  /** Names the prepared muscle map for this exercise; "" when there is none.
   *  The card shows the map rather than spelling the muscles out. */
  muscleMapKey: string
  completedCount: number
  totalCount: number
  /** Epoch ms; 0 while paused. */
  timerStartEpochMs: number
  /** Frozen elapsed time; 0 while running. */
  elapsedMs: number
  isPaused: boolean
}

/**
 * A frame plus the artwork the native side may still be missing. The PNG is
 * carried separately from the content because it is large, identical for every
 * frame of the same exercise, and written to the shared container at most once
 * — the sync compares frames on {@link LiveActivityContent} alone.
 */
export type LiveActivityPayload = LiveActivityContent & {
  /** Base64 PNG of the muscle map for `muscleMapKey`; "" when it could not be
   *  prepared. Sent on every frame rather than once — the native side writes
   *  it only if the file is missing, so a map evicted from its bounded cache
   *  comes back on its own. */
  muscleMapPng: string
  /** Which still of the exercise's movement to show. A Live Activity cannot
   *  play an animation, and only redraws when the content state changes, so
   *  the demonstration is stepped on by one every time the card is updated —
   *  which is the whole of the motion the platform allows. Wraps natively. */
  frameIndex: number
}

export type LiveActivityEndOptions = LiveActivityPayload & {
  /** A finished workout lingers on the Lock Screen; a cancelled one does not. */
  dismissImmediately: boolean
}

export type LiveActivityPlugin = {
  isSupported: () => Promise<{ supported: boolean }>
  start: (
    content: LiveActivityPayload
  ) => Promise<{ activityId: string | null }>
  update: (content: LiveActivityPayload) => Promise<void>
  end: (options: LiveActivityEndOptions) => Promise<void>
}

const plugin = registerPlugin<LiveActivityPlugin>("LiveActivity")

/**
 * ActivityKit exists only inside the iOS shell, and only from iOS 16.1. Every
 * call is a no-op elsewhere and a rejected one is swallowed: a Live Activity
 * is an accessory to the workout, never a reason to break it.
 */
export const liveActivity = {
  isSupported: async () => {
    if (!isNative()) return false
    try {
      const { supported } = await plugin.isSupported()
      return supported
    } catch {
      return false
    }
  },
  start: (content: LiveActivityPayload) => call(() => plugin.start(content)),
  update: (content: LiveActivityPayload) => call(() => plugin.update(content)),
  end: (options: LiveActivityEndOptions) => call(() => plugin.end(options)),
}

async function call(run: () => Promise<unknown>) {
  if (!isNative()) return
  try {
    await run()
  } catch {
    // Denied permission, an unsupported OS version, or the system's cap on
    // concurrent activities. None of it should surface in the workout.
  }
}
