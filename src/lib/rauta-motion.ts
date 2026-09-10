/**
 * The physical side of RAUTA: where it can go, how hard it can be thrown, and
 * what a twist or a tilt is worth.
 *
 * All of it is arithmetic on plain numbers, kept out of the component so it can
 * be reasoned about and tested without a frame loop. The hook that uses this
 * owns the motion values and the listeners; nothing here touches the DOM, the
 * clock or React.
 *
 * The rules it enforces are the ones that keep the character usable: it stays
 * reachable inside the screen, a hard swipe cannot fling it out of the app, and
 * a tilted phone nudges rather than slides.
 */

export type Point = { x: number; y: number }

/** How far the character may travel from where it sits in the layout, measured
 *  in the four directions separately because the space around it is not
 *  symmetrical — a bottom navigation bar takes room the top does not. */
export type RautaBounds = {
  left: number
  right: number
  top: number
  bottom: number
}

/** Everything measured about the screen the character lives in. Nothing here
 *  is assumed: the caller reads it from the real element and viewport. */
export type RautaBoundsInput = {
  /** The character's own box, in viewport coordinates, at rest. */
  rect: { left: number; top: number; width: number; height: number }
  /** The box the character lives in — the app's own frame where there is one,
   *  which on a phone is the whole screen and on a wider display is the shell.
   *  `left`/`top` default to the viewport origin. */
  viewport: { width: number; height: number; left?: number; top?: number }
  /** Safe-area and chrome to stay clear of. */
  inset?: { top?: number; right?: number; bottom?: number; left?: number }
}

/** Full-body travel bounds, including the envelope supplied by the renderer. */
export function rautaBounds(input: RautaBoundsInput): RautaBounds {
  const { rect, viewport } = input
  const inset = {
    top: input.inset?.top ?? 0,
    right: input.inset?.right ?? 0,
    bottom: input.inset?.bottom ?? 0,
    left: input.inset?.left ?? 0,
  }

  const originX = viewport.left ?? 0
  const originY = viewport.top ?? 0
  const minX = originX + inset.left
  const maxX = originX + viewport.width - inset.right - rect.width
  const minY = originY + inset.top
  const maxY = originY + viewport.height - inset.bottom - rect.height

  return {
    // A viewport too small for the character in some direction collapses that
    // direction to zero rather than inverting it.
    left: minX - rect.left,
    right: Math.max(minX, maxX) - rect.left,
    top: minY - rect.top,
    bottom: Math.max(minY, maxY) - rect.top,
  }
}

export function clampToBounds(point: Point, bounds: RautaBounds): Point {
  return {
    x: Math.min(bounds.right, Math.max(bounds.left, point.x)),
    y: Math.min(bounds.bottom, Math.max(bounds.top, point.y)),
  }
}

/** The hardest throw the character will accept, in px/s. A swipe can be much
 *  faster than this; past the cap the extra speed only makes the motion hard to
 *  follow and the collision violent. */
export const MAX_THROW_VELOCITY = 1900

export function clampVelocity(
  velocity: Point,
  max = MAX_THROW_VELOCITY
): Point {
  const speed = Math.hypot(velocity.x, velocity.y)
  if (speed <= max || speed === 0) return { ...velocity }
  const scale = max / speed
  return { x: velocity.x * scale, y: velocity.y * scale }
}

/** How much speed survives hitting an edge. Enough to read as a bounce, little
 *  enough that the character settles rather than rattling between two walls. */
const RESTITUTION = 0.42

/** Below this the bounce is not worth playing; the character just stops. */
const BOUNCE_FLOOR = 90

export type BounceResult = {
  position: Point
  velocity: Point
  /** Which edges were hit, for the reaction the character plays. */
  hit: ("left" | "right" | "top" | "bottom")[]
  /** Impact speed against the edge, for choosing how strongly to react. */
  impact: number
}

/**
 * One collision against the walls.
 *
 * The position is put back inside, and the component of the velocity that was
 * heading out is reversed and damped. Both axes are handled, so a corner hit
 * bounces off the corner rather than off whichever wall was tested first.
 */
