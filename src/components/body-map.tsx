import { useRef, useState, type PointerEvent } from "react"
import { FlipHorizontal2 } from "lucide-react"

import bodyPathData from "@/data/body-paths.generated.json"
import { triggerHaptic } from "@/lib/haptics"
import { isMuscleId, MUSCLE_LABELS } from "@/lib/muscles"
import { cn } from "@/lib/utils"
import type { MuscleId } from "@/types"

type BodyPart = {
  slug: string
  paths: string[]
}

type BodyView = {
  viewBox: string
  parts: BodyPart[]
}

type BodyMapProps = {
  selectedMuscles: MuscleId[]
  onToggle: (muscle: MuscleId) => void
}

type Side = "front" | "back"

const SWIPE_THRESHOLD = 45

const body = bodyPathData as { front: BodyView; back: BodyView }

function BodyFigure({
  label,
  onToggle,
  selectedMuscles,
  view,
}: BodyMapProps & { label: "Front" | "Back"; view: BodyView }) {
  const [, , widthAttr, heightAttr] = view.viewBox.split(" ")

  return (
    <div className="flex h-full min-h-0 w-full items-center justify-center">
      <svg
        aria-label={`${label} muscle map`}
        className="block h-full max-w-full overflow-visible"
        preserveAspectRatio="xMidYMid meet"
        role="img"
        style={{ aspectRatio: `${widthAttr} / ${heightAttr}` }}
        viewBox={view.viewBox}
      >
        {view.parts.map((part) => {
          const muscle = isMuscleId(part.slug) ? part.slug : null
          const selected = muscle ? selectedMuscles.includes(muscle) : false

          if (!muscle) {
            return (
              <g aria-hidden="true" className="body-silhouette" key={part.slug}>
                {part.paths.map((path, index) => (
                  <path d={path} key={`${part.slug}-${index}`} />
                ))}
              </g>
            )
          }

          const accessibleLabel = `${label} ${MUSCLE_LABELS[muscle]}`

          return (
            <g
              aria-label={accessibleLabel}
              aria-pressed={selected}
              className={cn("muscle-region", selected && "is-selected")}
              data-muscle={muscle}
              key={part.slug}
              onClick={() => onToggle(muscle)}
              onKeyDown={(event) => {
                if (event.key === "Enter" || event.key === " ") {
                  event.preventDefault()
                  onToggle(muscle)
                }
              }}
              role="button"
              tabIndex={0}
            >
              <title>{accessibleLabel}</title>
              {part.paths.map((path, index) => (
                <path d={path} key={`${part.slug}-${index}`} />
              ))}
            </g>
          )
        })}
      </svg>
    </div>
  )
}

export function BodyMap(props: BodyMapProps) {
  const [side, setSide] = useState<Side>("front")
  const label = side === "front" ? "Front" : "Back"
  const view = side === "front" ? body.front : body.back

  // Lets a horizontal swipe flip the figure, same as the button — a swipe
  // still ends with a pointerup (and browser-synthesized click) on whatever
  // muscle region happens to be underneath, so we briefly suppress toggling
  // a muscle right after a swipe is detected.
  const swipeStartX = useRef<number | null>(null)
  const suppressClick = useRef(false)

  const flipSide = () => {
    triggerHaptic("selection")
    setSide((current) => (current === "front" ? "back" : "front"))
  }

  const handleToggle = (muscle: MuscleId) => {
    if (suppressClick.current) return
    props.onToggle(muscle)
  }

  const onPointerDown = (event: PointerEvent) => {
    swipeStartX.current = event.clientX
  }

  const endSwipe = (event: PointerEvent) => {
    if (swipeStartX.current === null) return
    const dx = event.clientX - swipeStartX.current
    swipeStartX.current = null
    if (Math.abs(dx) > SWIPE_THRESHOLD) {
      suppressClick.current = true
      flipSide()
      requestAnimationFrame(() => {
        suppressClick.current = false
      })
    }
  }

  return (
    <div className="flex h-full min-h-0 w-full flex-col">
      <div className="mb-3 flex shrink-0 items-center justify-between">
        <p className="text-xs font-bold tracking-[0.16em] text-muted-foreground uppercase">
          {label}
        </p>
        <button
          aria-label={`Show ${side === "front" ? "back" : "front"}`}
          className="grid size-10 place-items-center rounded-full border border-border bg-card text-foreground transition-colors duration-150 hover:bg-muted active:bg-muted"
          onClick={flipSide}
          type="button"
        >
          <FlipHorizontal2 className="size-4.5" />
        </button>
      </div>
      <div
        className="t-flip min-h-0 w-full flex-1 touch-pan-y"
        data-swipe-ignore
        key={side}
        onPointerCancel={() => {
          swipeStartX.current = null
        }}
        onPointerDown={onPointerDown}
        onPointerUp={endSwipe}
      >
        <BodyFigure
          {...props}
          label={label}
          onToggle={handleToggle}
          view={view}
        />
      </div>
    </div>
  )
}
