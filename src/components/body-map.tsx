import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type PointerEvent,
} from "react"
import { FlipHorizontal2 } from "lucide-react"

import bodyPathData from "@/data/body-paths.generated.json"
import { installDirectTouchTarget, triggerHaptic } from "@/lib/haptics"
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
  const hapticTargetRef = useRef<HTMLDivElement>(null)
  const svgRef = useRef<SVGSVGElement>(null)

  useEffect(
    () =>
      installDirectTouchTarget(hapticTargetRef.current, (point) => {
        const overlay = hapticTargetRef.current
        const svg = svgRef.current
        if (!overlay || !svg) return

        // The iOS haptic switch has to sit above the SVG to receive a real
        // finger tap. Temporarily remove that overlay from hit-testing so we
        // can resolve the irregular SVG muscle region directly underneath it.
        const previousPointerEvents = overlay.style.pointerEvents
        overlay.style.pointerEvents = "none"
        const muscleRegion = document
          .elementsFromPoint(point.clientX, point.clientY)
          .map((element) => element.closest<SVGElement>("[data-muscle]"))
          .find((element) => element && svg.contains(element))
        overlay.style.pointerEvents = previousPointerEvents

        const muscle = muscleRegion?.dataset.muscle
        if (muscle && isMuscleId(muscle)) onToggle(muscle)
      }),
    [onToggle]
  )

  return (
    <div className="relative flex h-full min-h-0 w-full items-center justify-center">
      <svg
        aria-label={`${label} muscle map`}
        className="block h-full max-h-full max-w-full overflow-visible"
        preserveAspectRatio="xMidYMid meet"
        ref={svgRef}
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
      <div
        aria-hidden="true"
        className="absolute inset-0 z-20"
        data-haptics="off"
        ref={hapticTargetRef}
      />
    </div>
  )
}

export function BodyMap({ onToggle, selectedMuscles }: BodyMapProps) {
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

  const handleToggle = useCallback(
    (muscle: MuscleId) => {
      if (suppressClick.current) return
      onToggle(muscle)
    },
    [onToggle]
  )

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
        onPointerUp={endSwipe}
      >
        <BodyFigure
          label={label}
          onToggle={handleToggle}
          selectedMuscles={selectedMuscles}
          view={view}
        />
      </div>
    </div>
  )
}
