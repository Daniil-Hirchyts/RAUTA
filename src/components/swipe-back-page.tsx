import { useCallback, useEffect, useRef, useState, type ReactNode } from "react"

import { useEdgeSwipe } from "@/hooks/use-edge-swipe"

/**
 * Gives a full-screen view the same left-edge back gesture the staged flow
 * has. There is no previous page mounted to pull in behind these, so the
 * page itself travels with the finger and the view swaps on commit.
 */
export function SwipeBackPage({
  children,
  onBack,
}: {
  children: ReactNode
  onBack: () => void
}) {
  const [committed, setCommitted] = useState(false)
  const completedRef = useRef(false)
  const finishBack = useCallback(() => {
    if (completedRef.current) return
    completedRef.current = true
    onBack()
  }, [onBack])
  const beginBack = useCallback(() => setCommitted(true), [])

  useEffect(() => {
    if (!committed) return
    const fallback = window.setTimeout(finishBack, 360)
    return () => window.clearTimeout(fallback)
  }, [committed, finishBack])

  const { containerRef, dragging, offset, handlers } = useEdgeSwipe({
    canGoBack: true,
    canGoForward: false,
    onBack: beginBack,
    onForward: () => undefined,
  })

  return (
    <div
      className="t-swipe-back flex min-h-0 flex-1 flex-col"
      data-committed={committed ? "true" : undefined}
      data-dragging={dragging ? "true" : undefined}
      onTransitionEnd={(event) => {
        if (
          committed &&
          event.currentTarget === event.target &&
          event.propertyName === "transform"
        ) {
          finishBack()
        }
      }}
      ref={containerRef}
      style={
        committed
          ? { transform: "translateX(100%)" }
          : dragging
            ? { transform: `translateX(${offset}px)` }
            : undefined
      }
      {...handlers}
    >
      {children}
    </div>
  )
}
