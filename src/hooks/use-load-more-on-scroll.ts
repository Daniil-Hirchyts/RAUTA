import { useEffect, useRef, useState } from "react"

/**
 * Bounds a long list to a manageable initial render size and grows it as
 * the user scrolls near the end, instead of mounting every item (and every
 * per-item cost — SVG filters, blend modes, extra DOM nodes) at once.
 * `rootRef`/`sentinelRef` go on the scrolling container and a marker
 * element after the last rendered item, respectively — `root` matters
 * because it's usually a nested scrollable section, not the viewport.
 *
 * Verified this actually fires on a real scroll (not just jsdom) — see
 * App.tsx's exercises grid, which uses the same approach directly.
 */
export function useLoadMoreOnScroll<T extends HTMLElement = HTMLElement>(
  totalCount: number,
  pageSize: number,
  enabled = true
) {
  const [visibleCount, setVisibleCount] = useState(pageSize)

  // Reset pagination whenever the underlying count changes (list grew,
  // shrank, or is a different list entirely) — the "adjust state during
  // render" pattern React recommends in place of a setState-in-effect
  // cascade.
  const [countedTotal, setCountedTotal] = useState(totalCount)
  if (countedTotal !== totalCount) {
    setCountedTotal(totalCount)
    setVisibleCount(pageSize)
  }

  const hasMore = visibleCount < totalCount
  const rootRef = useRef<T>(null)
  const sentinelRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const root = rootRef.current
    const sentinel = sentinelRef.current
    if (!enabled || !root || !sentinel || !hasMore) return

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry?.isIntersecting) {
          setVisibleCount((count) => Math.min(count + pageSize, totalCount))
        }
      },
      { root, rootMargin: "600px 0px" }
    )
    observer.observe(sentinel)
    return () => observer.disconnect()
  }, [enabled, hasMore, pageSize, totalCount])

  return { hasMore, rootRef, sentinelRef, visibleCount }
}
