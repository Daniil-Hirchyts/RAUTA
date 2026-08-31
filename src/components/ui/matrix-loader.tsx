import type { CSSProperties } from "react"

import { cn } from "@/lib/utils"

export type MatrixLoaderVariant = "scan" | "twinkle" | "orbit" | "pulse"

const CELLS = Array.from({ length: 16 }, (_, index) => index)

/* Cell indices in the 4x4 grid:
     0  1  2  3
     4  5  6  7
     8  9 10 11
    12 13 14 15                                                          */
const CORNERS = [0, 3, 12, 15]
const TWINKLE_ORDER = [7, 2, 11, 5, 14, 9, 0, 12, 3, 15, 6, 10, 13, 1, 8, 4]
const ORBIT_RING = [1, 2, 7, 11, 14, 13, 8, 4]
const PULSE_INNER = [5, 6, 9, 10]

/**
 * How far into the shared colour cycle a cell lights up, as a fraction of
 * `--matrix-cycle`. `null` means the cell never lights (orbit's centre and
 * corners hold steady) — the CSS turns its animation off rather than
 * parking it at a delay.
 */
function cellDelay(variant: MatrixLoaderVariant, index: number) {
  switch (variant) {
    // Left to right, a column at a time.
    case "scan":
      return (index % 4) / 10
    // Scattered order, so no two neighbours light together.
    case "twinkle":
      return TWINKLE_ORDER.indexOf(index) / 16
    // One lit dot travelling the outer ring, clockwise.
    case "orbit": {
      const step = ORBIT_RING.indexOf(index)
      return step === -1 ? null : step / 8
    }
    // Centre first, everything else a beat behind it.
    case "pulse":
      return PULSE_INNER.includes(index) ? 0 : 0.16
  }
}

/**
 * A sixteen-dot loader for the app's short waits. `label` is what a screen
 * reader announces; size and colour come from the `--matrix-*` custom
 * properties, so a caller on a tight surface can shrink or tint it inline.
 */
export function MatrixLoader({
  className,
  label = "Loading",
  rounded = false,
  style,
  variant = "scan",
}: {
  className?: string
  label?: string
  rounded?: boolean
  style?: CSSProperties
  variant?: MatrixLoaderVariant
}) {
  return (
    <div
      aria-label={label}
      className={cn("t-matrix", className)}
      data-variant={variant}
      role="status"
      style={style}
    >
      {CELLS.map((index) => {
        const delay = cellDelay(variant, index)
        return (
          <i
            className={cn(
              rounded && CORNERS.includes(index) && "is-gap",
              delay === null && "is-still"
            )}
            key={index}
            style={
              delay === null ? undefined : ({ "--d": delay } as CSSProperties)
            }
          />
        )
      })}
    </div>
  )
}
