import type { ExerciseSummary } from "@/types"

export function equipmentImage(equipment: string) {
  const revision =
    equipment === "assisted" || equipment === "rope" ? "?v=2" : ""
  return `/assets/equipment/${equipment.replaceAll(" ", "-")}.jpg${revision}`
}

export function exerciseAnimation(exercise: ExerciseSummary) {
  return `/assets/exercises/webp/${exercise.id}.webp`
}

/**
 * Dark-theme treatment for the white-background exercise animations: a live
 * unsharp-mask sharpen (see SvgFilterDefs), then invert + hue-rotate so the
 * white background becomes black and the red muscle highlight stays red.
 * Pair with the `mix-blend-screen` class over a matching background color
 * so that black becomes exactly the surrounding surface color.
 *
 * Use this only where at most a handful of images render at once (the
 * workout list, the detail drawer). `feConvolveMatrix` is a real per-pixel
 * convolution, not a compositor-accelerated effect — stamped on a results
 * grid that can hold hundreds of cards, it's expensive enough to crash
 * mobile Safari's renderer. `EXERCISE_ANIMATION_FILTER_LIGHT` below drops
 * just the sharpen for exactly that case.
 */
export const EXERCISE_ANIMATION_FILTER =
  "url(#exercise-gif-sharpen) invert(1) hue-rotate(180deg) saturate(3.25) contrast(1.06)"

/** Same dark-theme treatment as {@link EXERCISE_ANIMATION_FILTER}, minus the
 *  SVG sharpen — for grids that can render many cards at once. */
export const EXERCISE_ANIMATION_FILTER_LIGHT =
  "invert(1) hue-rotate(180deg) saturate(3.25) contrast(1.06)"
