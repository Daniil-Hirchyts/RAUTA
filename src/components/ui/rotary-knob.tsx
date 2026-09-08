import {
  useId,
  useRef,
  useState,
  type KeyboardEvent,
  type PointerEvent,
} from "react"

import { AnimatedNumber } from "@/components/animated-number"
import { triggerHaptic } from "@/lib/haptics"
import { cn, snapToRange } from "@/lib/utils"

/**
 * A dial for a number that would otherwise need a keyboard.
 *
 * Only the crown of the wheel is on screen: the rim of a wheel that carries
 * on below the screen, notches cut into its outer edge, and a fixed marker at
 * the top — so the notch under the marker is the value you have. Turning it is
 * the whole point — a phone keyboard covers half the screen to collect two
 * digits, and every number this app asks for (an age, how long a session
 * should run, a load step) is one you nudge rather than type. The notches
 * follow the finger, so the gesture is a push on a wheel rather than a value
 * to aim at, and where the scale runs past what the dial will accept those
 * notches are drawn faint, when the caller paints one that wide. Hardware
 * keyboards and assistive technology drive the same value through ARIA
 * slider semantics.
 *
 * Nothing is drawn but the notches: no rim, no face, no numbers along the
 * band — a wheel painted under them is a shape to cut off at the edge of the
 * screen, and the notches alone already say which way it is turning.
 *
 * The number is read above the band and the two nudge buttons sit in the
 * hollow under it, which is the arrangement that fits: the wheel is the
 * bottom of the screen, the answer is the line above it, and nothing is
 * stacked underneath asking for room a phone does not have.
 */

/** The drawing is laid out in these units and scaled to whatever width the
 *  caller asks for; everything below is in them. */
const VIEWBOX_W = 240
const VIEWBOX_H = 84

/** The wheel is mostly below the box. A radius this much wider than the box
 *  is what leaves an arc rather than a circle; the two go together, since the
 *  radius is what decides how much of the wheel reaches the box's edges. The
 *  rim is high in the box and the face fills the rest, so the notches have the
 *  room they need and the buttons have somewhere to sit. */
const ARC_RADIUS = 162
/** Where the band sits in the box. What is left underneath is the hollow the
 *  two nudge buttons live in. */
const ARC_TOP = 28
const CENTER_X = VIEWBOX_W / 2
const CENTER_Y = ARC_TOP + ARC_RADIUS
const EDGE_DEGREES = 48

/** The marker stands proud of the band so it reads as pointing at it. */
const MARKER_RISE = 7

/** No numbers anywhere on the band — the value has already been said, in
 *  full, on the line above it. Every fifth notch is drawn longer all the
 *  same: a band of identical marks slides without appearing to move, and the
 *  long ones are what the eye counts as the wheel turns. */
const TICK = 9
const MAJOR_TICK = 16
const MAJOR_EVERY = 5

/** How far apart the notches sit, kept between these so a short range does
 *  not bunch into a smear and a long one still turns at a readable pace. */
const MIN_TICK_DEGREES = 3
const MAX_TICK_DEGREES = 9

/** A small dial has a short arc, and tracking it exactly would spend a whole
 *  range in a thumb's width; below this the wheel turns slower than the
 *  finger instead. */
const MIN_PIXELS_PER_NOTCH = 10

function polar(degrees: number, radius: number) {
  // 0° points at 12 o'clock and grows clockwise, the way the band is read.
  const radians = ((degrees - 90) * Math.PI) / 180
  return {
    x: CENTER_X + radius * Math.cos(radians),
    y: CENTER_Y + radius * Math.sin(radians),
  }
}

/** Shortest way round from one angle to another, so a drag never counts as
 *  most of a turn. */
function angleDelta(from: number, to: number) {
  return ((((to - from) % 360) + 540) % 360) - 180
}

/** Where the hollow starts, in per cent of the box's height: everything below
 *  the band is the two nudge areas, everything above it — which is the band
 *  itself, right across the dial — is the turn. */
