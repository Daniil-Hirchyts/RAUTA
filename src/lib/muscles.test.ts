import { describe, expect, it } from "vitest"

import {
  MUSCLE_ALIASES,
  normalizeExerciseMuscles,
  normalizeMuscle,
} from "@/lib/muscles"

describe("muscle normalization", () => {
  it.each(Object.entries(MUSCLE_ALIASES))(
    "normalizes %s",
    (alias, expected) => {
      expect(normalizeMuscle(alias)).toBe(expected)
      expect(normalizeMuscle(`  ${alias.toUpperCase()}  `)).toBe(expected)
    }
  )

  it("drops unknown and undrawable muscle names", () => {
    expect(normalizeMuscle("unknown muscle")).toBeNull()
    expect(normalizeMuscle(undefined)).toBeNull()
  })

  it("orders and deduplicates a record's muscles", () => {
    expect(
      normalizeExerciseMuscles({
        target: "pectorals",
        muscleGroup: "chest",
        secondaryMuscles: ["shoulders", "triceps", "chest"],
      })
    ).toEqual({
      primaryMuscle: "chest",
      muscles: ["chest", "deltoids", "triceps"],
    })
  })
})
