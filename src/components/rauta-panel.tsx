import type { ReactNode } from "react"
import { AnimatePresence, motion, useReducedMotion } from "motion/react"

import { cn } from "@/lib/utils"

import { Button } from "./ui/button"

const BOTTOM_CONTROL_GAP = 12
const BOTTOM_FOOTER_HEIGHT = 80

/** Something tapping the character offers to do. */
export type RautaAction = {
  /** What the action says. It says it in words: a button carrying a sentence
   *  does not also need a picture of it. */
  label: ReactNode
  onSelect: () => void
  /** The one thing the screen would rather you did. */
  primary?: boolean
  disabled?: boolean
}

/**
 * The section RAUTA speaks from.
 *
 * The character has no bubble and no dialog of its own: everything it says
 * arrives here, in a panel pinned to one edge of the screen that the character
 * stands against. With nothing to say the panel is not there at all, and when
 * there is something to choose it grows to hold the choices rather than
 * opening a window over the page.
 *
 * Which edge it sits on, and how much room it leaves for the character, are
 * decided by whoever renders it — this only has to look like one thing whether
 * it is holding a sentence or a sentence and three buttons.
 */
export function RautaPanel({
  actions,
  alert,
  className,
  footer,
  line,
  meta,
  open,
  onToggle,
  place,
  reserve,
  style,
  visible,
}: {
  actions?: RautaAction[]
  /** The line is a refusal or a failure, and should interrupt rather than
   *  wait its turn to be read out. */
  alert?: boolean
  className?: string
  /** The screen's own instrument, living in the panel rather than in a second
   *  bar beside it — a running timer, say. Its presence keeps the panel up
   *  whether or not the character has anything to say. */
  footer?: ReactNode
  /** What the character is saying. */
  line?: string | null
  /** A quieter second line: what the screen is set to, not what RAUTA says. */
  meta?: ReactNode
  open: boolean
  onToggle?: () => void
  place: "bottom" | "top"
  /** Room along the panel's own edge for the character standing against it. */
  reserve: number
  style?: React.CSSProperties
  visible: boolean
}) {
  const reduced = useReducedMotion()
  const offer = actions && actions.length > 0
  // The panel grows because what is inside it grows. Each inserted section
  // animates its own height so the content already pinned to the panel edge
  // does not get translated by a parent layout transform.
  const away = place === "bottom" ? 14 : -14
  return (
    <AnimatePresence>
      {visible ? (
        <motion.section
          key="rauta-panel"
          aria-label="RAUTA"
          className={cn(
            // A plain radius rather than the page's softened corner: this
            // panel is read as a piece of the shell rather than as a card on
            // it, and the shell's own surface is drawn the same way.
            "frosted-glass content-glow content-glow--subtle pointer-events-auto absolute flex flex-col overflow-hidden rounded-(--app-card-radius) border corner-round",
            place === "bottom" && "justify-end",
            className
          )}
          style={{
            ...style,
            ...(footer && place === "bottom"
              ? { paddingBottom: BOTTOM_FOOTER_HEIGHT }
              : {}),
          }}
          initial={{ opacity: 0, y: reduced ? 0 : away, height: 0 }}
          animate={{ opacity: 1, y: 0, height: "auto" }}
          exit={{ opacity: 0, y: reduced ? 0 : away, height: 0 }}
          transition={{
            duration: reduced ? 0 : 0.22,
            ease: [0.32, 0.72, 0, 1],
          }}
        >
          <AnimatePresence initial={false}>
            {line ? (
              <motion.div
                key="message"
                className="overflow-hidden"
                style={{ order: place === "bottom" ? 2 : 1 }}
                initial={{ height: reduced ? "auto" : 0, opacity: 0 }}
                animate={{ height: "auto", opacity: 1 }}
                exit={{ height: reduced ? "auto" : 0, opacity: 0 }}
                transition={{
                  duration: reduced ? 0 : 0.26,
                  ease: [0.32, 0.72, 0, 1],
                }}
              >
                <div
                  className={cn(
                    "px-4 pt-4",
                    footer ? "pb-0" : place === "bottom" ? "pb-5" : "pb-4"
                  )}
                  style={{
                    ...(place === "top" || !footer
                      ? { paddingLeft: reserve, paddingRight: reserve }
                      : {}),
                  }}
                >
                  <button
                    className={cn(
                      "flex w-full items-center justify-center gap-3 text-center",
                      offer && "active:scale-[0.99]"
                    )}
                    type="button"
                    aria-expanded={offer ? open : undefined}
                    aria-label={offer ? "RAUTA actions" : undefined}
                    disabled={!offer}
                    onClick={onToggle}
                  >
                    <span className="min-w-0 flex-1">
                      <strong
                        className={cn(
                          "line-clamp-3 block text-center text-[15px] leading-snug font-semibold tracking-tight"
                        )}
                        role={alert ? "alert" : "status"}
                      >
                        {line}
                      </strong>
                      {meta ? (
                        <span className="mt-1 block truncate text-[12px] text-muted-foreground">
                          {meta}
                        </span>
                      ) : null}
                    </span>
                  </button>
                </div>
              </motion.div>
            ) : null}
          </AnimatePresence>
          <AnimatePresence initial={false}>
            {offer && open ? (
              <motion.div
                key="actions"
                className="overflow-hidden"
                style={{ order: place === "bottom" ? 1 : 2 }}
                initial={{ height: reduced ? "auto" : 0, opacity: 0 }}
                animate={{ height: "auto", opacity: 1 }}
                exit={{ height: reduced ? "auto" : 0, opacity: 0 }}
                transition={{
                  duration: reduced ? 0 : 0.26,
                  ease: [0.32, 0.72, 0, 1],
                }}
              >
                <div
                  className={cn(
                    "space-y-2 px-4 pt-4",
                    place === "bottom" ? "pb-6" : "pb-5"
                  )}
                >
                  {actions.map((action, index) => (
                    <Button
                      className="w-full justify-center"
                      disabled={action.disabled}
                      key={index}
                      onClick={action.onSelect}
                      variant={
                        place === "top"
                          ? "ghost"
                          : action.primary
                            ? "default"
                            : "secondary"
                      }
                    >
                      {action.label}
                    </Button>
                  ))}
                </div>
              </motion.div>
            ) : null}
          </AnimatePresence>
          {footer ? (
            <div
              className={cn(
                "px-4 pt-4",
                place === "bottom" ? "absolute inset-x-0 bottom-0 pb-5" : "pb-4"
              )}
              style={
                place === "bottom"
                  ? {
                      order: 3,
                      paddingLeft: reserve + BOTTOM_CONTROL_GAP,
                    }
                  : { order: 3 }
              }
            >
              {footer}
            </div>
          ) : null}
        </motion.section>
      ) : null}
    </AnimatePresence>
  )
}
