import { useRef, useState, type PointerEvent, type ReactNode } from "react"

import { cn } from "@/lib/utils"

export const SWIPE_REVEAL_WIDTH = 92
const OPEN_THRESHOLD = SWIPE_REVEAL_WIDTH / 2
const DRAG_LOCK_DISTANCE = 8

/**
 * A row that swipes left to reveal an action (typically delete) parked
 * behind it, iOS-list style. `isOpen`/`onOpenChange` are lifted to the
 * caller so a list can keep only one row open at a time.
 */
export function SwipeableRow({
  action,
  children,
  className,
  isOpen,
  onOpenChange,
}: {
  action: ReactNode
  children: ReactNode
  className?: string
  isOpen: boolean
  onOpenChange: (open: boolean) => void
}) {
  const [dragX, setDragX] = useState<number | null>(null)
  // Drives the transition style, so it has to be state (render can't read
  // refs); `locked` is the same "are we actually dragging" flag but as a
  // ref, for synchronous checks inside the handlers themselves.
  const [isDragging, setIsDragging] = useState(false)
  const start = useRef<{ x: number; y: number } | null>(null)
  const locked = useRef(false)

  const settledX = isOpen ? -SWIPE_REVEAL_WIDTH : 0
  const x = dragX ?? settledX

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
      setIsDragging(true)
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
    setDragX(Math.min(0, Math.max(-SWIPE_REVEAL_WIDTH, settledX + dx)))
  }

  const endDrag = () => {
    if (locked.current) {
      const finalX = dragX ?? settledX
      onOpenChange(finalX <= -OPEN_THRESHOLD)
    }
    start.current = null
    locked.current = false
    setIsDragging(false)
    setDragX(null)
  }

  return (
    <div className={cn("relative overflow-hidden", className)}>
      <div
        className="absolute inset-y-0 right-0 flex items-center justify-center pl-4"
        style={{ width: SWIPE_REVEAL_WIDTH }}
      >
        {action}
      </div>
      <div
        className="relative touch-pan-y"
        onPointerCancel={endDrag}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={endDrag}
        style={{
          transform: `translateX(${x}px)`,
          transition: isDragging
            ? "none"
            : "transform 280ms var(--ease-smooth-out)",
        }}
      >
        {children}
      </div>
    </div>
  )
}
