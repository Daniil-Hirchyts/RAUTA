import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export type NumericRange = { min: number; max: number; step: number }

/**
 * The nearest value a stepped control can actually hold. Shared by the rotary
 * knob and by the stores that persist what it produced, so a restored value
 * always lands on the same notch a finger could have reached.
 */
export function snapToRange(value: unknown, { max, min, step }: NumericRange) {
  const numeric =
    typeof value === "number" && Number.isFinite(value) ? value : min
  const stepped = min + Math.round((numeric - min) / step) * step
  // Binary floating point turns 20 + 13 * 2.5 into 52.500000000000004; the
  // control only ever offers values a person could read off it.
  const rounded = Number(stepped.toFixed(6))
  return Math.min(max, Math.max(min, rounded))
}
