import { LikeButton } from "@/components/like-button"
import { Button } from "@/components/ui/button"
import {
  Drawer,
  DrawerContent,
  DrawerFooter,
  DrawerTitle,
} from "@/components/ui/drawer"
import { ProgressiveBlur } from "@/components/ui/progressive-blur"
import { EXERCISE_ANIMATION_FILTER, exerciseAnimation } from "@/lib/visuals"
import { useFavorites } from "@/store/use-favorites"
import type { ExerciseSummary } from "@/types"

export function ExerciseDetailDrawer({
  exercise,
  onAddToWorkout,
  onOpenChange,
  open,
}: {
  exercise: ExerciseSummary | null
  onAddToWorkout: (exercise: ExerciseSummary) => void
  onOpenChange: (open: boolean) => void
  open: boolean
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
          className="absolute top-3 right-3 z-30 grid size-11 shrink-0 place-items-center rounded-full border border-border bg-card text-muted-foreground shadow-lg shadow-black/20 transition-[transform,color,background-color] duration-250 hover:bg-muted active:scale-90"
          iconClassName="size-5"
          liked={isFavorite}
          onClick={() => toggleFavorite(exercise.id)}
        />

        <div className="min-h-0 flex-1 overflow-y-auto px-4 pt-16 pb-[calc(6.5rem+env(safe-area-inset-bottom))]">
          <div className="isolate aspect-square w-full shrink-0 overflow-hidden rounded-3xl bg-[#111113]">
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
            <ol className="mt-4 list-decimal space-y-2.5 pl-5 text-base text-muted-foreground">
              {exercise.instructions.map((step, index) => (
                <li className="pl-1 leading-relaxed" key={index}>
                  {step}
                </li>
              ))}
            </ol>
          )}
        </div>

        <DrawerFooter className="absolute inset-x-0 bottom-0 z-20 bg-transparent pt-4 pb-[calc(1rem+env(safe-area-inset-bottom))]">
          <ProgressiveBlur
            className="absolute inset-x-0 -top-6 bottom-0 rounded-b-[inherit]"
            direction="bottom"
          />
          <Button
            className="relative h-12 w-full rounded-2xl text-base font-semibold"
            onClick={() => onAddToWorkout(exercise)}
          >
            Select
          </Button>
        </DrawerFooter>
      </DrawerContent>
    </Drawer>
  )
}
