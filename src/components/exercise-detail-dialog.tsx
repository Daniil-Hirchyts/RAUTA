import { Heart, ListPlus } from "lucide-react"

import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogTitle,
} from "@/components/ui/dialog"
import { cn } from "@/lib/utils"
import { EXERCISE_GIF_FILTER, exerciseGif } from "@/lib/visuals"
import { useFavorites } from "@/store/use-favorites"
import type { ExerciseSummary } from "@/types"

export function ExerciseDetailDialog({
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
    <Dialog onOpenChange={onOpenChange} open={open}>
      <DialogContent>
        <div className="isolate aspect-square w-full shrink-0 overflow-hidden rounded-3xl bg-[#111113]">
          <img
            alt={`${exercise.name} demonstration`}
            className="h-full w-full object-contain mix-blend-screen"
            draggable={false}
            src={exerciseGif(exercise)}
            style={{ filter: EXERCISE_GIF_FILTER }}
          />
        </div>

        <DialogTitle className="text-xl leading-snug capitalize">
          {exercise.name}
        </DialogTitle>

        {exercise.instructions.length > 0 && (
          <ol className="allow-select list-decimal space-y-2.5 pl-5 text-base text-muted-foreground">
            {exercise.instructions.map((step, index) => (
              <li className="pl-1 leading-relaxed" key={index}>
                {step}
              </li>
            ))}
          </ol>
        )}

        <DialogFooter className="flex-row items-center">
          <button
            aria-label={
              isFavorite
                ? `Remove ${exercise.name} from favorites`
                : `Add ${exercise.name} to favorites`
            }
            aria-pressed={isFavorite}
            className="grid size-12 shrink-0 place-items-center rounded-2xl bg-secondary text-muted-foreground transition-transform duration-150 active:scale-90"
            onClick={() => toggleFavorite(exercise.id)}
            type="button"
          >
            <Heart
              className={cn(
                "size-5",
                isFavorite && "fill-primary text-primary"
              )}
            />
          </button>
          <Button
            className="h-12 flex-1 rounded-2xl text-base font-semibold"
            onClick={() => onAddToWorkout(exercise)}
          >
            <ListPlus data-icon="inline-start" />
            Add to workout
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
