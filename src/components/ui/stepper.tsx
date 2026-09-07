import { useCallback, useEffect, useRef } from "react"
import { Minus, Plus } from "lucide-react"

import { triggerHaptic } from "@/lib/haptics"
import { cn } from "@/lib/utils"

/** How long a held button waits before it starts repeating, and how quickly
 *  the repeats close up. Getting from an empty bar to 80 kg is a hold, not
 *  thirty-two taps — but a single deliberate tap must still be a single step. */
const FIRST_REPEAT_MS = 420
const REPEAT_DECAY = 0.72
const FASTEST_REPEAT_MS = 60

function useHoldRepeat(action: () => void) {
  // The repeat outlives the render that started it, so it reads the action
  // through a ref that every render refreshes rather than capturing one.
  const latest = useRef(action)
  useEffect(() => {
    latest.current = action
  })
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const stop = useCallback(() => {
    if (timer.current) clearTimeout(timer.current)
    timer.current = null
  }, [])

  const start = useCallback(() => {
    stop()
    latest.current()
    let delay = FIRST_REPEAT_MS
    const tick = () => {
      latest.current()
      delay = Math.max(FASTEST_REPEAT_MS, delay * REPEAT_DECAY)
      timer.current = setTimeout(tick, delay)
    }
    timer.current = setTimeout(tick, delay)
  }, [stop])

  useEffect(() => stop, [stop])
  return { start, stop }
}

function StepButton({
  ariaLabel,
  disabled,
  onStep,
  children,
}: {
  ariaLabel: string
  disabled: boolean
  onStep: () => void
  children: React.ReactNode
}) {
  const { start, stop } = useHoldRepeat(() => {
    triggerHaptic("selection")
    onStep()
  })

  return (
    <button
      aria-label={ariaLabel}
      className={cn(
        "interactive-spring grid size-12 shrink-0 touch-none place-items-center rounded-2xl border border-border bg-card text-primary",
        disabled && "opacity-35"
      )}
      data-haptics="off"
      disabled={disabled}
      onClick={(event) => {
        // Pointer input already stepped on press; only keyboard activation,
        // which reports no click coordinates, still has to be answered.
        if (event.detail !== 0) return
        triggerHaptic("selection")
        onStep()
      }}
      onLostPointerCapture={stop}
      onPointerCancel={stop}
      onPointerDown={(event) => {
        if (event.button !== 0 && event.pointerType === "mouse") return
        // The press owns the pointer until it is released. Without capture the
        // repeat is at the mercy of a boundary event — the panel growing under
        // a still finger is enough to end the hold a plate or two in. Capture
        // is an enhancement, so a pointer the browser will not hand over must
        // not take the step with it.
        try {
          event.currentTarget.setPointerCapture?.(event.pointerId)
        } catch {
          /* Released pointers cannot be captured; the press still counts. */
        }
        start()
      }}
      onPointerUp={stop}
      type="button"
    >
      {children}
    </button>
  )
}

/**
 * A number nudged rather than typed.
 *
 * Mid-set, a keyboard is the wrong instrument: it covers the screen to collect
 * two digits that only ever move by one plate or one rep. The buttons are the
 * whole control — no hover, no drag, both thumbs' worth of target — and they
 * repeat while held so a long way up is still one gesture.
 */
export function Stepper({
  className,
  display,
  canDecrement,
  label,
  onStep,
  unit,
}: {
  className?: string
  display: string
  label: string
  onStep: (direction: 1 | -1) => void
  unit?: string
  canDecrement?: boolean
}) {
  return (
    <div
      aria-label={label}
      className={cn(
        "flex items-center gap-1.5 rounded-3xl border border-border bg-muted/35 p-1.5",
        className
      )}
      role="group"
    >
      <StepButton
        ariaLabel={`Decrease ${label.toLowerCase()}`}
        disabled={canDecrement === false}
        onStep={() => onStep(-1)}
      >
        <Minus className="size-5" />
      </StepButton>
      <div className="min-w-0 flex-1 text-center">
        <p className="text-[10px] font-black tracking-[0.18em] text-muted-foreground uppercase">
          {label}
        </p>
        <output
          aria-live="polite"
          className="mt-0.5 block truncate text-[21px] leading-none font-black tracking-[-0.02em] tabular-nums"
        >
          {display}
          {unit ? (
            <span className="ml-1 text-[13px] font-bold text-muted-foreground">
              {unit}
            </span>
          ) : null}
        </output>
      </div>
      <StepButton
        ariaLabel={`Increase ${label.toLowerCase()}`}
        disabled={false}
        onStep={() => onStep(1)}
      >
        <Plus className="size-5" />
      </StepButton>
    </div>
  )
}
