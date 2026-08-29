import { Check, Heart } from "lucide-react"

import { cn } from "@/lib/utils"
import { EXERCISE_ANIMATION_FILTER, exerciseAnimation } from "@/lib/visuals"
import { useFavorites } from "@/store/use-favorites"
import type { ExerciseSummary } from "@/types"

export function ExerciseCard({
  exercise,
  index = 0,
  onOpenDetail,
  onToggleSelect,
  selected = false,
  selectMode = false,
}: {
  exercise: ExerciseSummary
  index?: number
  onOpenDetail: (exercise: ExerciseSummary) => void
  onToggleSelect: (id: string) => void
  selected?: boolean
  selectMode?: boolean
}) {
  const isFavorite = useFavorites((state) =>
    state.favoriteIds.includes(exercise.id)
  )
  const toggleFavorite = useFavorites((state) => state.toggleFavorite)

  const activate = () =>
    selectMode ? onToggleSelect(exercise.id) : onOpenDetail(exercise)

  return (
    <article
      className="exercise-card t-stagger-line relative overflow-hidden rounded-[22px] border border-border bg-card/90 shadow-sm shadow-black/10 backdrop-blur-sm transition-transform duration-150 active:scale-[0.98]"
      style={{ transitionDelay: `${Math.min(index, 6) * 40}ms` }}
    >
      <div
        aria-label={
          selectMode
            ? `Select ${exercise.name}`
            : `View ${exercise.name} details`
        }
        aria-pressed={selectMode ? selected : undefined}
        className="block w-full cursor-pointer text-left"
        onClick={activate}
        onKeyDown={(event) => {
          if (event.key === "Enter" || event.key === " ") {
            event.preventDefault()
            activate()
          }
        }}
        role="button"
        tabIndex={0}
      >
        <div className="isolate aspect-square overflow-hidden bg-[#111113]">
          <img
            alt={`${exercise.name} demonstration`}
            className="h-full w-full object-contain mix-blend-screen"
            decoding="async"
            draggable={false}
            fetchPriority="low"
            loading="lazy"
            src={exerciseAnimation(exercise)}
            style={{ filter: EXERCISE_ANIMATION_FILTER }}
          />
        </div>
        {/* Fixed height (not content-driven) so every card is identical
            regardless of grid row or 1- vs 2-line exercise names. */}
        <div className="flex h-[4.5rem] items-center px-3.5">
          <h3 className="line-clamp-2 text-base leading-snug font-semibold tracking-[-0.01em] capitalize">
            {exercise.name}
          </h3>
        </div>
      </div>

      <button
        aria-label={
          isFavorite
            ? `Remove ${exercise.name} from favorites`
            : `Add ${exercise.name} to favorites`
        }
        aria-pressed={isFavorite}
        className="absolute top-2.5 right-2.5 grid size-8 place-items-center rounded-full border border-white/10 bg-black/55 text-white backdrop-blur-sm transition-transform duration-150 active:scale-90"
        onClick={(event) => {
          event.stopPropagation()
          toggleFavorite(exercise.id)
        }}
        type="button"
      >
        <Heart
          className={cn(
            "size-4 transition-transform",
            isFavorite && "fill-primary text-primary"
          )}
        />
      </button>

      {selectMode && (
        <div
          aria-hidden="true"
          className={cn(
            "absolute top-2.5 left-2.5 grid size-8 place-items-center rounded-full border backdrop-blur-sm transition-colors",
            selected
              ? "border-primary bg-primary text-primary-foreground"
              : "border-white/20 bg-black/55 text-transparent"
          )}
        >
          <Check className="size-4.5" strokeWidth={3} />
        </div>
      )}
    </article>
  )
}
