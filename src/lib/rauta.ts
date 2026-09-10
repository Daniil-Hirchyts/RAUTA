/**
 * What RAUTA can express, as a vocabulary rather than a pile of animation
 * names.
 *
 * The character rig exposes a mood number and a set of one-shot triggers. Those
 * are asset details: a screen should be able to say "the week was generated" or
 * "this set was hard" without knowing that `status` is 8 and that the trigger is
 * called `gearUp`. So the names live here once, the rig binding lives here once,
 * and every screen speaks in states.
 *
 * Every mood and reaction below exists in the artwork. Nothing is invented, and
 * nothing is mapped twice under a friendlier name.
 */

/** The resting expression. Held until something changes it. */
export type RautaMood =
  | "calm"
  | "curious"
  | "thinking"
  | "working"
  | "bored"
  | "blocked"
  | "sleepy"
  | "focused"
  | "excited"
  | "happy"
  | "proud"
  | "confused"
  | "skeptical"
  | "nervous"
  | "playful"
  | "listening"

/** A one-shot: something happens, RAUTA reacts, the mood underneath returns. */
export type RautaReaction =
  | "acknowledge"
  | "surprise"
  | "celebrate"
  | "frustrated"
  | "relieved"
  | "wobble"
  | "gearUp"
  | "laugh"
  | "tapped"
  | "recoil"
  | "peek"
  | "blink"
  | "blinkDouble"
  | "wink"
  | "spinLeft"
  | "spinRight"
  | "turnaround"

/** `status` values in the rig, in the artwork's own order. */
export const RAUTA_MOOD_STATUS: Record<RautaMood, number> = {
  calm: 0,
  curious: 1,
  thinking: 2,
  working: 3,
  bored: 4,
  blocked: 5,
  sleepy: 6,
  focused: 7,
  excited: 8,
  happy: 9,
  proud: 10,
  confused: 11,
  skeptical: 12,
  nervous: 13,
  playful: 14,
  listening: 15,
}

export const RAUTA_REACTIONS: readonly RautaReaction[] = [
  "acknowledge",
  "surprise",
  "celebrate",
  "frustrated",
  "relieved",
  "wobble",
  "gearUp",
  "laugh",
  "tapped",
  "recoil",
  "peek",
  "blink",
  "blinkDouble",
  "wink",
  "spinLeft",
  "spinRight",
  "turnaround",
]

/**
 * Who asked for the behaviour, and therefore who wins.
 *
 * The engine and the app have something to say and must never be talked over.
 * What the person is physically doing to the character comes next, because it
 * is still their action. Ambient idle is the character having a thought of its
 * own, and yields to both.
 */
export type RautaSource = "explicit" | "interaction" | "ambient"

const PRIORITY: Record<RautaSource, number> = {
  explicit: 3,
  interaction: 2,
  ambient: 1,
}

/** How long a source holds the floor after it plays, in milliseconds. */
const HOLD_MS: Record<RautaSource, number> = {
  // Long enough for the reaction to read as an answer to what just happened.
  explicit: 2600,
  interaction: 900,
  ambient: 700,
}

/** The shortest gap between two reactions from the same source. Without it a
 *  stream of pointer events becomes a stutter of restarted animations. */
const COOLDOWN_MS: Record<RautaSource, number> = {
  explicit: 260,
  interaction: 620,
  ambient: 2400,
}

/** Ambient idle picks a new delay in this range each time, so the character
 *  neither loops on a fixed beat nor fidgets constantly. */
export const RAUTA_IDLE_RANGE_MS = { min: 5200, max: 12_600 } as const

/** Small, unobtrusive things to do while nothing is happening. Weighted by
 *  repetition rather than by a table: a blink should be common and a spin
 *  should be rare. */
const AMBIENT_REACTIONS: readonly RautaReaction[] = [
  "blink",
  "blink",
  "blink",
  "blinkDouble",
  "peek",
  "blink",
  "wink",
  "blinkDouble",
  "peek",
  "acknowledge",
  "relieved",
  "laugh",
  "turnaround",
  "spinLeft",
  "blink",
  "spinRight",
]