const STEP_AREA_TOP = 52

const STEP_BUTTON =
  "pointer-events-auto flex flex-1 items-center justify-center font-light text-foreground/70 transition-colors duration-150 active:text-primary disabled:opacity-25"

/** How far down the box the marker's light is centred, and so how far it may
 *  reach: an ellipse that tall ends exactly at the top edge of the box, at
 *  the radius where the wash has already faded to nothing. Any taller and the
 *  viewBox cuts it, which draws a straight line of light across the top. */
const GLOW_CENTER_Y = ARC_TOP - 4

/** The marker crosses the notches and stops just past the band, so it reads
 *  as resting on the wheel rather than floating over it. */
const MARKER_TOP = ARC_TOP - MAJOR_TICK - MARKER_RISE
const MARKER_BOTTOM = ARC_TOP + 4

export function RotaryKnob({
  ariaLabel,
  className,
  disabled = false,
  format = String,
  label,
  max,
  min,
  onChange,
  scaleMax,
  scaleMin,
  size = 480,
  step = 1,
  unit,
  value,
}: {
  ariaLabel: string
  className?: string
  disabled?: boolean
  format?: (value: number) => string
  label?: string
  max: number
  min: number
  onChange: (value: number) => void
  /** How much of the wheel is painted, when that is more than the dial will
   *  accept. Numbers like an age read better against the whole scale they
   *  belong to, with the part that is out of bounds greyed rather than
   *  missing. Defaults to the accepted range itself. */
  scaleMax?: number
  scaleMin?: number
  /** The widest the dial will draw itself; it takes the room it is given up
   *  to this. */
  size?: number
  step?: number
  unit?: string
  value: number
}) {
  // Two dials on one page must not both answer to the same paint server, and
  // React's generated ids carry colons an SVG reference cannot use.
  const paintId = `rotary-knob-${useId().replace(/:/g, "")}`
  const [dragging, setDragging] = useState(false)
  const [focused, setFocused] = useState(false)
  const gesture = useRef<{
    angle: number
    notches: number
    pointerId: number
    value: number
  } | null>(null)

  const range = { max, min, step }
  const isCompact = size < 300
  const current = snapToRange(value, range)
  const scaleFrom = Math.min(scaleMin ?? min, min)
  const scaleTo = Math.max(scaleMax ?? max, max)
  const notchCount = step > 0 ? Math.round((scaleTo - scaleFrom) / step) : 0
  const notch = Math.round((current - scaleFrom) / (step || 1))
  const lowNotch = Math.round((min - scaleFrom) / (step || 1))
  const highNotch = Math.round((max - scaleFrom) / (step || 1))
  const tickDegrees =
    notchCount > 0
      ? Math.min(
          MAX_TICK_DEGREES,
          Math.max(MIN_TICK_DEGREES, (EDGE_DEGREES * 2) / notchCount)
        )
      : MAX_TICK_DEGREES
  // Only the notches that can reach the visible band are drawn, so a range of
  // hundreds of steps costs the same as a range of ten.
  const visibleNotches = Math.ceil(EDGE_DEGREES / tickDegrees) + 1

  const commit = (next: number) => {
    const snapped = snapToRange(next, range)
    if (snapped === current) return
    // One tick per notch: the dial should feel like it is passing over
    // something rather than sliding.
    triggerHaptic("selection")
    onChange(snapped)
  }

  /** Where the pointer sits on the wheel, and how big the wheel currently is
   *  on screen — both read off the box the dial was laid out in. */
  const readPointer = (event: PointerEvent<HTMLDivElement>) => {
    const bounds = event.currentTarget.getBoundingClientRect()
    if (bounds.width === 0) return null
    const scale = bounds.width / VIEWBOX_W
    const dx = event.clientX - (bounds.left + CENTER_X * scale)
    const dy = event.clientY - (bounds.top + CENTER_Y * scale)
    if (dx === 0 && dy === 0) return null
    return {
      angle: (Math.atan2(dx, -dy) * 180) / Math.PI,
      radius: ARC_RADIUS * scale,
    }
  }

  const onPointerDown = (event: PointerEvent<HTMLDivElement>) => {
    if (disabled || event.button > 0) return
    const pointer = readPointer(event)
    if (!pointer) return
    // The dial owns this gesture from here: `touch-none` already keeps the
    // page from scrolling under the finger, and capture keeps the value
    // tracking once the finger wanders outside the band.
    try {
      event.currentTarget.setPointerCapture(event.pointerId)
    } catch {
      // Capture is an enhancement; the drag still works without it.
    }
    gesture.current = {
      angle: pointer.angle,
      notches: 0,
      pointerId: event.pointerId,
      value: current,
    }
    setDragging(true)
    event.currentTarget.focus({ preventScroll: true })
  }

  const endGesture = (event: PointerEvent<HTMLDivElement>) => {
    if (gesture.current?.pointerId !== event.pointerId) return
    gesture.current = null
    setDragging(false)
  }

  const onPointerMove = (event: PointerEvent<HTMLDivElement>) => {
    const state = gesture.current
    if (!state || state.pointerId !== event.pointerId) return
    // A pointer that is no longer held is not turning anything: a release the
    // dial never saw — capture lost to another window, a touch cancelled —
    // would otherwise leave it tracking every stray move across the band.
    if (event.buttons === 0) {
      endGesture(event)
      return
    }
    const pointer = readPointer(event)
    if (!pointer) return
    event.preventDefault()

    const turned = angleDelta(state.angle, pointer.angle)
    state.angle = pointer.angle

    const travelled = (turned * Math.PI * pointer.radius) / 180
    const perNotch = Math.max(
      MIN_PIXELS_PER_NOTCH,
      (pointer.radius * tickDegrees * Math.PI) / 180
    )
    // The strip goes with the finger: pushing it right brings the notches on
    // its left — the lower ones — under the marker.
    state.notches = Math.min(
      (max - state.value) / step,
      // Held at the range's own edge rather than allowed to wind up past it,
      // so turning back answers on the first notch.
      Math.max((min - state.value) / step, state.notches - travelled / perNotch)
    )

    commit(state.value + state.notches * step)
  }

  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (disabled) return
    const coarse = step * 5
    const moves: Record<string, number | undefined> = {
      ArrowUp: step,
      ArrowRight: step,
      ArrowDown: -step,
      ArrowLeft: -step,
      PageUp: coarse,
      PageDown: -coarse,
    }
    if (event.key === "Home" || event.key === "End") {
      event.preventDefault()
      commit(event.key === "Home" ? min : max)
      return
    }
    const delta = moves[event.key]
    if (delta === undefined) return
    event.preventDefault()
    commit(current + delta)
  }

  const ticks: {
    key: number
    major: boolean
    opacity: number
    tint: number
    x1: number
    x2: number
    y1: number
    y2: number
  }[] = []
  for (
    let index = Math.max(0, notch - visibleNotches);
    index <= Math.min(notchCount, notch + visibleNotches);
    index += 1
  ) {
    const offset = (index - notch) * tickDegrees
    if (Math.abs(offset) > EDGE_DEGREES) continue
    // Past the ends the wheel still turns under the finger, so the notches it
    // will not stop on are drawn faint rather than left out.
    const blocked = index < lowNotch || index > highNotch
    // Absolute angles inside a rotated group, so the whole strip is one
    // transform away from where it was and can be animated as a piece.
    const angle = index * tickDegrees
    const major = index % MAJOR_EVERY === 0
    // Cut into the outside of the rim, so the hollow below stays clear for
    // the buttons and the number has the space above.
    const inner = polar(angle, ARC_RADIUS)
    const outer = polar(angle, ARC_RADIUS + (major ? MAJOR_TICK : TICK))
    const reach = Math.abs(offset) / EDGE_DEGREES
    ticks.push({
      key: index,
      major,
      // Full strength until the band is nearly at the edge of the box, then
      // gone, so it reads as curving away rather than being cut short.
      opacity:
        (major ? 0.85 : 0.45) *
        (blocked ? 0.3 : 1) *
        Math.min(1, Math.max(0, (1 - reach) / 0.3)),
      // The notches warm up as they come under the marker, so the value you
      // have is lit and the ones you are heading for are not.
      tint: blocked ? 0 : Math.max(0, 1 - reach * 1.8),
      x1: inner.x,
      x2: outer.x,
      y1: inner.y,
      y2: outer.y,
    })
  }

  return (
    <div
      className={cn(
        "flex flex-col items-center",
        isCompact ? "gap-1" : "gap-2",
        className
      )}
    >
      {label ? (
        <p className="text-xs font-bold tracking-[0.16em] text-muted-foreground uppercase">
          {label}
        </p>
      ) : null}
      {/* The answer reads above the wheel, where the marker points back at
          it, rather than in a hollow the buttons then have to sit beneath. */}
      <span
        className={cn(
          "pointer-events-none flex flex-col items-center",
          disabled && "opacity-50"
        )}
      >
        <span
          className={cn(
            "font-readout font-black tracking-[-0.03em] tabular-nums",
            isCompact ? "text-3xl" : "text-[3.25rem]",
            // Last, and on purpose: a Tailwind size class carries a line
            // height of its own, so a leading set before it is dropped and
            // the readout keeps half a line of air it does not have.
            "leading-none"
          )}
        >
          <AnimatedNumber format={format} still={dragging} value={current} />
        </span>
        {unit ? (
          <span
            className={cn(
              "font-bold text-muted-foreground uppercase",
              isCompact
                ? "mt-1 text-[10px] tracking-[0.14em]"
                : "mt-1.5 text-xs tracking-[0.18em]"
            )}
          >
            {unit}
          </span>
        ) : null}
      </span>
      <div className="relative w-full" style={{ maxWidth: size }}>
        <div
          aria-disabled={disabled || undefined}
          aria-label={ariaLabel}
          aria-valuemax={max}
          aria-valuemin={min}
          aria-valuenow={current}
          aria-valuetext={unit ? `${format(current)} ${unit}` : format(current)}
          className={cn(
            "relative w-full touch-none outline-none select-none",
            disabled && "opacity-50"
          )}
          data-dragging={dragging ? "true" : undefined}
          data-slot="rotary-knob"
          // The dial reads a drag of its own; the shell's edge-swipe navigation
          // and the direct-touch haptic overlay both stay out of it.
          data-swipe-ignore
          onBlur={() => setFocused(false)}
          // A ring drawn round a band this wide reads as a box someone put on
          // the screen; the marker's own light comes up instead.
          onFocus={(event) => {
            try {
              setFocused(event.currentTarget.matches(":focus-visible"))
            } catch {
              setFocused(true)
            }
          }}
          onKeyDown={onKeyDown}
          onLostPointerCapture={endGesture}
          onPointerCancel={endGesture}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={endGesture}
          role="slider"
          // Wide as the space allows, up to what the caller asked for: the
          // band is read across, and the geometry scales off the box it lands
          // in rather than a fixed width.
          style={{ aspectRatio: `${VIEWBOX_W} / ${VIEWBOX_H}` }}
          tabIndex={disabled ? -1 : 0}
        >
          <svg
            aria-hidden="true"
            className="absolute inset-0 h-full w-full"
            viewBox={`0 0 ${VIEWBOX_W} ${VIEWBOX_H}`}
          >
            <defs>
              <linearGradient
                gradientUnits="userSpaceOnUse"
                id={`${paintId}-marker`}
                x1="0"
                x2="0"
                y1={MARKER_TOP}
                y2={MARKER_BOTTOM}
              >
                <stop offset="0%" stopColor="var(--primary-gradient-start)" />
                <stop offset="100%" stopColor="var(--primary-gradient-end)" />
              </linearGradient>
              <radialGradient id={`${paintId}-glow`}>
                <stop
                  offset="0%"
                  stopColor="var(--primary)"
                  stopOpacity="0.34"
                />
                <stop
                  offset="55%"
                  stopColor="var(--primary)"
                  stopOpacity="0.12"
                />
                <stop
                  offset="100%"
                  stopColor="var(--primary)"
                  stopOpacity="0"
                />
              </radialGradient>
            </defs>
            {/* The marker's own light, cast on the band it sits over. It
                grows sideways when the dial is being turned; how far it
                reaches upward is fixed, for the reason above. */}
            <ellipse
              className="transition-all duration-300"
              cx={CENTER_X}
              cy={GLOW_CENTER_Y}
              fill={`url(#${paintId}-glow)`}
              opacity={focused || dragging ? 1 : 0.8}
              rx={focused || dragging ? 68 : 48}
              ry={GLOW_CENTER_Y}
            />
            <g
              style={{
                transform: `rotate(${-notch * tickDegrees}deg)`,
                transformOrigin: `${CENTER_X}px ${CENTER_Y}px`,
                transition: dragging
                  ? "none"
                  : "transform 260ms cubic-bezier(0.2, 0.9, 0.3, 1)",
              }}
            >
              {ticks.map((tick) => (
                <line
                  key={tick.key}
                  opacity={tick.opacity}
                  stroke="var(--muted-foreground)"
                  strokeLinecap="round"
                  strokeWidth={tick.major ? 1.6 : 1}
                  x1={tick.x1}
                  x2={tick.x2}
                  y1={tick.y1}
                  y2={tick.y2}
                />
              ))}
              {ticks
                .filter((tick) => tick.tint > 0.02)
                .map((tick) => (
                  <line
                    key={tick.key}
                    opacity={tick.tint}
                    stroke="var(--primary)"
                    strokeLinecap="round"
                    strokeWidth={tick.major ? 1.6 : 1}
                    x1={tick.x1}
                    x2={tick.x2}
                    y1={tick.y1}
                    y2={tick.y2}
                  />
                ))}
            </g>
            <line
              opacity={0.3}
              stroke={`url(#${paintId}-marker)`}
              strokeLinecap="round"
              strokeWidth={8}
              x1={CENTER_X}
              x2={CENTER_X}
              y1={MARKER_TOP}
              y2={MARKER_BOTTOM}
            />
            <line
              stroke={`url(#${paintId}-marker)`}
              strokeLinecap="round"
              strokeWidth={2.6}
              x1={CENTER_X}
              x2={CENTER_X}
              y1={MARKER_TOP}
              y2={MARKER_BOTTOM}
            />
          </svg>
        </div>
        {/* The hollow under the band is the two nudge areas: one each side,
            half the dial wide, with its mark in the middle of it — so a step
            is a press anywhere on that side rather than an aim at a glyph.
            They start below the notches, which leaves the whole band, right
            across the dial, to the turn. They sit outside the slider, so a
            press is never read as the start of one. */}
        <div
          className="pointer-events-none absolute inset-x-0 bottom-0 flex"
          style={{ height: `${100 - STEP_AREA_TOP}%` }}
        >
          <button
            type="button"
            data-haptics="off"
            aria-label={`Decrease ${ariaLabel.toLowerCase()}`}
            disabled={disabled || current <= min}
            onClick={() => commit(current - step)}
            className={cn(STEP_BUTTON, isCompact ? "text-lg" : "text-2xl")}
          >
            −
          </button>
          <button
            type="button"
            data-haptics="off"
            aria-label={`Increase ${ariaLabel.toLowerCase()}`}
            disabled={disabled || current >= max}
            onClick={() => commit(current + step)}
            className={cn(STEP_BUTTON, isCompact ? "text-lg" : "text-2xl")}
          >
            +
          </button>
        </div>
      </div>
    </div>
  )
}
