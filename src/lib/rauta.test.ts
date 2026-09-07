import { describe, expect, it } from "vitest"

import {
  angleDelta,
  bounceInBounds,
  bounceStrength,
  clampToBounds,
  clampVelocity,
  MAX_THROW_VELOCITY,
  NO_ORIENTATION,
  orientationInfluence,
  rautaBounds,
  ROTATION_THRESHOLD_DEGREES,
  settleRotation,
  touchAngle,
} from "@/lib/rauta-motion"
import {
  createRautaActivity,
  RAUTA_IDLE_RANGE_MS,
  RAUTA_MOOD_STATUS,
  requestRautaReaction,
  scheduleRautaIdle,
} from "@/lib/rauta"

/**
 * RAUTA as behaviour rather than as frames.
 *
 * What matters about the character is what it is allowed to do: which reaction
 * wins, how often it may fidget, where it may go, how hard it may be thrown and
 * how much a tilted phone is worth. All of that is arithmetic, so it is tested
 * directly instead of through animation snapshots that would break on any
 * re-timing of the artwork.
 */

describe("what RAUTA is allowed to express", () => {
  it("names only moods the artwork really has", () => {
    // The rig numbers its moods 0–15; nothing here may point outside that.
    const values = Object.values(RAUTA_MOOD_STATUS)
    expect(new Set(values).size).toBe(values.length)
    for (const value of values) {
      expect(Number.isInteger(value)).toBe(true)
      expect(value).toBeGreaterThanOrEqual(0)
      expect(value).toBeLessThanOrEqual(15)
    }
  })

  it("does not let an idle thought talk over the engine", () => {
    let activity = createRautaActivity(0)
    const explicit = requestRautaReaction(activity, {
      source: "explicit",
      reaction: "celebrate",
      now: 1000,
    })
    expect(explicit.play).toBe("celebrate")
    activity = explicit.activity

    const ambient = requestRautaReaction(activity, {
      source: "ambient",
      reaction: "blink",
      now: 1200,
    })
    expect(ambient.play).toBeNull()

    // Once the reaction has had its moment, the character is its own again.
    const later = requestRautaReaction(ambient.activity, {
      source: "ambient",
      reaction: "blink",
      now: 1000 + 4000,
    })
    expect(later.play).toBe("blink")
  })

  it("lets what the person is doing outrank an idle thought but not the engine", () => {
    let activity = createRautaActivity(0)
    activity = requestRautaReaction(activity, {
      source: "ambient",
      reaction: "blink",
      now: 100,
    }).activity

    // A finger arrives mid-blink and wins.
    const touch = requestRautaReaction(activity, {
      source: "interaction",
      reaction: "tapped",
      now: 200,
    })
    expect(touch.play).toBe("tapped")

    // The engine arrives mid-touch and wins again.
    const engine = requestRautaReaction(touch.activity, {
      source: "explicit",
      reaction: "gearUp",
      now: 300,
    })
    expect(engine.play).toBe("gearUp")
  })

  it("refuses a second reaction from one source until it has cooled down", () => {
    let activity = createRautaActivity(0)
    const first = requestRautaReaction(activity, {
      source: "interaction",
      reaction: "wobble",
      now: 0,
    })
    expect(first.play).toBe("wobble")
    activity = first.activity

    // A stream of pointer events must not become a stutter of restarts.
    for (const now of [40, 120, 300, 500]) {
      const attempt = requestRautaReaction(activity, {
        source: "interaction",
        reaction: "wobble",
        now,
      })
      expect(attempt.play).toBeNull()
      activity = attempt.activity
    }
    expect(
      requestRautaReaction(activity, {
        source: "interaction",
        reaction: "wobble",
        now: 900,
      }).play
    ).toBe("wobble")
  })

  it("has an occasional thought rather than a permanent loop", () => {
    const random = () => 0.5
    let activity = createRautaActivity(0)
    let played = 0
    const idleAt: number[] = []

    // Twenty seconds of a screen nobody is touching, polled every second.
    for (let now = 0; now <= 20_000; now += 1000) {
      const outcome = scheduleRautaIdle(activity, now, random)
      activity = outcome.activity
      if (outcome.play) {
        played += 1
        idleAt.push(now)
      }
    }

    expect(played).toBeGreaterThan(0)
    // Occasional, not constant: never more often than the range allows.
    for (let index = 1; index < idleAt.length; index += 1)
      expect(idleAt[index] - idleAt[index - 1]).toBeGreaterThanOrEqual(
        RAUTA_IDLE_RANGE_MS.min
      )
    expect(played).toBeLessThan(20_000 / RAUTA_IDLE_RANGE_MS.min + 1)
  })

  it("varies what it does rather than repeating one animation", () => {
    let activity = createRautaActivity(0)
    const seen = new Set<string>()
    let seed = 0
    const random = () => {
      seed = (seed * 9301 + 49297) % 233280
      return seed / 233280
    }
    for (let now = 0; now <= 400_000; now += 1000) {
      const outcome = scheduleRautaIdle(activity, now, random)
      activity = outcome.activity
      if (outcome.play) seen.add(outcome.play)
    }
    expect(seen.size).toBeGreaterThan(2)
  })

  it("reschedules rather than spinning when a thought is blocked", () => {
    let activity = createRautaActivity(0)
    activity = requestRautaReaction(activity, {
      source: "explicit",
      reaction: "celebrate",
      now: 100_000,
    }).activity
    const due = activity.ambientDueAt

    const blocked = scheduleRautaIdle(
      { ...activity, ambientDueAt: 100_100 },
      100_100,
      () => 0.5
    )
    expect(blocked.play).toBeNull()
    // The next attempt is pushed out, so a blocked idle is not a busy wait.
    expect(blocked.activity.ambientDueAt).toBeGreaterThan(100_100)
    expect(due).toBeGreaterThan(100_000)
  })
})

