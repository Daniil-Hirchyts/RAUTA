import { useCallback, useRef, useState, type ReactNode } from "react"

import {
  MorphingPopover,
  MorphingPopoverContent,
  MorphingPopoverTrigger,
} from "@/components/ui/morphing-popover"
import { cn } from "@/lib/utils"

const PANEL_VARIANTS = {
  animate: { opacity: 1 },
  exit: { opacity: 0 },
  initial: { opacity: 0 },
}

/**
 * The app's one way to ask something on top of a page: the control morphs into
 * a panel where it already sits, so the page behind keeps both its content and
 * its scroll position. Anything that would otherwise be a full-screen detour
 * for a single question — a date, a confirmation — belongs here.
 */
export function AppPopover({
  ariaLabel,
  children,
  className,
  onOpenChange,
  open,
  panelClassName,
  panelHeight,
  panelLabel,
  trigger,
  triggerClassName,
}: {
  ariaLabel?: string
  children: ReactNode
  className?: string
  onOpenChange: (open: boolean) => void
  open: boolean
  panelClassName?: string
  /** Roughly what the panel measures. Only ever used to clamp its position, so
   *  a control near the bottom of the screen cannot open a panel off it. */
  panelHeight: number
  panelLabel: string
  trigger: ReactNode
  triggerClassName?: string
}) {
  // The panel is portalled to the shell frame: a page layer is transformed and
  // paint-contained, and a header clips its own title, so a panel any larger
  // than its trigger would be cut off where it stands.
  const [frame, setFrame] = useState<HTMLElement | null>(null)
  const [top, setTop] = useState(0)
  const control = useRef<HTMLDivElement | null>(null)
  const anchor = useCallback((node: HTMLDivElement | null) => {
    control.current = node
    setFrame(node?.closest<HTMLElement>(".app-shell-frame") ?? null)
  }, [])

  // Portalling costs the panel its place in the flow, so it is put back where
  // the control is: the panel opens out of the control itself rather than
  // travelling to a fixed corner of the screen.
  const anchorToControl = () => {
    if (!control.current || !frame) return
    const trigger = control.current.getBoundingClientRect()
    const host = frame.getBoundingClientRect()
    // A control can sit in the command band, below the page itself. The panel
    // it opens should not: it is answering a question about the page, so it
    // stays on the page's own surface.
    const surface = frame.querySelector(".app-surface")?.getBoundingClientRect()
    const floor = (surface?.bottom ?? host.bottom) - host.top - panelHeight - 8
    setTop(Math.max(8, Math.min(trigger.top - host.top, floor)))
  }

  return (
    <MorphingPopover
      className={className}
      onOpenChange={(next) => {
        if (next) anchorToControl()
        onOpenChange(next)
      }}
      open={open}
      ref={anchor}
      variants={PANEL_VARIANTS}
    >
      <MorphingPopoverTrigger
        aria-label={ariaLabel}
        className={triggerClassName}
        data-haptics="off"
      >
        {trigger}
      </MorphingPopoverTrigger>
      <MorphingPopoverContent
        aria-label={panelLabel}
        // Invisible rather than dimmed: it exists only to stop the page
        // scrolling out from under an open panel, which would leave the panel
        // pointing at nothing when it morphs back.
        backdropClassName="absolute inset-0 z-[65] touch-none"
        className={cn(
          "right-4 left-4 z-[70] mx-auto max-w-[21.5rem] rounded-3xl border border-border bg-card p-3 shadow-[0_28px_64px_-16px_rgb(0_0_0/0.85)]",
          panelClassName
        )}
        container={frame}
        style={{ top }}
      >
        {children}
      </MorphingPopoverContent>
    </MorphingPopover>
  )
}
