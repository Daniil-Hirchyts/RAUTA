import { useEffect, useState, type ReactNode } from "react"

import { createPortal } from "react-dom"
import { AnimatePresence, MotionConfig, motion } from "motion/react"

import { cn } from "@/lib/utils"

/**
 * transitions.dev's "Modal open/close": the panel scales up from 0.96 as it
 * fades in over 250ms and leaves faster than it arrives — 150ms — on the
 * smooth-out curve the rest of the shell already uses. The asymmetry is the
 * point: an answer should feel quicker than the question.
 */
const EASE_SMOOTH_OUT = [0.22, 1, 0.36, 1] as const
const OPEN = { duration: 0.25, ease: EASE_SMOOTH_OUT }
const CLOSE = { duration: 0.15, ease: EASE_SMOOTH_OUT }

/**
 * The app's one way to ask something on top of a page: a centred panel over a
 * dimmed page, which stays exactly where it was underneath. Anything that
 * would otherwise be a full-screen detour for a single question — a date, a
 * confirmation — belongs here.
 */
export function AppModal({
  children,
  label,
  onClose,
  open,
  panelClassName,
}: {
  children: ReactNode
  label: string
  onClose: () => void
  open: boolean
  panelClassName?: string
}) {
  // Modals belong to the shell, not to the page that asked: a page layer is
  // transformed and paint-contained, and its command band sits outside it
  // entirely — a modal rendered in place could not cover the buttons it is
  // asking about.
  const [host] = useState(
    () =>
      document.querySelector<HTMLElement>(".app-shell-frame") ?? document.body
  )

  useEffect(() => {
    if (!open) return
    const dismissOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose()
    }
    document.addEventListener("keydown", dismissOnEscape)
    return () => document.removeEventListener("keydown", dismissOnEscape)
  }, [onClose, open])

  return createPortal(
    <MotionConfig reducedMotion="user">
      <AnimatePresence>
        {open ? (
          <motion.div
            animate={{ opacity: 1 }}
            // The scrim dims the page — the panel is the only thing to answer
            // while it is up — and catches the taps and the scrolling that
            // would otherwise land underneath it.
            className="absolute inset-0 z-[70] grid touch-none place-items-center bg-black/60 p-5"
            exit={{ opacity: 0, transition: CLOSE }}
            initial={{ opacity: 0 }}
            onPointerDown={(event) => {
              if (event.target === event.currentTarget) onClose()
            }}
            transition={OPEN}
          >
            <motion.div
              animate={{ opacity: 1, scale: 1 }}
              aria-label={label}
              aria-modal="true"
              className={cn(
                "w-full max-w-[21.5rem] rounded-3xl border border-border bg-card p-3 shadow-[0_28px_64px_-16px_rgb(0_0_0/0.85)]",
                panelClassName
              )}
              exit={{ opacity: 0, scale: 0.96, transition: CLOSE }}
              initial={{ opacity: 0, scale: 0.96 }}
              role="dialog"
              transition={OPEN}
            >
              {children}
            </motion.div>
          </motion.div>
        ) : null}
      </AnimatePresence>
    </MotionConfig>,
    host
  )
}
