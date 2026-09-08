import { useCallback, useEffect, useMemo, useRef } from "react"
import {
  animate,
  useMotionValue,
  useReducedMotion,
  type MotionValue,
} from "motion/react"

import {
  angleDelta,
  bounceInBounds,
  bounceStrength,
  clampToBounds,
  clampVelocity,
  homeReturnDelay,
  normalizeAngle,
  orientationInfluence,
  rautaBounds,
  ROTATION_THRESHOLD_DEGREES,
  settleRotation,
  touchAngle,
  NO_ORIENTATION,
  type OrientationInfluence,
  type Point,
  type RautaBounds,
} from "@/lib/rauta-motion"

/**
 * Moving RAUTA around the screen.
 *
 * The character is dragged, thrown, twisted and tilted, all of which happen at
 * pointer or sensor rate. None of it goes through React state: position,
 * rotation and scale are motion values written straight to the element, so a
 * drag repaints the character and nothing else on the screen.
 *
 * The rules it obeys — where it may go, how hard it may be thrown, what counts
 * as a deliberate twist, how much a tilt is worth — are all in
 * `@/lib/rauta-motion`. This hook is the wiring: measure the real element and
 * viewport, read the gestures, run one animation loop, keep one sensor
 * listener, and tear all of it down on unmount.
 */

export type RautaGestureEvent =
  | { type: "drag-start" }
  | { type: "drag-end"; speed: number }
  | { type: "throw"; speed: number }
  | { type: "collision"; strength: "soft" | "hard"; edges: string[] }
  | { type: "rotate"; degrees: number }
  | { type: "return" }
  | { type: "tap" }
  | { type: "gesture-end" }

export type RautaMotionOptions = {
  /** Visible silhouette within the artboard; transparent animation padding
   * must not become an invisible wall. Coordinates are fractions of the box. */
  body?: { left: number; top: number; width: number; height: number }

  /** Room to leave at each screen edge — safe areas, bottom navigation, and
   *  any controls this screen needs to keep tappable. */
  inset?: { top?: number; right?: number; bottom?: number; left?: number }
  /** Told about gestures worth reacting to. Never called per frame. */
  onGesture?: (event: RautaGestureEvent) => void
  /** Turns dragging off entirely (a page that is not the active layer). */
  disabled?: boolean
}

type Sample = { x: number; y: number; at: number }

/** The box the character may travel in: the app shell around it, or the
 *  visible viewport when it is not inside one. */
function frameBox(node: HTMLElement) {
  const frame = node.closest(".app-shell-frame")
  if (frame) {
    // Follow the visible rounded surface, including its opening animation.
    const surface = frame.querySelector(".app-surface") ?? frame
    const box = surface.getBoundingClientRect()
    return {
      left: box.left,
      top: box.top,
      width: box.width,
      height: box.height,
    }
  }
  return {
    left: 0,
    top: 0,
    width: window.visualViewport?.width ?? window.innerWidth,
    height: window.visualViewport?.height ?? window.innerHeight,
  }
}

const FRICTION = 0.94
const REST_SPEED = 40
const MAX_FLIGHT_MS = 1400
/** A press that never really moved is a tap, not a drag. */
const TAP_SLOP = 7
/** The pull home: firm enough to read as a magnet, soft enough to watch. */
const HOME_SPRING = {
  type: "spring",
  stiffness: 180,
  damping: 21,
  mass: 1.1,
} as const