export function bounceInBounds(
  position: Point,
  velocity: Point,
  bounds: RautaBounds,
  restitution = RESTITUTION
): BounceResult {
  const hit: BounceResult["hit"] = []
  let { x, y } = position
  let vx = velocity.x
  let vy = velocity.y
  let impact = 0

  if (x < bounds.left) {
    impact = Math.max(impact, Math.abs(vx))
    x = bounds.left
    vx = Math.abs(vx) * restitution
    hit.push("left")
  } else if (x > bounds.right) {
    impact = Math.max(impact, Math.abs(vx))
    x = bounds.right
    vx = -Math.abs(vx) * restitution
    hit.push("right")
  }
  if (y < bounds.top) {
    impact = Math.max(impact, Math.abs(vy))
    y = bounds.top
    vy = Math.abs(vy) * restitution
    hit.push("top")
  } else if (y > bounds.bottom) {
    impact = Math.max(impact, Math.abs(vy))
    y = bounds.bottom
    vy = -Math.abs(vy) * restitution
    hit.push("bottom")
  }

  if (Math.hypot(vx, vy) < BOUNCE_FLOOR) {
    vx = 0
    vy = 0
  }
  return { position: { x, y }, velocity: { x: vx, y: vy }, hit, impact }
}

/** How hard a collision felt. Only a real thump is worth an animation. */
export function bounceStrength(impact: number): "none" | "soft" | "hard" {
  if (impact < 420) return "none"
  return impact < 1100 ? "soft" : "hard"
}

export type OrientationSample = {
  /** Front-to-back tilt in degrees, as `deviceorientation` reports it. */
  beta: number | null
  /** Left-to-right tilt in degrees. */
  gamma: number | null
}

export type OrientationInfluence = { x: number; y: number; lean: number }

const ORIENTATION_DEAD_ZONE = 4
const ORIENTATION_RANGE = 26
/** Deliberately small. The character leans with the phone; it does not slide
 *  around because somebody is holding it at an angle. */
const ORIENTATION_SHIFT_PX = 9
const ORIENTATION_LEAN_DEGREES = 5
const ORIENTATION_SMOOTHING = 0.12

function tilt(value: number | null) {
  if (value === null || !Number.isFinite(value)) return 0
  const magnitude = Math.abs(value)
  if (magnitude <= ORIENTATION_DEAD_ZONE) return 0
  const scaled =
    (magnitude - ORIENTATION_DEAD_ZONE) /
    (ORIENTATION_RANGE - ORIENTATION_DEAD_ZONE)
  return Math.sign(value) * Math.min(1, scaled)
}

/**
 * How far a tilted phone nudges the character, smoothed toward the new reading.
 *
 * Dead zone first, so a hand that is not quite level does nothing at all. Then
 * clamped, so the influence has a ceiling however far the phone is turned. Then
 * eased toward, so a jittery sensor does not become a jittery character. An
 * absent or unsupported reading resolves to no influence, which is the same
 * thing as a level phone — the character keeps working either way.
 */
export function orientationInfluence(
  previous: OrientationInfluence,
  sample: OrientationSample,
  smoothing = ORIENTATION_SMOOTHING
): OrientationInfluence {
  const gamma = tilt(sample.gamma)
  const beta = tilt(sample.beta)
  const target = {
    x: gamma * ORIENTATION_SHIFT_PX,
    y: beta * ORIENTATION_SHIFT_PX,
    lean: gamma * ORIENTATION_LEAN_DEGREES,
  }
  const ease = Math.min(1, Math.max(0, smoothing))
  return {
    x: previous.x + (target.x - previous.x) * ease,
    y: previous.y + (target.y - previous.y) * ease,
    lean: previous.lean + (target.lean - previous.lean) * ease,
  }
}

export const NO_ORIENTATION: OrientationInfluence = { x: 0, y: 0, lean: 0 }

/** How far the character may be taken from its own place at all. It is on a
 *  short leash: far enough to be picked up, played with and thrown, never far
 *  enough to be lost on the other side of the screen. */
export const MAX_TRAVEL = 132

/** Keeps a point inside the leash, along the direction it was pulled. */
export function clampTravel(point: Point, max = MAX_TRAVEL): Point {
  const distance = Math.hypot(point.x, point.y)
  if (distance <= max || distance === 0) return { ...point }
  const scale = max / distance
  return { x: point.x * scale, y: point.y * scale }
}

/** Let go this close to where it belongs and the character is pulled back with
 *  no pause at all: nobody means to park it a centimetre from its own place. */
export const HOME_MAGNET_RADIUS = 96

/**
 * How long the character is left where it was put before the pull home starts.
 *
 * Short on purpose. However long it was carried and however hard it was thrown,
 * it belongs in one place, and a character that lingers where it was dropped
 * reads as one that has been left there. Far enough to be worth seeing land, it
 * waits a beat; near home it does not wait at all.
 */
export function homeReturnDelay(distance: number) {
  return distance <= HOME_MAGNET_RADIUS ? 0 : 200
}
