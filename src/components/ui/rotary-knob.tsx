import {
  useId,
  useRef,
  useState,
  type KeyboardEvent,
  type PointerEvent,
} from "react"

import { triggerHaptic } from "@/lib/haptics"
import { cn, snapToRange } from "@/lib/utils"

/**
 * A dial for a number that would otherwise need a keyboard.
 *
 * Turning it is the whole point: a phone keyboard covers half the screen to
 * collect two digits, and every number this app asks for — an age, how long a
 * session should run — is a value you nudge rather than type. The gesture is
 * relative, so grabbing the dial never jumps the value, and it tracks the
 * angle around the centre, so a small circle at the edge is as usable as a
 * wide one. Hardware keyboards and assistive technology drive the same value
 * through ARIA slider semantics.
 */

/** How much of the circle the range is spread over, and where it starts.
 *  Leaving the bottom open is what makes the dial read as a gauge with two
 *  ends rather than an endless wheel. */
const SWEEP_DEGREES = 270
const START_ANGLE = -135

const VIEWBOX = 120
const CENTER = VIEWBOX / 2
const RADIUS = 50
const TRACK_WIDTH = 2

function polar(angleDegrees: number, radius = RADIUS) {
  // 0° points at 12 o'clock and grows clockwise, the way the dial is read.
  const radians = ((angleDegrees - 90) * Math.PI) / 180
  return {
    x: CENTER + radius * Math.cos(radians),
    y: CENTER + radius * Math.sin(radians),
  }
}

function arcPath(fromDegrees: number, toDegrees: number) {
  const from = polar(fromDegrees)
  const to = polar(toDegrees)
  const largeArc = Math.abs(toDegrees - fromDegrees) > 180 ? 1 : 0
  return `M ${from.x} ${from.y} A ${RADIUS} ${RADIUS} 0 ${largeArc} 1 ${to.x} ${to.y}`
}

/** Shortest way round from one angle to another, so a drag that crosses the
 *  gap at the bottom counts as a few degrees rather than most of a turn. */
function angleDelta(from: number, to: number) {
  return ((((to - from) % 360) + 540) % 360) - 180
}

