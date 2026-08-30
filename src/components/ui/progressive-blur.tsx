import type { CSSProperties, HTMLAttributes } from "react"

import { cn } from "@/lib/utils"

type Direction = "top" | "right" | "bottom" | "left"

const GRADIENT_ANGLES: Record<Direction, number> = {
  top: 0,
  right: 90,
  bottom: 180,
  left: 270,
}

/**
 * A soft, gradually-intensifying blur — the "frosted glass" fade you'd put
 * behind a floating bottom bar so scrolling content dissolves into it
 * instead of cutting off sharply. CSS has no native blur gradient, so this
 * stacks several full-size layers, each blurred a little more than the
 * last and masked to a thin band, so the *combined* result reads as one
 * continuous blur that ramps up toward `direction`.
 * See https://motion-primitives.com/docs/progressive-blur
 */
export function ProgressiveBlur({
  blurIntensity = 0.75,
  blurLayers = 8,
  className,
  direction = "bottom",
  ...props
}: HTMLAttributes<HTMLDivElement> & {
  blurIntensity?: number
  blurLayers?: number
  direction?: Direction
}) {
  const layers = Math.max(blurLayers, 2)
  const segmentSize = 1 / (layers + 1)
  const angle = GRADIENT_ANGLES[direction]

  return (
    <div
      aria-hidden="true"
      className={cn("pointer-events-none relative", className)}
      {...props}
    >
      {Array.from({ length: layers }).map((_, index) => {
        const stops = [
          index * segmentSize,
          (index + 1) * segmentSize,
          (index + 2) * segmentSize,
          (index + 3) * segmentSize,
        ]
          .map(
            (position, stopIndex) =>
              `rgba(255,255,255,${stopIndex === 1 || stopIndex === 2 ? 1 : 0}) ${position * 100}%`
          )
          .join(", ")
        const mask = `linear-gradient(${angle}deg, ${stops})`

        return (
          <div
            className="absolute inset-0"
            key={index}
            style={
              {
                WebkitMaskImage: mask,
                backdropFilter: `blur(${index * blurIntensity}px)`,
                maskImage: mask,
              } as CSSProperties
            }
          />
        )
      })}
    </div>
  )
}
