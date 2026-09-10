import { useCallback, useEffect, useLayoutEffect, useRef } from "react"

import { cn } from "@/lib/utils"

export type TabDef = {
  label: string
  /** A number worth putting on the tab — how many are in there. Left off, the
   *  tab is just its name. */
  count?: number
}

/**
 * Sliding-pill tab bar.
 *
 * The pill's position (translateX + width) is measured from the active
 * button's layout, then written as inline styles so CSS transitions can
 * tween between positions.  First paint and resize snap without animation.
 */
export function SlidingTabs({
  activeIndex,
  onChange,
  tabs,
}: {
  activeIndex: number
  onChange: (index: number) => void
  tabs: TabDef[]
}) {
  const barRef = useRef<HTMLDivElement>(null)
  const pillRef = useRef<HTMLSpanElement>(null)

  const syncPill = useCallback(
    (animate: boolean) => {
      const bar = barRef.current
      const pill = pillRef.current
      if (!bar || !pill) return
      const btn =
        bar.querySelectorAll<HTMLButtonElement>('[role="tab"]')[activeIndex]
      if (!btn) return

      if (!animate) {
        pill.style.transition = "none"
        // Force reflow so the "none" is flushed before we restore
        void pill.offsetWidth
      }
      pill.style.transform = `translateX(${btn.offsetLeft}px)`
      pill.style.width = `${btn.offsetWidth}px`
      if (!animate) {
        // Restore after one frame
        requestAnimationFrame(() => {
          pill.style.transition = ""
        })
      }
    },
    [activeIndex]
  )

  // Snap on first paint and whenever the active tab changes
  useLayoutEffect(() => {
    syncPill(true)
  }, [syncPill])

  // Snap (no animation) on first mount
  useEffect(() => {
    syncPill(false)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Snap (no animation) on resize
  useEffect(() => {
    const onResize = () => syncPill(false)
    window.addEventListener("resize", onResize)
    return () => window.removeEventListener("resize", onResize)
  }, [syncPill])

  return (
    <div className="t-tabs" ref={barRef} role="tablist">
      <span className="t-tabs-pill" ref={pillRef} aria-hidden="true" />
      {tabs.map((tab, i) => (
        <button
          aria-selected={i === activeIndex}
          className="t-tab"
          key={tab.label}
          onClick={() => onChange(i)}
          role="tab"
          type="button"
        >
          {tab.label}
          {tab.count === undefined ? null : (
            <span
              className={cn(
                "ml-1.5 rounded-full px-1.5 py-0.5 text-[10px] font-bold tabular-nums transition-colors",
                i === activeIndex
                  ? "bg-black/15 text-primary-foreground"
                  : "bg-muted/60 text-muted-foreground"
              )}
            >
              {tab.count}
            </span>
          )}
        </button>
      ))}
    </div>
  )
}
