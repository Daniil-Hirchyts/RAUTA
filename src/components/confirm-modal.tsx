import { useEffect, useState } from "react"

import { createPortal } from "react-dom"
import { AnimatePresence, MotionConfig, motion } from "motion/react"

import { Button } from "@/components/ui/button"
import { triggerHaptic } from "@/lib/haptics"

export type ConfirmationKind =
  "clear-data" | "delete-workout" | "discard-session" | "finish-workout"

/**
 * transitions.dev's "Modal open/close": the panel scales up from 0.96 as it
 * fades in over 250ms and leaves faster than it arrives — 150ms — on the
 * smooth-out curve the rest of the shell already uses. The asymmetry is the
 * point: an answer should feel quicker than the question.
 */
const EASE_SMOOTH_OUT = [0.22, 1, 0.36, 1] as const
const OPEN = { duration: 0.25, ease: EASE_SMOOTH_OUT }
const CLOSE = { duration: 0.15, ease: EASE_SMOOTH_OUT }

const CONFIRMATION_COPY: Record<
  ConfirmationKind,
  {
    action: string
    description: string
    title: string
    tone: "default" | "destructive"
  }
> = {
  "clear-data": {
    action: "Continue",
    description:
      "Every workout, favorite, equipment preset, and preference is removed from this device and iCloud.",
    title: "Clear all data?",
    tone: "destructive",
  },
  "delete-workout": {
    action: "Delete workout",
    description: "This workout will be permanently removed from this device.",
    title: "Delete workout?",
    tone: "destructive",
  },
  "discard-session": {
    action: "Discard session",
    description:
      "The timer and everything checked off are lost. The workout itself stays saved.",
    title: "Discard this session?",
    tone: "destructive",
  },
  "finish-workout": {
    action: "Finish workout",
    description:
      "Your session progress and elapsed time will be saved to your history.",
    title: "Finish workout?",
    tone: "default",
  },
}

/**
 * Every confirmation in the app is this modal: a question about a single tap
 * is not worth a screen of its own, and the answer reads better with the page
 * it applies to still on screen behind it. `kind` drives it — null is closed.
 */
export function ConfirmModal({
  kind,
  onCancel,
  onConfirm,
}: {
  kind: ConfirmationKind | null
  onCancel: () => void
  onConfirm: () => void
}) {
  // Modals belong to the shell, not to the page that asked: a page layer is
  // transformed and paint-contained, and its command band sits outside it
  // entirely — a modal rendered in place could not cover the buttons it is
  // asking about.
  const [host] = useState(
    () =>
      document.querySelector<HTMLElement>(".app-shell-frame") ?? document.body
  )
  // Clearing everything asks twice: the second pass is the one that says the
  // data is not coming back.
  const [clearConfirmed, setClearConfirmed] = useState(false)
  const [asked, setAsked] = useState(kind)
  if (kind !== asked) {
    setAsked(kind)
    if (kind) setClearConfirmed(false)
  }

  useEffect(() => {
    if (!kind) return
    const dismissOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") onCancel()
    }
    document.addEventListener("keydown", dismissOnEscape)
    return () => document.removeEventListener("keydown", dismissOnEscape)
  }, [kind, onCancel])

  const copy = kind ? CONFIRMATION_COPY[kind] : null
  const finalClear = kind === "clear-data" && clearConfirmed
  const title = finalClear ? "This cannot be undone" : copy?.title
  const description = finalClear
    ? "Export a backup first if you may need any of it later."
    : copy?.description
  const action = finalClear ? "Delete everything" : copy?.action

  return createPortal(
    <MotionConfig reducedMotion="user">
      <AnimatePresence>
        {kind && copy ? (
          <motion.div
            animate={{ opacity: 1 }}
            // Undimmed: the page behind stays readable, and the panel earns
            // its separation with a shadow. This layer is here to catch the
            // taps and the scrolling that would land on the page underneath.
            className="absolute inset-0 z-[70] grid touch-none place-items-center p-5"
            exit={{ opacity: 0, transition: CLOSE }}
            initial={{ opacity: 0 }}
            onPointerDown={(event) => {
              if (event.target === event.currentTarget) onCancel()
            }}
            transition={OPEN}
          >
            <motion.div
              animate={{ opacity: 1, scale: 1 }}
              aria-label={title}
              aria-modal="true"
              className="w-full max-w-[21.5rem] rounded-3xl border border-border bg-card p-3 shadow-[0_28px_64px_-16px_rgb(0_0_0/0.85)]"
              exit={{ opacity: 0, scale: 0.96, transition: CLOSE }}
              initial={{ opacity: 0, scale: 0.96 }}
              role="dialog"
              transition={OPEN}
            >
              <div className="px-3 pt-3 pb-1 text-center">
                <h2 className="text-lg font-black tracking-[-0.02em]">
                  {title}
                </h2>
                <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
                  {description}
                </p>
              </div>
              <div className="mt-4 flex items-center gap-2">
                <Button className="flex-1" onClick={onCancel} variant="ghost">
                  Cancel
                </Button>
                <Button
                  className="flex-1"
                  onClick={() => {
                    if (kind === "clear-data" && !clearConfirmed) {
                      triggerHaptic("medium")
                      setClearConfirmed(true)
                      return
                    }
                    triggerHaptic(
                      kind === "finish-workout" ? "success" : "warning"
                    )
                    onConfirm()
                  }}
                  variant={
                    copy.tone === "destructive" ? "destructive" : "default"
                  }
                >
                  {action}
                </Button>
              </div>
            </motion.div>
          </motion.div>
        ) : null}
      </AnimatePresence>
    </MotionConfig>,
    host
  )
}
