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
  exerciseMuscles: string
  nextExerciseName: string
  completedCount: number
  totalCount: number
  /** Epoch ms; 0 while paused. */
  timerStartEpochMs: number
  /** Frozen elapsed time; 0 while running. */
  elapsedMs: number
  isPaused: boolean
}

export type LiveActivityEndOptions = LiveActivityContent & {
  /** A finished workout lingers on the Lock Screen; a cancelled one does not. */
  dismissImmediately: boolean
}

export type LiveActivityPlugin = {
  isSupported: () => Promise<{ supported: boolean }>
  start: (
    content: LiveActivityContent
  ) => Promise<{ activityId: string | null }>
  update: (content: LiveActivityContent) => Promise<void>
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
  start: (content: LiveActivityContent) => call(() => plugin.start(content)),
  update: (content: LiveActivityContent) => call(() => plugin.update(content)),
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
