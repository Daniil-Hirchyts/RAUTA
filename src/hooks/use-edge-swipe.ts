import { useCallback, useEffect, useRef } from "react"

/** How far in from a side edge a drag has to start to count as navigation. */
const EDGE_WIDTH = 32
/** Horizontal travel before the gesture takes over from a vertical scroll. */
const DIRECTION_LOCK = 8
/** Fraction of the container that has to be crossed to commit the change. */
const COMMIT_RATIO = 0.32
/** A quick flick commits even when it never crosses COMMIT_RATIO. */
const COMMIT_VELOCITY = 0.45

export type SwipePeer = "prev" | "next" | null

/**
 * iOS-style interactive page navigation: a drag that starts at either side
 * edge pulls the neighbouring page along with the finger, and releasing it
 * either commits the change or springs back.
 *
 * Deliberately edge-only. The stages are full of horizontally scrollable
 * strips, tappable cards and a swipeable body map, so a gesture that started
 * anywhere would steal from them.
 */
export function useEdgeSwipe({
  canGoBack,
  canGoForward,
  onBack,
  onForward,
}: {
  canGoBack: boolean
  canGoForward: boolean
  onBack: () => void
  onForward: () => void
}) {
  const containerRef = useRef<HTMLDivElement | null>(null)
  const offset = useRef(0)
  const paintFrame = useRef<number | null>(null)

  // Everything the in-flight gesture needs lives in a ref: re-rendering on
  // each touchmove is already paid for by the offset state, and the rest
  // must not go stale between events.
  const gesture = useRef<{
    active: boolean
    decided: boolean
    intent: SwipePeer
    startX: number
    startY: number
    lastX: number
    lastT: number
    velocity: number
    width: number
  } | null>(null)

  const reset = useCallback(() => {
    if (paintFrame.current !== null) cancelAnimationFrame(paintFrame.current)
    paintFrame.current = null
    gesture.current = null
    offset.current = 0
    const element = containerRef.current
    if (!element) return
    delete element.dataset.dragging
    delete element.dataset.swipePeer
    element.style.removeProperty("--stack-drag-peer-x")
    element.style.removeProperty("--stack-drag-x")
  }, [])

  const paintOffset = useCallback(() => {
    paintFrame.current = null
    const element = containerRef.current
    if (!element) return
    element.style.setProperty("--stack-drag-x", `${offset.current}px`)
    element.style.setProperty(
      "--stack-drag-peer-x",
      `${offset.current * 0.1}px`
    )
  }, [])

  const onTouchStart = useCallback(
    (event: React.TouchEvent<HTMLDivElement>) => {
      if (event.touches.length !== 1) return reset()

      const touch = event.touches[0]
      const element = containerRef.current
      if (!element) return
      const bounds = element.getBoundingClientRect()
      const fromLeft = touch.clientX - bounds.left
      const fromRight = bounds.right - touch.clientX

      // Left edge goes back, right edge goes forward — the direction the
      // page will travel is the direction the finger already points.
      let intent: SwipePeer = null
      if (fromLeft <= EDGE_WIDTH && canGoBack) intent = "prev"
      else if (fromRight <= EDGE_WIDTH && canGoForward) intent = "next"
      if (!intent) return

      gesture.current = {
        active: true,
        decided: false,
        intent,
        startX: touch.clientX,
        startY: touch.clientY,
        lastX: touch.clientX,
        lastT: event.timeStamp,
        velocity: 0,
        width: bounds.width || 1,
      }
    },
    [canGoBack, canGoForward, reset]
  )

  const onTouchMove = useCallback(
    (event: React.TouchEvent<HTMLDivElement>) => {
      const state = gesture.current
      if (!state?.active) return
      const touch = event.touches[0]
      const dx = touch.clientX - state.startX
      const dy = touch.clientY - state.startY

      if (!state.decided) {
        if (Math.abs(dx) < DIRECTION_LOCK && Math.abs(dy) < DIRECTION_LOCK)
          return
        // A mostly-vertical start belongs to the scroller underneath.
        if (Math.abs(dy) > Math.abs(dx)) return reset()
        // So does a drag heading away from the page it would reveal.
        if (state.intent === "prev" ? dx <= 0 : dx >= 0) return reset()
        state.decided = true
        const element = containerRef.current
        if (element) {
          element.dataset.dragging = "true"
          element.dataset.swipePeer =
            state.intent === "prev" ? "prev" : "next"
        }
      }

      const dt = event.timeStamp - state.lastT
      if (dt > 0) state.velocity = (touch.clientX - state.lastX) / dt
      state.lastX = touch.clientX
      state.lastT = event.timeStamp

      // Clamp to the direction of travel so the page can't be dragged the
      // wrong way past its resting position.
      const clamped =
        state.intent === "prev"
          ? Math.max(0, Math.min(dx, state.width))
          : Math.min(0, Math.max(dx, -state.width))
      offset.current = clamped
      if (paintFrame.current === null) {
        paintFrame.current = requestAnimationFrame(paintOffset)
      }
    },
    [paintOffset, reset]
  )

  const onTouchEnd = useCallback(
    (event: React.TouchEvent<HTMLDivElement>) => {
      const state = gesture.current
      if (!state?.active || !state.decided) return reset()

      const travelled = Math.abs(offset.current) / state.width
      const flicked =
        state.intent === "prev"
          ? state.velocity > COMMIT_VELOCITY
          : state.velocity < -COMMIT_VELOCITY
      const commit = travelled > COMMIT_RATIO || flicked

      // Drop the drag first: the pages keep their current on-screen transform
      // and CSS animates them the rest of the way, whether that is onward to
      // the new stage or back to the old one.
      reset()
      if (commit) {
        if (state.intent === "prev") onBack()
        else onForward()
      }
      event.stopPropagation()
    },
    [onBack, onForward, reset]
  )

  // Backgrounding mid-drag must not leave the pages parked halfway.
  useEffect(() => {
    const cancel = () => reset()
    window.addEventListener("pagehide", cancel)
    return () => window.removeEventListener("pagehide", cancel)
  }, [reset])

  return {
    containerRef,
    handlers: {
      onTouchCancel: reset,
      onTouchEnd,
      onTouchMove,
      onTouchStart,
    },
  }
}
