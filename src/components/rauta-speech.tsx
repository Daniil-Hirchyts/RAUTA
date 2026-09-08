import { AnimatePresence, motion, useReducedMotion } from "motion/react"
import type { ReactNode } from "react"

import { cn } from "@/lib/utils"

export function RautaSpeech({
  children,
  className,
  visible = true,
}: {
  children: ReactNode
  className?: string
  visible?: boolean
}) {
  const reduced = useReducedMotion()
  return (
    <AnimatePresence>
      {visible ? (
        <motion.div
          key="speech"
          animate={{ opacity: 1, scale: 1, y: 0 }}
          exit={{ opacity: 0, scale: reduced ? 1 : 0.98, y: reduced ? 0 : 3 }}
          className={cn(
            "relative rounded-2xl border border-primary/20 bg-card/95 px-4 py-3 shadow-lg shadow-black/20 backdrop-blur-md",
            className
          )}
          initial={{
            opacity: 0,
            scale: reduced ? 1 : 0.98,
            y: reduced ? 0 : 5,
          }}
          transition={{ duration: reduced ? 0 : 0.18 }}
        >
          <span
            aria-hidden="true"
            className="mb-1.5 flex items-center gap-1.5 text-[9px] font-bold tracking-[0.16em] text-primary"
          >
            <span className="size-1 rounded-full bg-primary" /> RAUTA
          </span>
          {children}
        </motion.div>
      ) : null}
    </AnimatePresence>
  )
}
