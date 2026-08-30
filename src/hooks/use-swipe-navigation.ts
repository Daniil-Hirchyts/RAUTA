import { useRef, type PointerEventHandler } from "react"

type SwipeDirection = "left" | "right"

const SWIPE_DISTANCE = 56
const HORIZONTAL_BIAS = 1.25

export function useSwipeNavigation(
  onSwipe: (direction: SwipeDirection) => void
) {
  const start = useRef<{ x: number; y: number } | null>(null)

  const onPointerDown: PointerEventHandler<HTMLElement> = (event) => {
    if (event.pointerType !== "touch") return
    const target = event.target
    if (
      target instanceof Element &&
      target.closest("[data-swipe-ignore], [data-slot='drawer-popup']")
    ) {
      return
    }
    start.current = { x: event.clientX, y: event.clientY }
  }

  const onPointerCancel: PointerEventHandler<HTMLElement> = () => {
    start.current = null
  }

  const onPointerUp: PointerEventHandler<HTMLElement> = (event) => {
    if (!start.current) return
    const dx = event.clientX - start.current.x
    const dy = event.clientY - start.current.y
    start.current = null

    if (
      Math.abs(dx) < SWIPE_DISTANCE ||
      Math.abs(dx) < Math.abs(dy) * HORIZONTAL_BIAS
    ) {
      return
    }

    onSwipe(dx > 0 ? "right" : "left")
  }

  return { onPointerCancel, onPointerDown, onPointerUp }
}
