import type { ReactNode } from "react"

import { cn } from "@/lib/utils"

/** Keep an optional command mounted while its space opens and closes. */
export function MorphingActionSlot({
  children,
  className,
  visible,
}: {
  children: ReactNode
  className?: string
  visible: boolean
}) {
  return (
    <div
      aria-hidden={!visible}
      className={cn("morphing-action-slot", className)}
      data-visible={visible ? "true" : undefined}
      inert={!visible}
    >
      <div className="morphing-action-slot-inner">{children}</div>
    </div>
  )
}
