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
 * so that black becomes exactly the surrounding surface color — use the
 * surface token itself (bg-card, bg-popover), never a hardcoded hex, or the
 * animation sits in a visibly darker box.
 *
 * The rotation lands the source red on the app's primary orange: measured
 * in WebKit the highlight averages ~1 degree off the brand hue, against 22
 * degrees for the original 180deg/3.25. Rotating below ~190deg swings the
 * hue back towards yellow rather than further into red, so this is about as
 * warm as the pair gets while staying on brand.
 *
 * Use this only where at most a handful of images render at once (the
 * workout list, the detail drawer). `feConvolveMatrix` is a real per-pixel
 * convolution, not a compositor-accelerated effect — stamped on a results
 * grid that can hold hundreds of cards, it's expensive enough to crash
 * mobile Safari's renderer. `EXERCISE_ANIMATION_FILTER_LIGHT` below drops
 * just the sharpen for exactly that case.
 */
export const EXERCISE_ANIMATION_FILTER =
  "url(#exercise-gif-sharpen) invert(1) hue-rotate(188deg) saturate(2.2) contrast(1.05)"

/** Same dark-theme treatment as {@link EXERCISE_ANIMATION_FILTER}, minus the
 *  SVG sharpen — for grids that can render many cards at once. */
export const EXERCISE_ANIMATION_FILTER_LIGHT =
  "invert(1) hue-rotate(188deg) saturate(2.2) contrast(1.05)"
