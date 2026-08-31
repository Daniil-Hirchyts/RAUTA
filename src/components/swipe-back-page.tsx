import type { ReactNode } from "react"

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
  const { containerRef, dragging, offset, handlers } = useEdgeSwipe({
    canGoBack: true,
    canGoForward: false,
    onBack,
    onForward: () => undefined,
  })

  return (
    <div
      className="t-swipe-back flex min-h-0 flex-1 flex-col"
      data-dragging={dragging ? "true" : undefined}
      ref={containerRef}
      style={dragging ? { transform: `translateX(${offset}px)` } : undefined}
      {...handlers}
    >
      {children}
    </div>
  )
}
