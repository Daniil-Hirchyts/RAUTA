import type { ExerciseSummary } from "@/types"

import { isNative } from "@/lib/native"

export function equipmentImage(equipment: string) {
  return `/assets/equipment/${equipment.replaceAll(" ", "-")}.webp`
}

export function exerciseAnimation(exercise: ExerciseSummary) {
  return `/assets/exercises/webp/${exercise.id}.webp`
}

/** Ties an exercise's card thumbnail to its detail hero, so opening one
 *  moves the animation into place rather than redrawing it there. */
export function exerciseMorphId(exerciseId: string) {
  return `exercise-media:${exerciseId}`
}

/**
 * Dark-theme treatment for the white-background exercise animations. The
 * first filter turns the near-white canvas into transparency; the remaining
 * filters invert and recolor the figure. Unlike mix-blend-mode, this does not
 * depend on a backdrop layer and remains stable in WKWebView.
 *
 * The rotation lands the source red on the app's primary orange: measured
 * in WebKit the highlight averages ~1 degree off the brand hue, against 22
 * degrees for the original 180deg/3.25. Rotating below ~190deg swings the
 * hue back towards yellow rather than further into red, so this is about as
 * warm as the pair gets while staying on brand.
 *
 * Use this only where at most a handful of images render at once (the
 * workout list, and exercise detail page). `feConvolveMatrix` is a real per-pixel
 * convolution, not a compositor-accelerated effect — stamped on a results
 * grid that can hold hundreds of cards, it's expensive enough to crash
 * mobile Safari's renderer. `EXERCISE_ANIMATION_FILTER_LIGHT` below drops
 * just the sharpen for exactly that case.
 */
export const EXERCISE_ANIMATION_FILTER = isNative()
  ? "url(#exercise-background-key) invert(1) hue-rotate(188deg) saturate(2.2) contrast(1.05)"
  : "url(#exercise-background-key) url(#exercise-gif-sharpen) invert(1) hue-rotate(188deg) saturate(2.2) contrast(1.05)"

/** Same dark-theme treatment as {@link EXERCISE_ANIMATION_FILTER}, minus the
 *  SVG sharpen — for grids that can render many cards at once. */
export const EXERCISE_ANIMATION_FILTER_LIGHT =
  "url(#exercise-background-key) invert(1) hue-rotate(188deg) saturate(2.2) contrast(1.05)"
