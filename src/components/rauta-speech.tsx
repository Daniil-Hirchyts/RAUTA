import { motion } from "motion/react"
import type { ReactNode } from "react"

import { cn } from "@/lib/utils"

export function RautaSpeech({
  children,
  className,
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <motion.div
      animate={{ opacity: 1, scale: 1, y: 0 }}
      className={cn(
        "relative rounded-[1.35rem] border border-border/80 bg-card px-4 py-3 shadow-[0_12px_28px_rgba(0,0,0,0.18)]",
        className
      )}
      initial={{ opacity: 0, scale: 0.96, y: 5 }}
      transition={{ type: "spring", stiffness: 420, damping: 32 }}
    >
      <span
        aria-hidden="true"
        className="absolute top-7 -left-1.5 size-3 rotate-45 border-b border-l border-border/80 bg-card"
      />
      <span className="mb-1 block text-[10px] font-black tracking-[0.18em] text-primary uppercase">
        RAUTA
      </span>
      {children}
    </motion.div>
  )
}
