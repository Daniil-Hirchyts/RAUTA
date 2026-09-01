import { cn } from "@/lib/utils"

/**
 * Subtle organic film grain texture for the app's lit surfaces.
 * Uses procedural fractal noise generated via SVG feTurbulence at 100% dimensions,
 * ensuring continuous non-repeating grain without grid or tile patterns.
 * Kept at very low opacity (barely visible) for a gentle analog feel.
 *
 * It belongs to whatever surface renders it — a screen surface or a drawer —
 * and never to the shell frame around them, so it fills its positioned parent
 * rather than the viewport.
 */
export function AppGrain({ className }: { className?: string }) {
  return (
    <div
      aria-hidden="true"
      className={cn(
        "pointer-events-none absolute inset-0 z-30 overflow-hidden select-none",
        className
      )}
    >
      <svg
        className="size-full opacity-[0.08]"
        height="100%"
        width="100%"
        xmlns="http://www.w3.org/2000/svg"
      >
        <filter id="app-shell-grain" x="0%" y="0%" width="100%" height="100%">
          <feTurbulence
            baseFrequency="0.75"
            numOctaves="3"
            stitchTiles="noStitch"
            type="fractalNoise"
          />
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 1
                    0 0 0 0 1
                    0 0 0 0 1
                    1 0 0 0 0"
          />
        </filter>
        <rect
          fill="white"
          filter="url(#app-shell-grain)"
          height="100%"
          width="100%"
        />
      </svg>
    </div>
  )
}
