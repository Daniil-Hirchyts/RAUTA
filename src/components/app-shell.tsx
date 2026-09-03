import {
  useEffect,
  useRef,
  useState,
  type ComponentProps,
  type ReactNode,
  type RefObject,
} from "react"

import { createPortal } from "react-dom"

import { AppGrain } from "@/components/app-grain"
import { Button } from "@/components/ui/button"
import {
  ControlsHostContext,
  PageLayerContext,
  useControlsHost,
  usePageLayer,
} from "@/hooks/use-app-shell"
import { cn } from "@/lib/utils"

export function AppShell({
  children,
  commandsVisible,
  pageSwitching,
}: {
  children: ReactNode
  commandsVisible: boolean
  pageSwitching: boolean
}) {
  const [controlsHost, setControlsHost] = useState<HTMLDivElement | null>(null)

  return (
    <main
      className="app-shell-frame relative mx-auto grid h-(--app-viewport-height) w-full touch-pan-y overflow-hidden bg-(--app-shell) sm:max-w-[430px]"
      data-commands={commandsVisible ? "visible" : "hidden"}
      data-page-switching={pageSwitching ? "true" : undefined}
    >
      <ControlsHostContext.Provider value={controlsHost}>
        <div className="app-surface">{children}</div>
        <AppGrain className="app-surface-grain" />
        <div
          aria-live="off"
          className="app-controls-host"
          ref={setControlsHost}
        />
      </ControlsHostContext.Provider>
    </main>
  )
}

export function PageLayerProvider({
  active,
  children,
  entryId,
}: {
  active: boolean
  children: ReactNode
  entryId: string
}) {
  return (
    <PageLayerContext.Provider value={{ active, entryId }}>
      {children}
    </PageLayerContext.Provider>
  )
}

/** Compatibility wrapper for pages that predate the stationary shell. */
export function AppScreen({
  children,
}: {
  bottomControls?: boolean
  children: ReactNode
}) {
  return (
    <div className="app-screen">
      {/* The top edge fade lives inside the page rather than on the shell: a
          page layer is transformed, so it opens a stacking context the title
          cannot escape, and a shell-owned scrim would paint over the very
          title it is meant to sit behind. */}
      <div aria-hidden="true" className="app-top-scrim" />
      {children}
    </div>
  )
}

/** A page's actions render into the shell-owned command band. */
export function AppControls({
  children,
  className,
  transitionKey,
}: {
  children: ReactNode
  className?: string
  transitionKey: string
}) {
  const host = useControlsHost()
  const page = usePageLayer()

  // No crossfade between action sets, and so no outgoing layer to keep around
  // for one: the band shows the active page's buttons and nothing else, which
  // makes them hittable the instant the page is.
  const controls = (
    <footer
      aria-hidden={!page.active}
      className={cn("app-controls", className)}
      data-active={page.active ? "true" : undefined}
      data-page-entry={page.entryId}
      data-slot="app-controls"
      data-transition-key={transitionKey}
      inert={!page.active}
    >
      {children}
    </footer>
  )

  return host ? createPortal(controls, host) : controls
}

/** Compatibility wrapper while page components shed their old surface owner. */
export function AppSurface({ children }: { children: ReactNode }) {
  return <div className="app-page-surface">{children}</div>
}

/** How far the scroller has to travel in one direction before the title
 *  slides away, and the shorter distance back that brings it in again. */
const HIDE_TRAVEL = 72
const SHOW_TRAVEL = 44

export function AppShellHeader({
  above,
  below,
  className,
  left,
  right,
  scrollRef,
  title,
}: {
  above?: ReactNode
  below?: ReactNode
  className?: string
  left?: ReactNode
  right?: ReactNode
  scrollRef?: RefObject<HTMLElement | null>
  title: ReactNode
}) {
  const [hidden, setHidden] = useState(false)
  const lastScrollTop = useRef(0)
  const travel = useRef(0)

  useEffect(() => {
    const scroller = scrollRef?.current
    lastScrollTop.current = scroller?.scrollTop ?? 0
    travel.current = 0
    const resetFrame = requestAnimationFrame(() => setHidden(false))
    if (!scroller) return () => cancelAnimationFrame(resetFrame)

    const syncVisibility = () => {
      const scrollTop = scroller.scrollTop
      const isScrollable = scroller.scrollHeight > scroller.clientHeight + 1

      if (!isScrollable || scrollTop <= 8) {
        travel.current = 0
        setHidden(false)
      } else {
        // Toggling on a single 6px frame made the title flicker away on the
        // smallest flick and snap back just as abruptly. Instead accumulate
        // travel in one direction — the accumulator zeroes the moment the
        // finger reverses — so the title only moves once the scroll is
        // clearly a deliberate one, and hiding asks for more of it than
        // bringing the title back does.
        const delta = scrollTop - lastScrollTop.current
        if (delta !== 0 && Math.sign(delta) !== Math.sign(travel.current)) {
          travel.current = 0
        }
        travel.current = Math.max(
          -2 * SHOW_TRAVEL,
          Math.min(2 * HIDE_TRAVEL, travel.current + delta)
        )

        if (travel.current > HIDE_TRAVEL) setHidden(true)
        else if (travel.current < -SHOW_TRAVEL) setHidden(false)
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
      data-above={above ? "true" : undefined}
      data-below={below ? "true" : undefined}
      data-hidden={hidden ? "true" : undefined}
    >
      <div className="app-shell-header-row">
        <div className="app-shell-header-action">{left}</div>
        <div className="app-shell-header-center">
          {above ? <div className="app-shell-header-above">{above}</div> : null}
          <h1 className="app-shell-header-title" tabIndex={-1}>
            {title}
          </h1>
        </div>
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
