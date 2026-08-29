import bodyPathData from "@/data/body-paths.generated.json"
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

const body = bodyPathData as { front: BodyView; back: BodyView }

function BodyFigure({
  label,
  onToggle,
  selectedMuscles,
  view,
}: BodyMapProps & { label: "Front" | "Back"; view: BodyView }) {
  return (
    <figure className="min-w-0">
      <svg
        aria-label={`${label} muscle map`}
        className="block h-[294px] w-full overflow-visible"
        preserveAspectRatio="xMidYMid meet"
        role="img"
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
      <figcaption className="mt-1 text-center text-[10px] font-medium tracking-[0.12em] text-muted-foreground uppercase">
        {label}
      </figcaption>
    </figure>
  )
}

export function BodyMap(props: BodyMapProps) {
  return (
    <div className="grid grid-cols-2 gap-1">
      <BodyFigure {...props} label="Front" view={body.front} />
      <BodyFigure {...props} label="Back" view={body.back} />
    </div>
  )
}
