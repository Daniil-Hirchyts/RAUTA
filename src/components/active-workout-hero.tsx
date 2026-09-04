import { SkipForward } from "lucide-react"

import { AppImage } from "@/components/app-image"
import { Button } from "@/components/ui/button"
import { triggerHaptic } from "@/lib/haptics"
import { EXERCISE_ANIMATION_FILTER, exerciseAnimation } from "@/lib/visuals"
import type { ExerciseSummary } from "@/types"

/**
 * The exercise being performed right now: the demonstration, its name, and the
 * two decisions available from here. Everything else about the session — where
 * it is up to, what comes next — is on the list below and in the progress bar,
 * so this card stays a single glance.
 */
export function ActiveWorkoutHero({
  exercise,
  onComplete,
  onOpenExercise,
  onSkip,
}: {
  exercise: ExerciseSummary
  onComplete: () => void
  onOpenExercise: (exercise: ExerciseSummary) => void
  /** Omitted when this is the last exercise left to do. */
  onSkip?: () => void
}) {
  return (
    <section
      aria-label="Current exercise"
      className="mx-(--app-content-inset) overflow-hidden rounded-3xl border border-primary/30 bg-card shadow-lg shadow-black/20"
    >
      <button
        aria-label={`Open ${exercise.name} demonstration`}
        className="isolate block aspect-[5/4] w-full bg-card"
        onClick={() => onOpenExercise(exercise)}
        type="button"
      >
        <AppImage
          alt={`${exercise.name} demonstration`}
          className="h-full w-full object-contain mix-blend-screen"
          decoding="async"
          draggable={false}
          fetchPriority="high"
          loading="eager"
          src={exerciseAnimation(exercise)}
          style={{ filter: EXERCISE_ANIMATION_FILTER }}
        />
      </button>

      <div className="px-3 pt-1 pb-3">
        <h2 className="text-center text-xl leading-snug font-bold capitalize">
          {exercise.name}
        </h2>

        <div className="mt-3.5 flex items-center gap-2.5">
          <Button
            className="h-12 flex-1 rounded-2xl text-base font-semibold"
            onClick={() => {
              triggerHaptic("success")
              onComplete()
            }}
          >
            Mark done
          </Button>
          <Button
            aria-label={`Skip ${exercise.name}`}
            className="size-12 rounded-2xl"
            disabled={!onSkip}
            onClick={() => {
              triggerHaptic("light")
              onSkip?.()
            }}
            size="icon"
            variant="secondary"
          >
            <SkipForward className="size-5" />
          </Button>
        </div>
      </div>
    </section>
  )
}
