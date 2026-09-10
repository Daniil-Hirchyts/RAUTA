import { AppImage } from "@/components/app-image"
import { EXERCISE_ANIMATION_FILTER, exerciseAnimation } from "@/lib/visuals"
import type { ExerciseSummary } from "@/types"

/**
 * The exercise being performed right now: the demonstration and its name.
 *
 * The full width of the column, and about a third of the screen tall: the
 * sets being logged are what the tab is for, and a demonstration any deeper
 * would push them past the fold. The artwork sits in the middle of that band
 * at its own size. Tapping it opens the exercise in full; advancing and
 * finishing live in the panel at the foot of the screen and in the command
 * band.
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
      className="content-glow relative mx-(--app-content-inset) h-[34vh] max-h-[22rem] min-h-[12rem] overflow-hidden rounded-3xl border border-primary/30 bg-card shadow-lg shadow-black/20"
    >
      <button
        aria-label={`Open ${exercise.name} demonstration`}
        className="absolute inset-0 isolate block bg-card"
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

      {/* The name belongs to the picture, so it sits on it rather than under
          it — which is what keeps the card square. Its own scrim carries it
          over the artwork, and it is painted above the card's glow, which was
          otherwise washing it out. */}
      <h2 className="pointer-events-none absolute inset-x-0 bottom-0 z-2 bg-gradient-to-t from-black/80 via-black/45 to-transparent px-4 pt-10 pb-3.5 text-center text-lg leading-snug font-extrabold capitalize drop-shadow-[0_1px_6px_rgba(0,0,0,0.65)]">
        {exercise.name}
      </h2>
    </section>
  )
}
