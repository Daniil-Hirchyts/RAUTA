import {
  useCallback,
  useEffect,
  useRef,
  type PointerEvent,
  type ReactNode,
} from "react"

import { cn } from "@/lib/utils"

export const SWIPE_REVEAL_WIDTH = 92
const DRAG_LOCK_DISTANCE = 8

/**
 * A row that swipes left to reveal an action (typically delete) parked
 * behind it, iOS-list style. `isOpen`/`onOpenChange` are lifted to the
 * caller so a list can keep only one row open at a time.
 */
export function SwipeableRow({
  action,
  actionInset = 0,
  children,
  className,
  isOpen,
  onOpenChange,
  revealWidth = SWIPE_REVEAL_WIDTH,
}: {
  action: ReactNode
  /** The card's right-side margin, included in the exposed delete area. */
  actionInset?: number
  children: ReactNode
  className?: string
  isOpen: boolean
  onOpenChange: (open: boolean) => void
  revealWidth?: number
}) {
  const start = useRef<{ x: number; y: number } | null>(null)
  const locked = useRef(false)
  const dragX = useRef<number | null>(null)
  const contentRef = useRef<HTMLDivElement>(null)
  const actionRef = useRef<HTMLDivElement>(null)
  const paintFrame = useRef<number | null>(null)

  const settledX = isOpen ? -revealWidth : 0

  const paint = useCallback((x: number) => {
    paintFrame.current = null
    if (contentRef.current) {
      contentRef.current.style.transform = `translate3d(${x}px, 0, 0)`
    }
    if (actionRef.current) {
      const visible = x < -1
      actionRef.current.style.opacity = visible ? "1" : "0"
      // Keep the action layer hit-testable for accessibility and keyboard
      // discovery. The content layer is painted above it while closed, so it
      // still cannot steal taps until the row is actually revealed.
      actionRef.current.style.pointerEvents = "auto"
    }
  }, [])

  const schedulePaint = useCallback((x: number) => {
    if (paintFrame.current !== null) cancelAnimationFrame(paintFrame.current)
    paintFrame.current = requestAnimationFrame(() => paint(x))
  }, [paint])

  useEffect(() => {
    if (contentRef.current) {
      contentRef.current.style.transition =
        "transform 280ms var(--ease-smooth-out)"
    }
    schedulePaint(settledX)
    return () => {
      if (paintFrame.current !== null) cancelAnimationFrame(paintFrame.current)
    }
  }, [schedulePaint, settledX])

  const onPointerDown = (event: PointerEvent<HTMLDivElement>) => {
    start.current = { x: event.clientX, y: event.clientY }
    locked.current = false
  }

  const onPointerMove = (event: PointerEvent<HTMLDivElement>) => {
    if (!start.current) return
    const dx = event.clientX - start.current.x
    const dy = event.clientY - start.current.y

    if (!locked.current) {
      if (Math.max(Math.abs(dx), Math.abs(dy)) < DRAG_LOCK_DISTANCE) return
      if (Math.abs(dx) < Math.abs(dy)) {
        // Vertical intent — let the list scroll natively instead.
        start.current = null
        return
      }
      locked.current = true
      if (contentRef.current) contentRef.current.style.transition = "none"
      // Capture is a reliability nice-to-have (keeps the drag tracking even
      // if the finger leaves the element); a pointer some environments
      // consider inactive can reject it, but the gesture works fine without.
      try {
        event.currentTarget.setPointerCapture?.(event.pointerId)
      } catch {
        // Ignored — see above.
      }
    }

    event.preventDefault()
    dragX.current = Math.min(0, Math.max(-revealWidth, settledX + dx))
    schedulePaint(dragX.current)
  }

  const endDrag = () => {
    if (locked.current) {
      const finalX = dragX.current ?? settledX
      const nextOpen = finalX <= -revealWidth / 2
      onOpenChange(nextOpen)
      if (contentRef.current) {
        contentRef.current.style.transition =
          "transform 280ms var(--ease-smooth-out)"
      }
      schedulePaint(nextOpen ? -revealWidth : 0)
    }
    start.current = null
    locked.current = false
    dragX.current = null
  }

  return (
    <div className={cn("relative overflow-hidden", className)}>
      <div
        className="absolute inset-y-0 right-0 flex items-center justify-center opacity-0 transition-opacity duration-150"
        ref={actionRef}
        style={{ width: revealWidth + actionInset }}
      >
        {action}
      </div>
      <div
        className="relative touch-pan-y"
        onPointerCancel={endDrag}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={endDrag}
        ref={contentRef}
        style={{
          transform: `translate3d(${settledX}px, 0, 0)`,
          transition: "transform 280ms var(--ease-smooth-out)",
        }}
      >
        {children}
      </div>
    </div>
  )
}