export type RautaActivity = {
  /** The source that currently holds the floor, and until when. */
  holder: RautaSource | null
  holdUntil: number
  lastInteraction?: RautaReaction
  /** The previous idle beat, so random choice still never looks like a loop. */
  lastAmbient?: RautaReaction
  /** When each source last played, for its own cooldown. */
  lastPlayedAt: Record<RautaSource, number>
  /** When ambient idle is next allowed to have a thought. */
  ambientDueAt: number
}

export function createRautaActivity(now = 0): RautaActivity {
  return {
    holder: null,
    holdUntil: 0,
    lastPlayedAt: {
      explicit: -Infinity,
      interaction: -Infinity,
      ambient: -Infinity,
    },
    ambientDueAt: now + RAUTA_IDLE_RANGE_MS.min,
  }
}

/**
 * Whether a reaction gets to play, and the activity that follows.
 *
 * Pure: the clock and the randomness are arguments, so the same sequence of
 * requests always resolves the same way and a test never has to wait.
 *
 * A request is refused when a higher- or equal-priority source still holds the
 * floor, or when its own source is still cooling down. Refusing is the point —
 * it is what stops an idle blink from cutting off the celebration of a finished
 * week, and what stops every pointer move from restarting an animation.
 */
export function requestRautaReaction(
  activity: RautaActivity,
  request: { source: RautaSource; reaction: RautaReaction; now: number }
): { activity: RautaActivity; play: RautaReaction | null } {
  const { source, reaction, now } = request
  const holding =
    activity.holder !== null &&
    now < activity.holdUntil &&
    PRIORITY[activity.holder] >= PRIORITY[source] &&
    // A source never blocks itself out of continuing; only its cooldown does.
    activity.holder !== source
  const impactInterrupt =
    source === "interaction" &&
    (reaction === "recoil" || reaction === "wobble") &&
    (activity.lastInteraction === "surprise" ||
      activity.lastInteraction === "peek" ||
      activity.lastInteraction === "spinLeft" ||
      activity.lastInteraction === "spinRight")
  const cooling =
    !impactInterrupt &&
    now - activity.lastPlayedAt[source] < COOLDOWN_MS[source]
  if (holding || cooling) return { activity, play: null }

  return {
    activity: {
      ...activity,
      holder: source,
      lastInteraction:
        source === "interaction" ? reaction : activity.lastInteraction,
      holdUntil: now + HOLD_MS[source],
      lastPlayedAt: { ...activity.lastPlayedAt, [source]: now },
      // Anything happening pushes the character's own next thought back.
      ambientDueAt:
        source === "ambient"
          ? activity.ambientDueAt
          : now + RAUTA_IDLE_RANGE_MS.min,
    },
    play: reaction,
  }
}

/**
 * The character's next thought, when it is due and nothing else is going on.
 *
 * Returns null while a reaction still holds the floor or the next idle moment
 * has not arrived, so idle behaviour stays occasional. `random` is injected so
 * the choice and the next delay are reproducible in a test.
 */
export function scheduleRautaIdle(
  activity: RautaActivity,
  now: number,
  random: () => number = Math.random
): { activity: RautaActivity; play: RautaReaction | null } {
  if (now < activity.ambientDueAt) return { activity, play: null }

  const span = RAUTA_IDLE_RANGE_MS.max - RAUTA_IDLE_RANGE_MS.min
  const nextDueAt = now + RAUTA_IDLE_RANGE_MS.min + Math.floor(random() * span)
  const available = AMBIENT_REACTIONS.filter(
    (reaction) => reaction !== activity.lastAmbient
  )
  const choice =
    available[
      Math.min(available.length - 1, Math.floor(random() * available.length))
    ]

  const attempt = requestRautaReaction(
    { ...activity, ambientDueAt: nextDueAt },
    { source: "ambient", reaction: choice, now }
  )
  // Even when the floor is held, the next thought is rescheduled rather than
  // retried immediately: a blocked idle must not become a busy wait.
  return {
    activity: attempt.play
      ? { ...attempt.activity, lastAmbient: attempt.play }
      : { ...activity, ambientDueAt: nextDueAt },
    play: attempt.play,
  }
}
