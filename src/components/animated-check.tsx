import { Check } from "lucide-react"

import { cn } from "@/lib/utils"

export function AnimatedCheck({
  checked,
  className,
}: {
  checked: boolean
  className?: string
}) {
  return (
    <span
      aria-hidden="true"
      className={cn(
        "t-check-box grid place-items-center rounded-full border",
        className
      )}
      data-checked={checked}
    >
      <Check className="t-check-mark size-4" strokeWidth={3} />
    </span>
  )
}
