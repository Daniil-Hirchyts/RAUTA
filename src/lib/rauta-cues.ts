import type { RautaReaction } from "@/lib/rauta"

/** Meaningful product events RAUTA can answer without coupling screens to the
 * animation rig. These are deliberately sparse: a workout action gets a
 * response; ordinary navigation does not become chatter. */
export type RautaCue =
  | "set-saved"
  | "exercise-completed"
  | "exercise-skipped"
  | "workout-paused"
  | "workout-resumed"
  | "workout-started"
  | "workout-finished"
  | "plan-adjusted"
  | "action-blocked"

export type RautaResponse = {
  reaction: RautaReaction
  line: string
}

const RESPONSES: Record<RautaCue, readonly RautaResponse[]> = {
  "set-saved": [
    { reaction: "acknowledge", line: "Set locked in." },
    { reaction: "wink", line: "Got it. Keep moving." },
    { reaction: "gearUp", line: "Recorded. Next one when you're ready." },
    { reaction: "relieved", line: "That's on the board." },
  ],
  "exercise-completed": [
    { reaction: "celebrate", line: "Exercise done. Strong work." },
    { reaction: "gearUp", line: "One station cleared." },
    { reaction: "wink", line: "That's finished. Onward." },
  ],
  "exercise-skipped": [
    { reaction: "acknowledge", line: "Moving on. We can come back." },
    { reaction: "turnaround", line: "Next exercise. Stay warm." },
    { reaction: "peek", line: "Skipping ahead. I've kept your place." },
  ],
  "workout-paused": [
    { reaction: "relieved", line: "Clock paused. Take the moment." },
    { reaction: "blinkDouble", line: "Paused. I'll hold our place." },
    { reaction: "peek", line: "Break time. I'm still here." },
  ],
  "workout-resumed": [
    { reaction: "gearUp", line: "We're back. Clock is running." },
    { reaction: "acknowledge", line: "Resumed. Pick up where you left off." },
    { reaction: "wink", line: "Back in motion." },
  ],
  "workout-started": [
    { reaction: "gearUp", line: "Let's train. First set when you're ready." },
    { reaction: "celebrate", line: "Session started. I'll keep count." },
  ],
  "workout-finished": [
    { reaction: "celebrate", line: "Session complete. You did the work." },
    { reaction: "laugh", line: "That's a wrap. Nice session." },
    { reaction: "relieved", line: "Finished and saved." },
  ],
  "plan-adjusted": [
    { reaction: "celebrate", line: "Week adjusted. The remaining work fits." },
    { reaction: "acknowledge", line: "Plan updated around what you logged." },
    { reaction: "wink", line: "Schedule reshaped. You're set." },
  ],
  "action-blocked": [
    { reaction: "frustrated", line: "That didn't work. Try once more." },
    { reaction: "recoil", line: "I couldn't save that change." },
    { reaction: "surprise", line: "Something got in the way." },
  ],
}

// The event name is private to the app, but exported for the runtime test and
// for integrations that live outside React.
export const RAUTA_CUE_EVENT = "rauta:cue"

let previousChoice: Partial<Record<RautaCue, number>> = {}

export function pickRautaResponse(
  cue: RautaCue,
  previous = previousChoice[cue],
  random: () => number = Math.random
): RautaResponse {
  const options = RESPONSES[cue]
  let index = Math.min(
    options.length - 1,
    Math.floor(random() * options.length)
  )
  if (options.length > 1 && index === previous)
    index = (index + 1) % options.length
  previousChoice[cue] = index
  return options[index]
}

export function cueRauta(cue: RautaCue) {
  if (typeof window === "undefined") return
  window.dispatchEvent(
    new CustomEvent<RautaCue>(RAUTA_CUE_EVENT, { detail: cue })
  )
}
