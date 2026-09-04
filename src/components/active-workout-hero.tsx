import { AppImage } from "@/components/app-image"
import { EXERCISE_ANIMATION_FILTER, exerciseAnimation } from "@/lib/visuals"
import type { ExerciseSummary } from "@/types"

/**
 * The exercise being performed right now: the demonstration and its name.
 * Decisions for advancing or completing the session live in the in-progress dock
 * and bottom commands, so this card stays a clean demonstration glance.
 */
export function ActiveWorkoutHero({
  exercise,
  onOpenExercise,
}: {
  exercise: ExerciseSummary
  onOpenExercise: (exercise: ExerciseSummary) => void
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
          className="h-full w-full object-contain"
          decoding="async"
          draggable={false}
          fetchPriority="high"
          loading="eager"
          src={exerciseAnimation(exercise)}
          style={{ filter: EXERCISE_ANIMATION_FILTER }}
        />
      </button>

      <div className="px-3 pt-2 pb-4">
        <h2 className="text-center text-2xl leading-snug font-extrabold capitalize">
          {exercise.name}
        </h2>
      </div>
    </section>
  )
}
