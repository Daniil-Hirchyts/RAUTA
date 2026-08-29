import type { ExerciseSummary } from "@/types"

export function equipmentImage(equipment: string) {
  return `/assets/equipment/${equipment.replaceAll(" ", "-")}.jpg`
}

export function exerciseGif(exercise: ExerciseSummary) {
  return `/assets/exercises/gifs/${exercise.id}.gif`
}

/**
 * Dark-theme treatment for the (white-background) exercise GIFs: a live
 * unsharp-mask sharpen (see SvgFilterDefs), then invert + hue-rotate so the
 * white background becomes black and the red muscle highlight stays red.
 * Pair with the `mix-blend-screen` class over a matching background color
 * so that black becomes exactly the surrounding surface color.
 */
export const EXERCISE_GIF_FILTER =
  "url(#exercise-gif-sharpen) invert(1) hue-rotate(180deg)"
