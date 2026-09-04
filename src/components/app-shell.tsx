import {
  isValidElement,
  useEffect,
  useRef,
  useState,
  type ComponentProps,
  type ReactNode,
  type RefObject,
} from "react"

import { createPortal } from "react-dom"
import { LayoutGroup, MotionConfig } from "motion/react"

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
}: {
  children: ReactNode
  commandsVisible: boolean
}) {
  const [controlsHost, setControlsHost] = useState<HTMLDivElement | null>(null)

  return (
    <main
      className="app-shell-frame relative mx-auto grid h-(--app-viewport-height) w-full touch-pan-y overflow-hidden bg-(--app-shell) sm:max-w-[430px]"
      data-commands={commandsVisible ? "visible" : "hidden"}
    >
      {/* One group spanning both the page stack and the command band: the
          band is a portal, so the pair only share a `layoutId` because they
          share this React ancestor, not because they sit near each other in
          the DOM. */}
      <MotionConfig reducedMotion="user">
        <LayoutGroup>
          <ControlsHostContext.Provider value={controlsHost}>
            <div className="app-surface">{children}</div>
            <AppGrain className="app-surface-grain" />
            <div
              aria-live="off"
              className="app-controls-host"
              ref={setControlsHost}
            />
          </ControlsHostContext.Provider>
        </LayoutGroup>
      </MotionConfig>
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

/** One band per blur step, softest last. The radii and the slice each one
 *  covers live in index.css; all this has to do is put seven boxes there for
 *  them to land on. */
const BLUR_BANDS = [0, 1, 2, 3, 4, 5, 6]

/** Compatibility wrapper for pages that predate the stationary shell. */
export function AppScreen({
  children,
}: {
  bottomControls?: boolean
  children: ReactNode
}) {
  return (
    <div className="app-screen">
      {/* The top edge treatment lives inside the page rather than on the
          shell: a page layer is transformed, so it opens a stacking context
          the title cannot escape, and a shell-owned scrim would paint over the
          very title it is meant to sit behind. Being inside the layer is also
          what gives the blur something to read — the layer carries
          `contain: paint`, which makes it the backdrop root the bands sample
          the scrolling content from. */}
      <div aria-hidden="true" className="app-top-scrim">
        {BLUR_BANDS.map((band) => (
          <div className="app-top-scrim-blur" key={band} />
        ))}
        <div className="app-top-scrim-tint" />
      </div>
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

  // Only the page in view fills the band. Keeping every mounted page's
  // buttons stacked here would be cheaper, but it would also mean several
  // pages claiming the same command role at once — and a role can only be
  // handed from one page to the next if exactly one page holds it.
  if (!page.active) return null

  const controls = (
    <footer
      className={cn("app-controls", className)}
      data-active="true"
      data-page-entry={page.entryId}
      data-slot="app-controls"
      data-transition-key={transitionKey}
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
  subtitle,
  title,
  titleClassName,
  titleMultiline,
  titleSize,
}: {
  above?: ReactNode
  below?: ReactNode
  className?: string
  left?: ReactNode
  right?: ReactNode
  scrollRef?: RefObject<HTMLElement | null>
  subtitle?: ReactNode
  title: ReactNode
  titleClassName?: string
  titleMultiline?: boolean
  titleSize?: "default" | "md" | "sm" | "xs"
}) {
  const [hidden, setHidden] = useState(false)
  const lastScrollTop = useRef(0)
  const travel = useRef(0)

  const effectiveSize =
    titleSize ??
    (titleMultiline && typeof title === "string"
      ? title.length > 50
        ? "xs"
        : title.length > 34
          ? "sm"
          : title.length > 22
            ? "md"
            : "default"
      : undefined)

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
          <h1
            className={cn("app-shell-header-title", titleClassName)}
            data-multiline={titleMultiline ? "true" : undefined}
            data-size={
              effectiveSize && effectiveSize !== "default"
                ? effectiveSize
                : undefined
            }
            tabIndex={-1}
          >
            {title}
          </h1>
          {subtitle ? (
            <p
              className="app-shell-header-subtitle"
              data-testid="stage-subtitle"
              key={
                isValidElement(subtitle) && subtitle.key != null
                  ? String(subtitle.key)
                  : undefined
              }
            >
              {subtitle}
            </p>
          ) : null}
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

/** A round tool in the command band.
 *
 *  Which icon it carries and what pressing it does belong to the page; how
 *  big the button is, what it is made of, and how big the icon inside it
 *  draws belong to the band. Said once here because they had already drifted
 *  apart — the same X in four places, in two greys and two icon sizes, so
 *  that "cancel" looked like a different control depending on which step you
 *  had reached. A page that means something stronger than a tool — deleting
 *  a workout, say — still passes its own `variant`. */
export function AppControlButton({
  className,
  variant = "ghost",
  ...props
}: ComponentProps<typeof Button>) {
  return (
    <Button
      {...props}
      className={cn("app-control-button", className)}
      size="icon-cta"
      variant={variant}
    />
  )
}