export function useRautaMotion(options: RautaMotionOptions = {}) {
  const { inset, body, onGesture, disabled = false } = options
  const reduced = useReducedMotion()

  const ref = useRef<HTMLDivElement | null>(null)
  const x = useMotionValue(0)
  const y = useMotionValue(0)
  const rotate = useMotionValue(0)
  const scale = useMotionValue(1)

  const bounds = useRef<RautaBounds>({ left: 0, right: 0, top: 0, bottom: 0 })
  const pointers = useRef(new Map<number, Point>())
  const drag = useRef<{
    id: number
    from: Point
    origin: Point
    moved: boolean
  } | null>(null)
  const twist = useRef<{
    angle: number
    from: number
    engaged: boolean
  } | null>(null)
  const samples = useRef<Sample[]>([])
  const frame = useRef<number | null>(null)
  const homecoming = useRef<{ timer: number | null; stop: () => void } | null>(
    null
  )
  const tilt = useRef<OrientationInfluence>(NO_ORIENTATION)
  const suppressClick = useRef(false)
  const notify = useRef(onGesture)
  useEffect(() => {
    notify.current = onGesture
  }, [onGesture])

  /** Measured, never assumed: read once per gesture rather than per frame. */
  const measure = useCallback(() => {
    const node = ref.current
    if (!node || typeof window === "undefined") return
    const rect = node.getBoundingClientRect()
    // The rect moves with the character, so the resting box is where it would
    // be with no offset applied.
    const width = node.offsetWidth || rect.width
    const height = node.offsetHeight || rect.height
    // Use the current rotation, rather than an invisible diagonal-sized square.
    const radians = (rotate.get() * Math.PI) / 180
    const c = Math.abs(Math.cos(radians))
    const s = Math.abs(Math.sin(radians))
    const bodyWidth = width * (body?.width ?? 1)
    const bodyHeight = height * (body?.height ?? 1)
    const dx = width * ((body?.left ?? 0) + (body?.width ?? 1) / 2 - 0.5)
    const dy = height * ((body?.top ?? 0) + (body?.height ?? 1) / 2 - 0.5)
    const centerX =
      (dx * Math.cos(radians) - dy * Math.sin(radians)) * scale.get()
    const centerY =
      (dx * Math.sin(radians) + dy * Math.cos(radians)) * scale.get()
    const envelopeWidth = (bodyWidth * c + bodyHeight * s) * scale.get()
    const envelopeHeight = (bodyHeight * c + bodyWidth * s) * scale.get()
    bounds.current = rautaBounds({
      rect: {
        left:
          rect.left + rect.width / 2 - x.get() + centerX - envelopeWidth / 2,
        top:
          rect.top + rect.height / 2 - y.get() + centerY - envelopeHeight / 2,
        width: envelopeWidth,
        height: envelopeHeight,
      },
      // The app's own frame is the screen on a phone and a centred column on
      // anything wider, so the character is free inside the layout rather than
      // inside the browser window it happens to be shown in.
      viewport: frameBox(node),
      inset,
    })
    // The source anchor can move while its page scrolls or the shell opens.
    // Keep the portal inside the newly measured surface in the same frame.
    const fitted = clampToBounds({ x: x.get(), y: y.get() }, bounds.current)
    x.set(fitted.x)
    y.set(fitted.y)
  }, [body, inset, rotate, scale, x, y])

  const stopFlight = useCallback(() => {
    if (frame.current !== null) cancelAnimationFrame(frame.current)
    frame.current = null
  }, [])

  /** Any new touch outranks the magnet: whatever the character was doing on
   *  its way home stops the moment a finger arrives. */
  const cancelHome = useCallback(() => {
    const pending = homecoming.current
    if (!pending) return
    if (pending.timer !== null) window.clearTimeout(pending.timer)
    pending.stop()
    homecoming.current = null
  }, [])

  /**
   * The magnet.
   *
   * The character's place in the layout is the one it belongs in, so wherever
   * it is put down it comes back — after a pause long enough to see where it
   * landed, and almost immediately when it was barely moved at all. It returns
   * to the nearest point inside the current bounds rather than to a slot that
   * may since have been scrolled or resized out of reach.
   */
  const pullHome = useCallback(() => {
    cancelHome()
    const target = clampToBounds({ x: 0, y: 0 }, bounds.current)
    const distance = Math.hypot(x.get() - target.x, y.get() - target.y)
    if (distance < 1) return
    const timer = window.setTimeout(() => {
      if (homecoming.current) homecoming.current.timer = null
      notify.current?.({ type: "return" })
      if (reduced) {
        x.set(target.x)
        y.set(target.y)
        homecoming.current = null
        return
      }
      const journey = [
        animate(x, target.x, HOME_SPRING),
        animate(y, target.y, HOME_SPRING),
      ]
      homecoming.current = {
        timer: null,
        stop: () => journey.forEach((leg) => leg.stop()),
      }
    }, homeReturnDelay(distance))
    homecoming.current = { timer, stop: () => {} }
  }, [cancelHome, reduced, x, y])

  /** Read through a ref so the flight loop, which outlives the render that
   *  started it, always calls the current magnet. */
  const home = useRef(pullHome)
  useEffect(() => {
    home.current = pullHome
  }, [pullHome])

  /** One loop for the whole throw: integrate, collide, damp, stop. */
  const fling = useCallback(
    (velocity: Point) => {
      stopFlight()
      let v = clampVelocity(velocity)
      let last = performance.now()
      const started = last

      const step = (now: number) => {
        const dt = Math.min(0.05, (now - last) / 1000)
        last = now
        const next = { x: x.get() + v.x * dt, y: y.get() + v.y * dt }
        const result = bounceInBounds(next, v, bounds.current)
        v = result.velocity
        x.set(result.position.x)
        y.set(result.position.y)

        if (result.hit.length) {
          const strength = bounceStrength(result.impact)
          if (strength !== "none")
            notify.current?.({ type: "collision", strength, edges: result.hit })
        }
        v = {
          x: v.x * Math.pow(FRICTION, dt * 60),
          y: v.y * Math.pow(FRICTION, dt * 60),
        }

        if (
          Math.hypot(v.x, v.y) < REST_SPEED ||
          now - started > MAX_FLIGHT_MS
        ) {
          const settled = clampToBounds(
            { x: x.get(), y: y.get() },
            bounds.current
          )
          x.set(settled.x)
          y.set(settled.y)
          frame.current = null
          // The throw is over; the magnet takes it from here.
          home.current()
          return
        }
        frame.current = requestAnimationFrame(step)
      }
      frame.current = requestAnimationFrame(step)
    },
    [stopFlight, x, y]
  )

  const releaseTwist = useCallback(() => {
    if (!twist.current?.engaged) {
      twist.current = null
      return
    }
    twist.current = null
    const settled = settleRotation(rotate.get())
    rotate.set(settled)
    measure()
    const fitted = clampToBounds({ x: x.get(), y: y.get() }, bounds.current)
    x.set(fitted.x)
    y.set(fitted.y)
  }, [measure, rotate, x, y])

  const handlers = useMemo(() => {
    if (disabled) return {}
    return {
      onPointerDown(event: React.PointerEvent<HTMLDivElement>) {
        if (event.button !== 0 && event.pointerType === "mouse") return
        if (pointers.current.size === 0) suppressClick.current = false
        pointers.current.set(event.pointerId, {
          x: event.clientX,
          y: event.clientY,
        })
        try {
          // Capture keeps the gesture alive when the finger leaves the
          // character, but a browser is entitled to refuse it. Losing capture
          // must never cost the drag itself.
          ;(event.target as HTMLElement).setPointerCapture?.(event.pointerId)
        } catch {
          /* Tracked through the pointer id instead. */
        }
        stopFlight()
        cancelHome()
        scale.set(1)
        measure()

        if (pointers.current.size === 2) {
          // Two fingers means a twist, and a twist is not a drag: whichever
          // drag was in progress ends here so the character cannot slide while
          // it turns.
          suppressClick.current = true
          const [a, b] = [...pointers.current.values()]
          twist.current = {
            angle: touchAngle(a, b),
            from: rotate.get(),
            engaged: false,
          }
          drag.current = null
          return
        }
        if (pointers.current.size === 1) {
          drag.current = {
            id: event.pointerId,
            from: { x: event.clientX, y: event.clientY },
            origin: { x: x.get(), y: y.get() },
            moved: false,
          }
          samples.current = [{ x: x.get(), y: y.get(), at: performance.now() }]
        }
      },

      onPointerMove(event: React.PointerEvent<HTMLDivElement>) {
        if (!pointers.current.has(event.pointerId)) return
        pointers.current.set(event.pointerId, {
          x: event.clientX,
          y: event.clientY,
        })

        if (pointers.current.size >= 2 && twist.current) {
          const [a, b] = [...pointers.current.values()]
          const delta = angleDelta(twist.current.angle, touchAngle(a, b))
          // Only a real twist turns the character; resting two fingers on it
          // does nothing at all.
          if (!twist.current.engaged) {
            if (Math.abs(delta) < ROTATION_THRESHOLD_DEGREES) return
            twist.current = { ...twist.current, engaged: true }
            notify.current?.({ type: "rotate", degrees: delta })
          }
          rotate.set(normalizeAngle(twist.current.from + delta))
          measure()
          const fitted = clampToBounds(
            { x: x.get(), y: y.get() },
            bounds.current
          )
          x.set(fitted.x)
          y.set(fitted.y)
          return
        }

        const gesture = drag.current
        if (!gesture || gesture.id !== event.pointerId) return
        const dx = event.clientX - gesture.from.x
        const dy = event.clientY - gesture.from.y
        if (!gesture.moved && Math.hypot(dx, dy) > TAP_SLOP) {
          gesture.moved = true
          suppressClick.current = true
          notify.current?.({ type: "drag-start" })
        }
        if (!gesture.moved) return
        // One finger translates. It never rotates — turning the character is a
        // thing you have to mean.
        const next = clampToBounds(
          { x: gesture.origin.x + dx, y: gesture.origin.y + dy },
          bounds.current
        )
        x.set(next.x)
        y.set(next.y)
        const at = performance.now()
        samples.current.push({ x: next.x, y: next.y, at })
        if (samples.current.length > 6) samples.current.shift()
      },

      onPointerUp(event: React.PointerEvent<HTMLDivElement>) {
        pointers.current.delete(event.pointerId)
        scale.set(1)
        if (twist.current) {
          notify.current?.({ type: "gesture-end" })
          releaseTwist()
          return
        }
        const gesture = drag.current
        drag.current = null
        if (!gesture || gesture.id !== event.pointerId) return
        if (!gesture.moved) {
          notify.current?.({ type: "tap" })
          return
        }

        const trail = samples.current
        const first = trail[0]
        const last = trail[trail.length - 1]
        const elapsed =
          last && first && performance.now() - last.at < 100
            ? (last.at - first.at) / 1000
            : 0
        const velocity =
          elapsed > 0.012
            ? {
                x: (last.x - first.x) / elapsed,
                y: (last.y - first.y) / elapsed,
              }
            : { x: 0, y: 0 }
        const clamped = clampVelocity(velocity)
        const speed = Math.hypot(clamped.x, clamped.y)
        notify.current?.({ type: "drag-end", speed })
        // Reduced motion skips the flight, not the way back.
        if (reduced || speed < REST_SPEED) {
          pullHome()
          return
        }
        notify.current?.({ type: "throw", speed })
        fling(clamped)
      },

      onClickCapture(event: React.MouseEvent<HTMLDivElement>) {
        if (suppressClick.current) {
          event.preventDefault()
          event.stopPropagation()
          suppressClick.current = false
        }
      },

      onPointerCancel(event: React.PointerEvent<HTMLDivElement>) {
        pointers.current.delete(event.pointerId)
        suppressClick.current = true
        notify.current?.({ type: "gesture-end" })
        drag.current = null
        twist.current = null
        scale.set(1)
        pullHome()
      },
    }
  }, [
    cancelHome,
    disabled,
    fling,
    measure,
    pullHome,
    reduced,
    releaseTwist,
    rotate,
    scale,
    stopFlight,
    x,
    y,
  ])

  useEffect(() => {
    if (disabled || reduced || typeof window === "undefined") return
    let sensorFrame: number | null = null
    let attached = false
    const onOrientation = (event: DeviceOrientationEvent) => {
      if (sensorFrame !== null || document.hidden) return
      sensorFrame = requestAnimationFrame(() => {
        sensorFrame = null
        if (pointers.current.size || frame.current !== null) return
        const nextTilt = orientationInfluence(tilt.current, event)
        // Apply only the change in tilt, around the position the user chose.
        const next = clampToBounds(
          {
            x: x.get() + nextTilt.x - tilt.current.x,
            y: y.get() + nextTilt.y - tilt.current.y,
          },
          bounds.current
        )
        tilt.current = nextTilt
        x.set(next.x)
        y.set(next.y)
      })
    }
    const attach = () => {
      const api = window.DeviceOrientationEvent as unknown as
        { requestPermission?: () => Promise<string> } | undefined
      if (!attached && api && (!api.requestPermission || orientationGranted)) {
        window.addEventListener("deviceorientation", onOrientation)
        attached = true
      }
    }
    attach()
    window.addEventListener("rauta-orientation-granted", attach)
    return () => {
      if (sensorFrame !== null) cancelAnimationFrame(sensorFrame)
      window.removeEventListener("deviceorientation", onOrientation)
      window.removeEventListener("rauta-orientation-granted", attach)
    }
  }, [disabled, reduced, x, y])

  useEffect(() => {
    if (typeof window === "undefined") return
    const remeasure = () => {
      measure()
      const next = clampToBounds({ x: x.get(), y: y.get() }, bounds.current)
      x.set(next.x)
      y.set(next.y)
    }
    remeasure()
    const observer =
      typeof ResizeObserver === "undefined"
        ? null
        : new ResizeObserver(remeasure)
    const shell = ref.current?.closest(".app-shell-frame")
    if (ref.current)
      observer?.observe(
        shell?.querySelector(".app-surface") ?? shell ?? ref.current
      )
    shell?.addEventListener("transitionend", remeasure)
    window.addEventListener("resize", remeasure)
    window.visualViewport?.addEventListener("resize", remeasure)
    // Scrolling is deliberately not listened for. The character sits in the
    // shell rather than in the page, so a scroll neither moves it nor changes
    // the surface it is bounded by — and re-measuring on every scroll frame
    // only ever cost work.
    return () => {
      observer?.disconnect()
      shell?.removeEventListener("transitionend", remeasure)
      window.removeEventListener("resize", remeasure)
      window.visualViewport?.removeEventListener("resize", remeasure)
    }
  }, [measure, x, y])

  useEffect(() => {
    if (disabled || reduced) {
      stopFlight()
      cancelHome()
      pointers.current.clear()
      drag.current = null
      twist.current = null
      scale.set(1)
    }
  }, [cancelHome, disabled, reduced, stopFlight, scale])

  useEffect(
    () => () => {
      stopFlight()
      cancelHome()
    },
    [cancelHome, stopFlight]
  )

  return { ref, x, y, rotate, scale, handlers, measure } satisfies {
    ref: React.RefObject<HTMLDivElement | null>
    x: MotionValue<number>
    y: MotionValue<number>
    rotate: MotionValue<number>
    scale: MotionValue<number>
    handlers: Record<string, unknown>
    measure: () => void
  }
}

/** Whether the person has already allowed motion readings this session. Only
 *  ever set from a real interaction, never at launch. */
let orientationGranted = false

/**
 * Asks for device-motion access, from a gesture.
 *
 * Safe to call anywhere: platforms that need no permission report success, and
 * a refusal simply leaves the character working without tilt.
 */
export async function requestRautaOrientation(): Promise<boolean> {
  if (typeof window === "undefined") return false
  const api = window.DeviceOrientationEvent as unknown as
    { requestPermission?: () => Promise<string> } | undefined
  if (!api) return false
  if (typeof api.requestPermission !== "function") {
    orientationGranted = true
    return true
  }
  try {
    orientationGranted = (await api.requestPermission()) === "granted"
  } catch {
    orientationGranted = false
  }
  if (orientationGranted)
    window.dispatchEvent(new Event("rauta-orientation-granted"))
  return orientationGranted
}
