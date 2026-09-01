import type { ReactNode } from "react"

import { AppGrain } from "@/components/app-grain"
import { cn } from "@/lib/utils"

/**
 * The three parts every top-level route is built from. They were copied into
 * each screen before, which is how the header padding drifted apart and how
 * the grain had to be added in four places at once. Owning the scaffold here
 * means a new screen gets the whole treatment by construction.
 */
export function AppScreen({
  bottomControls = false,
  children,
}: {
  bottomControls?: boolean
  children: ReactNode
}) {
  return (
    <div
      className="app-screen"
      data-bottom-controls={bottomControls ? "true" : undefined}
    >
      {children}
    </div>
  )
}

/** The clipped content surface, and the only thing the grain belongs to. */
export function AppSurface({ children }: { children: ReactNode }) {
  return (
    <div className="app-surface">
      <AppGrain />
      {children}
    </div>
  )
}

export function AppShellHeader({
  children,
  className,
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <header className={cn("app-shell-header shrink-0 px-5 py-4", className)}>
      {children}
    </header>
  )
}
