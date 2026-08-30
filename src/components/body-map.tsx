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

function PreviewFigure({
  selectedMuscles,
  view,
}: {
  selectedMuscles: MuscleId[]
  view: BodyView
}) {
  const [, , widthAttr, heightAttr] = view.viewBox.split(" ")

  return (
    <svg
      aria-hidden="true"
      className="block h-full min-w-0 flex-1 overflow-visible"
      preserveAspectRatio="xMidYMid meet"
      style={{ aspectRatio: `${widthAttr} / ${heightAttr}` }}
      viewBox={view.viewBox}
    >
      {view.parts.map((part) => {
        const muscle = isMuscleId(part.slug) ? part.slug : null
        const selected = muscle ? selectedMuscles.includes(muscle) : false

        return (
          <g
            className={
              muscle
                ? cn("muscle-region", selected && "is-selected")
                : "body-silhouette"
            }
            data-muscle={muscle ?? undefined}
            key={part.slug}
          >
            {part.paths.map((path, index) => (
              <path d={path} key={`${part.slug}-${index}`} />
            ))}
          </g>
        )
      })}
    </svg>
  )
}

export function BodyPreview({
  className,
  selectedMuscles,
}: {
  className?: string
  selectedMuscles: MuscleId[]
}) {
  const selectedLabels = selectedMuscles
    .map((muscle) => MUSCLE_LABELS[muscle])
    .join(", ")

  return (
    <div
      aria-label={
        selectedLabels
          ? `Target muscles: ${selectedLabels}`
          : "No target muscles"
      }
      className={cn("flex h-16 w-24 items-center gap-0.5", className)}
      role="img"
    >
      <PreviewFigure selectedMuscles={selectedMuscles} view={body.front} />
      <PreviewFigure selectedMuscles={selectedMuscles} view={body.back} />
    </div>
  )
}

function BodyFigure({
  label,
  onToggle,
  selectedMuscles,
  view,
}: BodyMapProps & { label: "Front" | "Back"; view: BodyView }) {
  const [, , widthAttr, heightAttr] = view.viewBox.split(" ")

  return (
    <div className="relative flex h-full min-h-0 w-full items-center justify-center">
      <svg
        aria-label={`${label} muscle map`}
        className="block h-full max-h-full max-w-full overflow-visible"
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
              onClick={(event) => {
                // Real pointer taps are handled by BodyMap's pointer-up logic.
                // Keep zero-detail clicks for assistive technology/programmatic
                // activation without double-toggling normal mouse/touch input.
                if (event.detail === 0) onToggle(muscle)
              }}
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

export function BodyMap({ onToggle, selectedMuscles }: BodyMapProps) {
  const [side, setSide] = useState<Side>("front")
  const label = side === "front" ? "Front" : "Back"
  const view = side === "front" ? body.front : body.back
  const swipeStartX = useRef<number | null>(null)

  const flipSide = () => {
    triggerHaptic("selection")
    setSide((current) => (current === "front" ? "back" : "front"))
  }

  const onPointerDown = (event: PointerEvent) => {
    swipeStartX.current = event.clientX
  }

  const onPointerUp = (event: PointerEvent) => {
    if (swipeStartX.current === null) return

    const dx = event.clientX - swipeStartX.current
    swipeStartX.current = null

    if (Math.abs(dx) > SWIPE_THRESHOLD) {
      flipSide()
      return
    }

    // Handle the actual muscle selection on pointer-up instead of relying on
    // Safari to synthesize a click for an SVG <g>. This works for mouse, pen,
    // and touch and keeps the muscle map independent from the iOS haptics
    // overlay implementation used by ordinary HTML buttons.
    const target = event.target
    if (!(target instanceof Element)) return

    const muscleRegion = target.closest<SVGElement>("[data-muscle]")
    const muscle = muscleRegion?.dataset.muscle
    if (muscle && isMuscleId(muscle)) onToggle(muscle)
  }

  return (
    <div className="flex h-full min-h-0 w-full flex-col">
      <div className="mb-1 flex shrink-0 items-center justify-between">
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
        onPointerUp={onPointerUp}
      >
        <BodyFigure
          label={label}
          onToggle={onToggle}
          selectedMuscles={selectedMuscles}
          view={view}
        />
      </div>
    </div>
  )
}
