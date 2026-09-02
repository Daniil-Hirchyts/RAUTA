import {
  useEffect,
  useRef,
  useState,
  type ComponentProps,
  type ReactNode,
  type RefObject,
} from "react"

import { AppGrain } from "@/components/app-grain"
import { Button } from "@/components/ui/button"
import { DrawerHostContext } from "@/hooks/use-drawer-host"
import { cn } from "@/lib/utils"

/**
 * Drawers belong to the app, not to the browser window. They portal into this
 * host, which is the shell's inner area — so a sheet slides up inside the
 * frame and takes its curve, rather than spanning the viewport and painting
 * over the shell around it.
 *
 * Wraps the shell's contents and renders the host after them, so the host is
 * never inside a page that transforms during a route change.
 */
export function AppDrawerHost({ children }: { children: ReactNode }) {
  const hostRef = useRef<HTMLDivElement>(null)

  return (
    <DrawerHostContext.Provider value={hostRef}>
      {children}
      <div className="app-drawer-host" ref={hostRef} />
    </DrawerHostContext.Provider>
  )
}

/**
 * The three parts every top-level route is built from. They were copied into
 * each screen before, which is how the header padding drifted apart and how
 * the grain had to be added in four places at once. Owning the scaffold here
 * means a new screen gets the whole treatment by construction.
 */
export function AppScreen({
  bottomControls = false,
  children,
}: {
  bottomControls?: boolean
  children: ReactNode
}) {
  return (
    <div
      className="app-screen"
      data-bottom-controls={bottomControls ? "true" : undefined}
    >
      {children}
    </div>
  )
}

/** The clipped content surface, and the only thing the grain belongs to. */
export function AppSurface({ children }: { children: ReactNode }) {
  return (
    <div className="app-surface">
      <AppGrain />
      <div aria-hidden="true" className="app-top-scrim" />
      {children}
    </div>
  )
}

export function AppShellHeader({
  below,
  className,
  left,
  right,
  scrollRef,
  title,
}: {
  below?: ReactNode
  className?: string
  left?: ReactNode
  right?: ReactNode
  scrollRef?: RefObject<HTMLElement | null>
  title: ReactNode
}) {
  const [hidden, setHidden] = useState(false)
  const lastScrollTop = useRef(0)

  useEffect(() => {
    const scroller = scrollRef?.current
    lastScrollTop.current = scroller?.scrollTop ?? 0
    const resetFrame = requestAnimationFrame(() => setHidden(false))
    if (!scroller) return () => cancelAnimationFrame(resetFrame)

    const syncVisibility = () => {
      const scrollTop = scroller.scrollTop
      const isScrollable = scroller.scrollHeight > scroller.clientHeight + 1

      if (!isScrollable || scrollTop <= 8) {
        setHidden(false)
      } else {
        const delta = scrollTop - lastScrollTop.current
        if (delta > 6) setHidden(true)
        if (delta < -6) setHidden(false)
      }

      lastScrollTop.current = scrollTop
    }

    const resizeObserver =
      typeof ResizeObserver === "undefined"
        ? null
        : new ResizeObserver(syncVisibility)
    resizeObserver?.observe(scroller)

    const mutationObserver = new MutationObserver(syncVisibility)
    mutationObserver.observe(scroller, { childList: true, subtree: true })
    scroller.addEventListener("scroll", syncVisibility, { passive: true })
    window.addEventListener("resize", syncVisibility)
    const frame = requestAnimationFrame(syncVisibility)

    return () => {
      cancelAnimationFrame(frame)
      cancelAnimationFrame(resetFrame)
      resizeObserver?.disconnect()
      mutationObserver.disconnect()
      scroller.removeEventListener("scroll", syncVisibility)
      window.removeEventListener("resize", syncVisibility)
    }
  }, [scrollRef])

  return (
    <header
      className={cn("app-shell-header shrink-0", className)}
      data-below={below ? "true" : undefined}
      data-hidden={hidden ? "true" : undefined}
    >
      <div className="app-shell-header-row">
        <div className="app-shell-header-action">{left}</div>
        <h1 className="app-shell-header-title">{title}</h1>
        <div className="app-shell-header-action">{right}</div>
      </div>
      {below ? <div className="app-shell-header-below">{below}</div> : null}
    </header>
  )
}

export function AppHeaderButton({
  className,
  ...props
}: ComponentProps<typeof Button>) {
  return (
    <Button
      {...props}
      className={cn("app-shell-header-button", className)}
      size="icon"
      variant="ghost"
    />
  )
}
