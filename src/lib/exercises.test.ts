import { describe, expect, it } from "vitest"

import { EXERCISES, filterExercises } from "@/lib/exercises"
import type { ExerciseSummary } from "@/types"

const fixture: ExerciseSummary[] = [
  {
    id: "1",
    name: "Alpha press",
    equipment: "barbell",
    primaryMuscle: "chest",
    muscles: ["chest", "triceps"],
    instructions: [],
  },
  {
    id: "2",
    name: "Beta curl",
    equipment: "dumbbell",
    primaryMuscle: "biceps",
    muscles: ["biceps", "forearm"],
    instructions: [],
  },
  {
    id: "3",
    name: "Gamma press",
    equipment: "dumbbell",
    primaryMuscle: "chest",
    muscles: ["chest", "triceps"],
    instructions: [],
  },
]

describe("exercise data", () => {
  it("contains the complete compact dataset with unique IDs", () => {
    expect(EXERCISES).toHaveLength(1324)
    expect(new Set(EXERCISES.map((exercise) => exercise.id)).size).toBe(1324)
    expect(EXERCISES.every((exercise) => exercise.equipment.length > 0)).toBe(
      true
    )
  })

  it("is stably sorted by name then ID", () => {
    const sorted = [...EXERCISES].sort(
      (left, right) =>
        left.name.localeCompare(right.name) || left.id.localeCompare(right.id)
    )
    expect(EXERCISES).toEqual(sorted)
  })
})

describe("filtering", () => {
  it("requires both filter groups", () => {
    expect(filterExercises(fixture, [], ["barbell"])).toEqual([])
    expect(filterExercises(fixture, ["chest"], [])).toEqual([])
  })

  it("uses OR within groups and AND between groups", () => {
    expect(
      filterExercises(
        fixture,
        ["chest", "biceps"],
        ["barbell", "dumbbell"]
      ).map((exercise) => exercise.id)
    ).toEqual(["1", "2", "3"])

    expect(
      filterExercises(fixture, ["chest", "biceps"], ["barbell"]).map(
        (exercise) => exercise.id
      )
    ).toEqual(["1"])
  })

  it("matches secondary muscles", () => {
    expect(
      filterExercises(fixture, ["triceps"], ["barbell"]).map(
        (exercise) => exercise.id
      )
    ).toEqual(["1"])
  })
})