export function RotaryKnob({
  ariaLabel,
  className,
  disabled = false,
  format = String,
  label,
  max,
  min,
  onChange,
  size = 232,
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
  size?: number
  step?: number
  unit?: string
  value: number
}) {
  // Two dials on one page must not both answer to the same paint server, and
  // React's generated ids carry colons an SVG reference cannot use.
  const gradientId = `rotary-knob-${useId().replace(/:/g, "")}`
  const [dragging, setDragging] = useState(false)
  const gesture = useRef<{
    angle: number
    pointerId: number
    rotation: number
    value: number
  } | null>(null)

  const range = { max, min, step }
  const current = snapToRange(value, range)
  const span = max - min
  const fraction = span > 0 ? (current - min) / span : 0
  const valueAngle = START_ANGLE + fraction * SWEEP_DEGREES
  const handle = polar(valueAngle, 40)

  const commit = (next: number) => {
    const snapped = snapToRange(next, range)
    if (snapped === current) return
    // One tick per notch: the dial should feel like it is passing over
    // something rather than sliding.
    triggerHaptic("selection")
    onChange(snapped)
  }

  const pointerAngle = (event: PointerEvent<HTMLDivElement>) => {
    const bounds = event.currentTarget.getBoundingClientRect()
    const dx = event.clientX - (bounds.left + bounds.width / 2)
    const dy = event.clientY - (bounds.top + bounds.height / 2)
    if (dx === 0 && dy === 0) return null
    return (Math.atan2(dx, -dy) * 180) / Math.PI
  }

  const onPointerDown = (event: PointerEvent<HTMLDivElement>) => {
    if (disabled || event.button > 0) return
    const angle = pointerAngle(event)
    if (angle === null) return
    // The dial owns this gesture from here: `touch-none` already keeps the
    // page from scrolling under the finger, and capture keeps the value
    // tracking once the finger wanders outside the circle.
    try {
      event.currentTarget.setPointerCapture(event.pointerId)
    } catch {
      // Capture is an enhancement; the drag still works without it.
    }
    gesture.current = {
      angle,
      pointerId: event.pointerId,
      rotation: 0,
      value: current,
    }
    setDragging(true)
    event.currentTarget.focus({ preventScroll: true })
  }

  const onPointerMove = (event: PointerEvent<HTMLDivElement>) => {
    const state = gesture.current
    if (!state || state.pointerId !== event.pointerId) return
    const angle = pointerAngle(event)
    if (angle === null) return
    event.preventDefault()

    const travelled = state.rotation + angleDelta(state.angle, angle)
    // Held at the range's own edge rather than allowed to wind up past it, so
    // turning back answers on the first degree.
    const lower = span > 0 ? ((min - state.value) / span) * SWEEP_DEGREES : 0
    const upper = span > 0 ? ((max - state.value) / span) * SWEEP_DEGREES : 0
    state.rotation = Math.min(upper, Math.max(lower, travelled))
    state.angle = angle

    commit(state.value + (state.rotation / SWEEP_DEGREES) * span)
  }

  const endGesture = (event: PointerEvent<HTMLDivElement>) => {
    if (gesture.current?.pointerId !== event.pointerId) return
    gesture.current = null
    setDragging(false)
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

  return (
    <div className={cn("flex flex-col items-center gap-2.5", className)}>
      {label ? (
        <p className="text-xs font-bold tracking-[0.16em] text-muted-foreground uppercase">
          {label}
        </p>
      ) : null}
      <div
        aria-disabled={disabled || undefined}
        aria-label={ariaLabel}
        aria-valuemax={max}
        aria-valuemin={min}
        aria-valuenow={current}
        aria-valuetext={unit ? `${format(current)} ${unit}` : format(current)}
        className={cn(
          "relative grid touch-none place-items-center rounded-full drop-shadow-[0_14px_18px_rgba(0,0,0,0.3)] outline-none select-none",
          "focus-visible:ring-3 focus-visible:ring-ring/30",
          disabled && "opacity-50"
        )}
        data-dragging={dragging ? "true" : undefined}
        data-slot="rotary-knob"
        // The dial reads a drag of its own; the shell's edge-swipe navigation
        // and the direct-touch haptic overlay both stay out of it.
        data-swipe-ignore
        onKeyDown={onKeyDown}
        onLostPointerCapture={endGesture}
        onPointerCancel={endGesture}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={endGesture}
        role="slider"
        style={{ height: size, width: size }}
        tabIndex={disabled ? -1 : 0}
      >
        <svg
          aria-hidden="true"
          className="absolute inset-0 h-full w-full overflow-visible"
          viewBox={`0 0 ${VIEWBOX} ${VIEWBOX}`}
        >
          <defs>
            <linearGradient id={gradientId} x1="0" x2="1" y1="0" y2="1">
              <stop offset="0%" stopColor="var(--primary-gradient-start)" />
              <stop offset="100%" stopColor="var(--primary-gradient-end)" />
            </linearGradient>
          </defs>
          <circle
            cx={CENTER}
            cy={CENTER}
            r={43}
            fill="var(--card)"
            stroke="var(--border)"
            strokeWidth="0.6"
          />
          <circle
            cx={CENTER}
            cy={CENTER}
            r={36}
            fill="var(--background)"
            stroke="var(--border)"
            strokeWidth="0.4"
          />
          {Array.from({ length: 55 }, (_, i) => {
            const angle = START_ANGLE + i * 5
            const inner = polar(angle, i % 5 === 0 ? 53 : 55)
            const outer = polar(angle, 58)
            return (
              <line
                key={i}
                x1={inner.x}
                y1={inner.y}
                x2={outer.x}
                y2={outer.y}
                stroke={
                  angle <= valueAngle
                    ? "var(--primary)"
                    : "var(--muted-foreground)"
                }
                opacity={angle <= valueAngle ? 1 : 0.35}
                strokeWidth={i % 5 === 0 ? 1 : 0.5}
              />
            )
          })}
          <path
            d={arcPath(START_ANGLE, START_ANGLE + SWEEP_DEGREES)}
            fill="none"
            stroke="var(--input)"
            strokeLinecap="round"
            strokeWidth={TRACK_WIDTH}
          />
          {fraction > 0 ? (
            <path
              d={arcPath(START_ANGLE, valueAngle)}
              fill="none"
              stroke={`url(#${gradientId})`}
              strokeLinecap="round"
              strokeWidth={TRACK_WIDTH}
            />
          ) : null}
          <circle cx={handle.x} cy={handle.y} fill="var(--primary)" r={2} />
        </svg>
        <span className="pointer-events-none relative z-10 flex flex-col items-center">
          <span className="font-heading text-[3.25rem] leading-none font-black tracking-[-0.03em] tabular-nums">
            {format(current)}
          </span>
          {unit ? (
            <span className="mt-1.5 text-xs font-bold tracking-[0.16em] text-muted-foreground uppercase">
              {unit}
            </span>
          ) : null}
        </span>
      </div>
      <div
        className="flex items-center gap-5 text-xs font-semibold text-muted-foreground"
        aria-hidden="true"
      >
        <span>{min}</span>
        <span className="text-[10px] tracking-[0.18em] uppercase">
          Turn to adjust
        </span>
        <span>{max}</span>
      </div>
      <div className="flex gap-3">
        <button
          type="button"
          data-haptics="off"
          aria-label={`Decrease ${ariaLabel.toLowerCase()}`}
          disabled={disabled || current <= min}
          onClick={() => commit(current - step)}
          className="interactive-spring grid size-11 place-items-center rounded-full border border-border bg-card text-xl disabled:opacity-35"
        >
          −
        </button>
        <button
          type="button"
          data-haptics="off"
          aria-label={`Increase ${ariaLabel.toLowerCase()}`}
          disabled={disabled || current >= max}
          onClick={() => commit(current + step)}
          className="interactive-spring grid size-11 place-items-center rounded-full border border-border bg-card text-xl disabled:opacity-35"
        >
          +
        </button>
      </div>
    </div>
  )
}