describe("where RAUTA can go", () => {
  const phone = (width: number) => ({
    rect: { left: width - 120, top: 500, width: 104, height: 104 },
    viewport: { width, height: 844 },
    inset: { bottom: 96, top: 12, left: 8, right: 8 },
  })

  it.each([320, 390, 430])("gives real room on a %ipx screen", (width) => {
    const bounds = rautaBounds(phone(width))
    // Substantially more than the old fixed 38/24 px box, in every direction.
    expect(bounds.right - bounds.left).toBeGreaterThan(width * 0.5)
    expect(bounds.bottom - bounds.top).toBeGreaterThan(300)
    expect(bounds.left).toBeLessThan(0)
    expect(bounds.top).toBeLessThan(0)
  })

  it("always leaves enough of the body on screen to grab", () => {
    const input = phone(390)
    const bounds = rautaBounds(input)
    for (const corner of [
      { x: bounds.left, y: bounds.top },
      { x: bounds.right, y: bounds.bottom },
    ]) {
      const left = input.rect.left + corner.x
      const top = input.rect.top + corner.y
      const visibleX =
        Math.min(left + input.rect.width, input.viewport.width) -
        Math.max(left, 0)
      const visibleY =
        Math.min(top + input.rect.height, input.viewport.height) -
        Math.max(top, 0)
      expect(visibleX).toBe(input.rect.width)
      expect(visibleY).toBe(input.rect.height)
    }
  })

  it("keeps every position inside the allowed box", () => {
    const bounds = { left: -100, right: 100, top: -50, bottom: 50 }
    expect(clampToBounds({ x: 9999, y: 9999 }, bounds)).toEqual({
      x: 100,
      y: 50,
    })
    expect(clampToBounds({ x: -9999, y: -9999 }, bounds)).toEqual({
      x: -100,
      y: -50,
    })
  })

  it("does not invert its bounds on a screen smaller than the character", () => {
    const bounds = rautaBounds({
      rect: { left: 0, top: 0, width: 300, height: 300 },
      viewport: { width: 200, height: 200 },
    })
    expect(bounds.right).toBeGreaterThanOrEqual(bounds.left)
    expect(bounds.bottom).toBeGreaterThanOrEqual(bounds.top)
  })
})

