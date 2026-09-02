import { cn } from "@/lib/utils"

/** A cached, tiled grain layer owned by the stationary shell. */
export function AppGrain({ className }: { className?: string }) {
  return (
    <div
      aria-hidden="true"
      className={cn(
        "app-grain pointer-events-none absolute inset-0 select-none",
        className
      )}
    />
  )
}
