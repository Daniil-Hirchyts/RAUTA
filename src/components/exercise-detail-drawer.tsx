import { LikeButton } from "@/components/like-button"
import { Button } from "@/components/ui/button"
import {
  Drawer,
  DrawerContent,
  DrawerControls,
  DrawerTitle,
} from "@/components/ui/drawer"
import { triggerHaptic } from "@/lib/haptics"
import { EXERCISE_ANIMATION_FILTER, exerciseAnimation } from "@/lib/visuals"
import { useFavorites } from "@/store/use-favorites"
import type { ExerciseSummary } from "@/types"

export function ExerciseDetailDrawer({
  exercise,
  onSelectExercise,
  onOpenChange,
  open,
  selected,
}: {
  exercise: ExerciseSummary | null
  /**
   * Omit to hide the select action entirely. Opened from a saved workout the
   * exercise is already part of it, so there is nothing to select into.
   */
  onSelectExercise?: (exercise: ExerciseSummary) => void
  onOpenChange: (open: boolean) => void
  open: boolean
  selected: boolean
}) {
  const isFavorite = useFavorites((state) =>
    exercise ? state.favoriteIds.includes(exercise.id) : false
  )
  const toggleFavorite = useFavorites((state) => state.toggleFavorite)

  if (!exercise) return null

  return (
    <Drawer onOpenChange={onOpenChange} open={open} swipeDirection="down">
      <DrawerContent className="mx-auto max-w-[430px] [--drawer-inset:0px]">
        <LikeButton
          aria-label={
            isFavorite
              ? `Remove ${exercise.name} from favorites`
              : `Add ${exercise.name} to favorites`
          }
          className="interactive-spring absolute top-4 right-4 z-30 grid size-11 place-items-center rounded-full border border-border bg-card text-muted-foreground shadow-lg shadow-black/20 active:bg-card/90 active:text-white"
          data-haptics="off"
          iconClassName="size-5"
          liked={isFavorite}
          onClick={() => {
            triggerHaptic("selection")
            toggleFavorite(exercise.id)
          }}
        />
        <div
          className="min-h-0 flex-1 overflow-y-auto px-4 pt-16 pb-6"
        >
          <div className="isolate aspect-square w-full shrink-0 overflow-hidden rounded-3xl bg-popover">
            <img
              alt={`${exercise.name} demonstration`}
              className="h-full w-full object-contain mix-blend-screen"
              decoding="async"
              draggable={false}
              fetchPriority="high"
              src={exerciseAnimation(exercise)}
              style={{ filter: EXERCISE_ANIMATION_FILTER }}
            />
          </div>

          <DrawerTitle className="mt-4 text-xl leading-snug font-bold capitalize">
            {exercise.name}
          </DrawerTitle>

          {exercise.instructions.length > 0 && (
            <ol className="mt-4 list-decimal space-y-2.5 pl-5 text-base text-muted-foreground marker:font-semibold marker:text-primary">
              {exercise.instructions.map((step, index) => (
                <li className="pl-1 leading-relaxed" key={index}>
                  {step}
                </li>
              ))}
            </ol>
          )}
        </div>

        {onSelectExercise ? (
          <DrawerControls>
            <Button
              className="w-full"
              disabled={selected}
              onClick={() => onSelectExercise(exercise)}
              size="cta"
            >
              {selected ? "Selected" : "Select"}
            </Button>
          </DrawerControls>
        ) : null}
      </DrawerContent>
    </Drawer>
  )
}
