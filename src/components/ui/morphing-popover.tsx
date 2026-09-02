import {
  createContext,
  use,
  useEffect,
  useId,
  useRef,
  useState,
  type ComponentProps,
  type ReactNode,
} from "react"

import { createPortal } from "react-dom"
import {
  AnimatePresence,
  MotionConfig,
  motion,
  type Transition,
  type Variants,
} from "motion/react"

import { cn } from "@/lib/utils"

/**
 * Ported from motion-primitives' morphing popover
 * (https://motion-primitives.com/docs/morphing-popover). The trigger and the
 * panel share a `layoutId`, so opening morphs the control itself into the
 * panel — the page underneath keeps its content instead of being pushed
 * aside or swapped out for the panel's.
 *
 * Two additions this app needs. `container` portals the open panel, because
 * a page layer is transformed and paint-contained: a panel wider or taller
 * than its trigger's corner of the page would otherwise be clipped away.
 * `backdropClassName` opts into a dimming layer that also swallows the
 * scrolling and taps behind an open panel, which a phone-sized surface wants
 * and a desktop popover does not.
 */
const TRANSITION: Transition = {
  type: "spring",
  bounce: 0.1,
  duration: 0.4,
}

type MorphingPopoverContextValue = {
  close: () => void
  isOpen: boolean
  open: () => void
  uniqueId: string
  variants?: Variants
}

const MorphingPopoverContext =
  createContext<MorphingPopoverContextValue | null>(null)

function usePopoverContext(component: string) {
  const context = use(MorphingPopoverContext)
  if (!context) {
    throw new Error(`${component} must be used within MorphingPopover`)
  }
  return context
}

export function MorphingPopover({
  children,
  className,
  defaultOpen = false,
  onOpenChange,
  open: controlledOpen,
  transition = TRANSITION,
  variants,
  ...props
}: {
  children: ReactNode
  className?: string
  defaultOpen?: boolean
  onOpenChange?: (open: boolean) => void
  open?: boolean
  transition?: Transition
  variants?: Variants
} & ComponentProps<"div">) {
  const uniqueId = useId()
  const [uncontrolledOpen, setUncontrolledOpen] = useState(defaultOpen)
  const isOpen = controlledOpen ?? uncontrolledOpen

  const setOpen = (next: boolean) => {
    if (controlledOpen === undefined) setUncontrolledOpen(next)
    onOpenChange?.(next)
  }

  return (
    <MorphingPopoverContext.Provider
      value={{
        close: () => setOpen(false),
        isOpen,
        open: () => setOpen(true),
        uniqueId,
        variants,
      }}
    >
      <MotionConfig reducedMotion="user" transition={transition}>
        <div
          {...props}
          className={cn("relative flex items-center justify-center", className)}
        >
          {children}
        </div>
      </MotionConfig>
    </MorphingPopoverContext.Provider>
  )
}

export function MorphingPopoverTrigger({
  children,
  className,
  ...props
}: ComponentProps<typeof motion.button>) {
  const context = usePopoverContext("MorphingPopoverTrigger")

  return (
    <motion.div
      layoutId={`popover-trigger-${context.uniqueId}`}
      onClick={context.open}
    >
      <motion.button
        {...props}
        aria-controls={`popover-content-${context.uniqueId}`}
        aria-expanded={context.isOpen}
        className={className}
        layoutId={`popover-label-${context.uniqueId}`}
        type="button"
      >
        {children}
      </motion.button>
    </motion.div>
  )
}

export function MorphingPopoverContent({
  backdropClassName,
  children,
  className,
  container,
  ...props
}: {
  backdropClassName?: string
  container?: HTMLElement | null
} & ComponentProps<typeof motion.div>) {
  const context = usePopoverContext("MorphingPopoverContent")
  const ref = useRef<HTMLDivElement>(null)
  const { close, isOpen } = context

  useEffect(() => {
    if (!isOpen) return

    // One pointerdown listener covers the backdrop, the page behind it and
    // the trigger itself, so the panel needs no dismiss affordance of its own.
    const dismissOutside = (event: PointerEvent) => {
      if (!ref.current?.contains(event.target as Node)) close()
    }
    const dismissOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") close()
    }

    document.addEventListener("pointerdown", dismissOutside)
    document.addEventListener("keydown", dismissOnEscape)
    return () => {
      document.removeEventListener("pointerdown", dismissOutside)
      document.removeEventListener("keydown", dismissOnEscape)
    }
  }, [close, isOpen])

  const layer = (
    <AnimatePresence>
      {isOpen ? (
        <>
          {backdropClassName === undefined ? null : (
            <motion.div
              animate={{ opacity: 1 }}
              aria-hidden="true"
              className={backdropClassName}
              exit={{ opacity: 0 }}
              initial={{ opacity: 0 }}
              key={`${context.uniqueId}-backdrop`}
            />
          )}
          <motion.div
            {...props}
            animate="animate"
            aria-modal="true"
            className={cn("absolute overflow-hidden", className)}
            exit="exit"
            id={`popover-content-${context.uniqueId}`}
            initial="initial"
            key={context.uniqueId}
            layoutId={`popover-trigger-${context.uniqueId}`}
            ref={ref}
            role="dialog"
            variants={context.variants}
          >
            {children}
          </motion.div>
        </>
      ) : null}
    </AnimatePresence>
  )

  return container ? createPortal(layer, container) : layer
}
