import { formatKg } from "@/lib/resistance"
import type { ProgressionRecommendation } from "@/training"

/**
 * The engine's recommendation, in one line RAUTA can say.
 *
 * Every line below is a translation of a reason the engine actually returned —
 * `top_of_range`, `context_changed`, `no_history` — and nothing is added on
 * top. Where the engine is unsure it says so; where it has no evidence it says
 * that too, rather than dressing a default up as a decision. If a reason is
 * ever added to the engine and not here, the line is simply omitted: silence
 * is the only honest fallback.
 */
export type ProgressionNote = {
  /** The load to put on, when the engine could name one. */
  kg: number | null
  /** Whether that load is measured on one implement or on the pair. */
  basis: "total" | "per_implement" | null
  text: string
}

function delta(recommendation: ProgressionRecommendation, previousKg: number) {
  const { resistance } = recommendation
  if (!("kg" in resistance)) return null
  const difference = Math.abs(resistance.kg - previousKg)
  return difference > 0 ? `${formatKg(difference)} kg` : null
}

/**
 * @param previousKg The load the recommendation moved away from, when the
 * caller knows it. Only used to say how large the step is.
 */
export function progressionNote(
  recommendation: ProgressionRecommendation,
  previousKg?: number
): ProgressionNote | null {
  const { action, reasons, resistance, targetReps } = recommendation
  const reason = reasons[0]
  const kg = "kg" in resistance ? resistance.kg : null
  const basis = "basis" in resistance ? resistance.basis : null
  const step =
    previousKg !== undefined ? delta(recommendation, previousKg) : null
  const note = (text: string): ProgressionNote => ({ kg, basis, text })

  if (action === "increase_load")
    return note(
      reason === "coarse_load_grid"
        ? `Smallest step here is${step ? ` ${step}` : ""}. Take it.`
        : `You hit the top of the range last time.${step ? ` +${step}.` : ""}`
    )
  if (action === "decrease_load")
    return note(
      `Two sessions short of the range.${step ? ` −${step}.` : ""} Rebuild from here.`
    )
  if (action === "reduce_assistance")
    return note(
      `Top of the range last time.${step ? ` ${step} less assist.` : ""}`
    )
  if (action === "increase_assistance")
    return note(
      `Short of the range twice.${step ? ` ${step} more assist.` : ""}`
    )
  if (action === "increase_reps")
    return note(
      reason === "coarse_load_grid"
        ? `Next load up is a big jump. Add reps first — up to ${targetReps.max}.`
        : `Top of the range last time. Go for ${targetReps.max} reps.`
    )
  if (action === "coarse_grid_progression")
    return note(
      `This station jumps too far in one step. Hold the load and work to ${targetReps.max} reps.`
    )
  if (action === "hold") {
    if (reason === "incomplete_sets")
      return note("Last session came up short. Same load again.")
    if (reason === "missing_effort")
      return note("No RIR logged last time, so nothing to progress from.")
    if (reason === "increment_too_large")
      return note("A step down here is too big. Hold this load.")
    if (reason === "grid_unavailable")
      return note("I do not know this station's steps yet. Hold this load.")
    if (reason === "within_range")
      return note("Keep this load until you reach the top of the range.")
    return null
  }
  if (action === "calibrate") {
    if (reason === "context_changed")
      return note("Different station today — recalibrating.")
    if (reason === "stale_history")
      return note("It has been a while. Find the load again, easy first set.")
    if (reason === "grid_unavailable")
      return note("Set this station's load step and I can progress it.")
    if (reason === "no_history")
      return note("Not enough logged sets yet. Find a working load.")
    return null
  }
  return null
}
