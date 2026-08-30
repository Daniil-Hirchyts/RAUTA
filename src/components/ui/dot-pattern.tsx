import { useId, type SVGProps } from "react"

import { cn } from "@/lib/utils"

type DotPatternProps = SVGProps<SVGSVGElement> & {
  cr?: number
  cx?: number
  cy?: number
  height?: number
  width?: number
  x?: number
  y?: number
}

export function DotPattern({
  className,
  cr = 1,
  cx = 1,
  cy = 1,
  height = 16,
  width = 16,
  x = 0,
  y = 0,
  ...props
}: DotPatternProps) {
  const id = useId()

  return (
    <svg
      aria-hidden="true"
      className={cn(
        "pointer-events-none absolute inset-0 h-full w-full fill-muted-foreground",
        className
      )}
      {...props}
    >
      <defs>
        <pattern
          height={height}
          id={id}
          patternContentUnits="userSpaceOnUse"
          patternUnits="userSpaceOnUse"
          width={width}
          x={x}
          y={y}
        >
          <circle cx={cx} cy={cy} r={cr} />
        </pattern>
      </defs>
      <rect fill={`url(#${id})`} height="100%" strokeWidth={0} width="100%" />
    </svg>
  )
}
