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

  it("ranks assisting muscles by how far down the source lists them", () => {
    expect(
      normalizeExerciseMuscles({
        target: "pectorals",
        muscleGroup: "chest",
        secondaryMuscles: ["shoulders", "triceps", "chest"],
      })
    ).toEqual({
      primaryMuscle: "chest",
      muscles: ["chest", "deltoids", "triceps"],
      muscleWeights: [1, 0.62, 0.42],
    })
  })

  it("drops stabilisers and muscles the source lists as an afterthought", () => {
    expect(
      normalizeExerciseMuscles({
        target: "hamstrings",
        muscleGroup: "glutes",
        // "core" is third but only stabilises, and forearms are fifth: both
        // fall under the involvement floor and leave the record entirely.
        secondaryMuscles: ["lower back", "core", "calves", "forearms"],
      })
    ).toEqual({
      primaryMuscle: "hamstring",
      muscles: ["hamstring", "gluteal", "lower-back", "calves"],
      muscleWeights: [1, 0.62, 0.42, 0.19],
    })
  })

  it("promotes the muscle group when the target is undrawable", () => {
    expect(
      normalizeExerciseMuscles({
        target: "cardiovascular system",
        muscleGroup: "quadriceps",
        secondaryMuscles: ["glutes"],
      })
    ).toEqual({
      primaryMuscle: "quadriceps",
      muscles: ["quadriceps", "gluteal"],
      muscleWeights: [1, 0.62],
    })
  })
})
