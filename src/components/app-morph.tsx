import { useEffect, useState, type CSSProperties, type ReactNode } from "react"

import { motion } from "motion/react"

import { usePageLayer } from "@/hooks/use-app-shell"
import { cn } from "@/lib/utils"
import { CONTROL_MORPH_TRANSITION, MORPH_TRANSITION } from "@/lib/motion"

/**
 * A box that exists on two pages and travels between them.
 *
 * Pages in this app never unmount — the stack keeps them around so back
 * navigation restores scroll and local state — which is normally fatal to a
 * shared-element transition: two live elements claiming one `layoutId` leave
 * motion nothing to hand off between. So only the page you can actually see
 * claims the id. The moment navigation flips which layer is active, the
 * outgoing page drops back to a plain box in the same commit that the
 * incoming page raises one, and motion reads that as one element moving.
 */
export function AppMorph({
  children,
  className,
  morphId,
  radius,
}: {
  children: ReactNode
  className?: string
  /** Stable across both pages — that identity is the whole mechanism. */
  morphId: string
  /** Inline rather than in `className` so motion can correct the radius as
   *  the box changes proportion; a class-set radius smears during flight. */
  radius?: CSSProperties["borderRadius"]
}) {
  const page = usePageLayer()

  if (!page.active) {
    return (
      <div className={className} style={{ borderRadius: radius }}>
        {children}
      </div>
    )
  }

  return (
    <motion.div
      className={className}
      layoutId={morphId}
      style={{ borderRadius: radius }}
      transition={MORPH_TRANSITION}
    >
      {children}
    </motion.div>
  )
}

/**
 * A role in the command band rather than a particular button: "the primary
 * action", "the destructive icon". Two pages that both fill the same role
 * hand the box between them, so a stationary band re-arranges itself instead
 * of blinking to a new set of buttons.
 *
 * Only the active page renders controls at all (see `AppControls`), so unlike
 * `AppMorph` this never has to stand down — whichever page owns the band owns
 * the role.
 */
export function AppControlMorph({
  children,
  className,
  role,
}: {
  children: ReactNode
  className?: string
  role: string
}) {
  return (
    <motion.div
      className={cn("app-control-morph", className)}
      layoutId={`app-controls:${role}`}
      transition={CONTROL_MORPH_TRANSITION}
    >
      {/* Its own projection node, so the button inside keeps its proportions
          while the box around it is still being stretched into place. */}
      <motion.div
        className="app-control-morph-inner"
        layout
        transition={CONTROL_MORPH_TRANSITION}
      >
        {children}
      </motion.div>
    </motion.div>
  )
}

/** How long a label takes to leave before its replacement starts arriving.
 *  Matches the `--text-swap-dur` half-cycle the CSS is written around. */
const SWAP_MS = 150

/**
 * Swaps one piece of text for another in place — the old line blurs upward
 * and out, the new one arrives from below. Used for anything whose container
 * outlives its contents: a stage title, or the label on a button that is
 * morphing rather than being replaced.
 */
export function TextSwap({
  children,
  className,
}: {
  /** Changing this string is what triggers the swap. */
  children: string
  className?: string
}) {
  const [shown, setShown] = useState(children)
  const [entering, setEntering] = useState(false)
  const exiting = children !== shown

  useEffect(() => {
    if (!exiting) return
    const reduceMotion = window.matchMedia?.(
      "(prefers-reduced-motion: reduce)"
    ).matches
    const timeout = window.setTimeout(
      () => {
        setShown(children)
        setEntering(true)
      },
      reduceMotion ? 0 : SWAP_MS
    )
    return () => window.clearTimeout(timeout)
  }, [children, exiting])

  useEffect(() => {
    if (!entering) return
    const frame = requestAnimationFrame(() =>
      requestAnimationFrame(() => setEntering(false))
    )
    return () => cancelAnimationFrame(frame)
  }, [entering])

  return (
    <span
      className={cn(
        "t-text-swap",
        exiting && "is-exit",
        entering && "is-enter-start",
        className
      )}
    >
      {shown}
    </span>
  )
}