describe("being thrown", () => {
  const bounds = { left: -100, right: 100, top: -100, bottom: 100 }

  it("caps how hard the character can be flung", () => {
    const clamped = clampVelocity({ x: 12_000, y: -9000 })
    expect(Math.hypot(clamped.x, clamped.y)).toBeCloseTo(MAX_THROW_VELOCITY, 5)
    // Direction is preserved; only the speed is limited.
    expect(Math.sign(clamped.x)).toBe(1)
    expect(Math.sign(clamped.y)).toBe(-1)
  })

  it("leaves an ordinary throw untouched", () => {
    expect(clampVelocity({ x: 300, y: 200 })).toEqual({ x: 300, y: 200 })
  })

  it("turns the character around at an edge and takes speed out of it", () => {
    const result = bounceInBounds({ x: 180, y: 0 }, { x: 800, y: 0 }, bounds)
    expect(result.position.x).toBe(100)
    // It comes back, slower than it arrived.
    expect(result.velocity.x).toBeLessThan(0)
    expect(Math.abs(result.velocity.x)).toBeLessThan(800)
    expect(result.hit).toEqual(["right"])
    expect(result.impact).toBe(800)
  })

  it("bounces off a corner on both axes at once", () => {
    const result = bounceInBounds(
      { x: 300, y: 300 },
      { x: 900, y: 900 },
      bounds
    )
    expect(result.position).toEqual({ x: 100, y: 100 })
    expect(result.hit).toEqual(["right", "bottom"])
    expect(result.velocity.x).toBeLessThan(0)
    expect(result.velocity.y).toBeLessThan(0)
  })

  it("comes to rest instead of rattling forever", () => {
    const result = bounceInBounds({ x: 101, y: 0 }, { x: 30, y: 0 }, bounds)
    expect(result.velocity).toEqual({ x: 0, y: 0 })
    expect(result.position.x).toBe(100)
  })

  it("only reacts to a collision worth noticing", () => {
    expect(bounceStrength(120)).toBe("none")
    expect(bounceStrength(700)).toBe("soft")
    expect(bounceStrength(1600)).toBe("hard")
  })
})

describe("turning RAUTA", () => {
  it("measures a twist between two fingers", () => {
    expect(touchAngle({ x: 0, y: 0 }, { x: 10, y: 0 })).toBe(0)
    expect(touchAngle({ x: 0, y: 0 }, { x: 0, y: 10 })).toBe(90)
  })

  it("takes the short way round rather than spinning at the seam", () => {
    expect(angleDelta(350, 10)).toBe(20)
    expect(angleDelta(10, 350)).toBe(-20)
  })

  it("ignores two fingers that are not actually twisting", () => {
    // Resting a second finger on the character shifts the angle a little; that
    // is below the threshold and must not turn anything.
    const drift = angleDelta(0, ROTATION_THRESHOLD_DEGREES - 2)
    expect(Math.abs(drift)).toBeLessThan(ROTATION_THRESHOLD_DEGREES)
  })

  it("settles on a quarter turn when released", () => {
    expect(settleRotation(43)).toBe(0)
    expect(settleRotation(50)).toBe(90)
    expect(settleRotation(-10)).toBe(0)
    expect(settleRotation(315)).toBe(0)
  })
})

describe("tilting the phone", () => {
  it("does nothing at all for a hand that is not quite level", () => {
    const influence = orientationInfluence(NO_ORIENTATION, {
      beta: 3,
      gamma: -2,
    })
    expect(influence).toEqual(NO_ORIENTATION)
  })

  it("keeps the effect small however far the phone is turned", () => {
    let influence = NO_ORIENTATION
    // Settle fully against an extreme reading.
    for (let index = 0; index < 400; index += 1)
      influence = orientationInfluence(influence, { beta: 90, gamma: 90 })
    expect(Math.abs(influence.x)).toBeLessThanOrEqual(9)
    expect(Math.abs(influence.y)).toBeLessThanOrEqual(9)
    expect(Math.abs(influence.lean)).toBeLessThanOrEqual(5)
  })

  it("eases toward a new reading instead of snapping to it", () => {
    const first = orientationInfluence(NO_ORIENTATION, { beta: 0, gamma: 40 })
    const second = orientationInfluence(first, { beta: 0, gamma: 40 })
    expect(Math.abs(first.x)).toBeGreaterThan(0)
    // Still travelling toward the target rather than already there.
    expect(Math.abs(second.x)).toBeGreaterThan(Math.abs(first.x))
    expect(Math.abs(first.x)).toBeLessThan(9)
  })

  it("treats an unsupported sensor as a level phone", () => {
    // `deviceorientation` reports nulls where the hardware has nothing to say.
    expect(
      orientationInfluence(NO_ORIENTATION, { beta: null, gamma: null })
    ).toEqual(NO_ORIENTATION)
    expect(
      orientationInfluence(NO_ORIENTATION, { beta: NaN, gamma: NaN })
    ).toEqual(NO_ORIENTATION)
  })
})

it("lets an edge impact follow a throw reaction without repeated collision spam", () => {
  const thrown = requestRautaReaction(createRautaActivity(), {
    source: "interaction",
    reaction: "surprise",
    now: 1000,
  })
  const hit = requestRautaReaction(thrown.activity, {
    source: "interaction",
    reaction: "recoil",
    now: 1100,
  })
  expect(hit.play).toBe("recoil")
  expect(
    requestRautaReaction(hit.activity, {
      source: "interaction",
      reaction: "recoil",
      now: 1120,
    }).play
  ).toBeNull()
})
