import { describe, expect, it } from "vitest"

import {
  EQUIPMENT_OPTIONS,
  EXERCISES,
  equipmentForMuscles,
  findExerciseAlternatives,
  filterExercises,
  supportingFromIndex,
} from "@/lib/exercises"
import type { ExerciseSummary, MuscleId } from "@/types"

const exercise = (
  id: string,
  name: string,
  equipment: string,
  involvement: Partial<Record<MuscleId, number>>
): ExerciseSummary => {
  const ranked = Object.entries(involvement) as [MuscleId, number][]
  return {
    id,
    name,
    equipment,
    primaryMuscle: ranked[0][0],
    muscles: ranked.map(([muscle]) => muscle),
    muscleWeights: ranked.map(([, weight]) => weight),
    instructions: [],
  }
}

const bench = exercise("bench", "Bench press", "barbell", {
  chest: 1,
  triceps: 0.62,
  deltoids: 0.42,
})
const fly = exercise("fly", "Cable fly", "cable", { chest: 1, deltoids: 0.62 })
const dip = exercise("dip", "Triceps dip", "body weight", {
  triceps: 1,
  chest: 0.62,
})
const stretch = exercise("stretch", "Chest stretch", "body weight", {
  chest: 1,
})
const row = exercise("row", "Barbell row", "barbell", {
  "upper-back": 1,
  biceps: 0.62,
})

const fixture = [bench, fly, dip, stretch, row]
const anyEquipment = ["barbell", "cable", "body weight"]

const ids = (exercises: ExerciseSummary[]) => exercises.map((match) => match.id)

describe("exercise data", () => {
  it("contains the complete compact dataset with unique IDs", () => {
    expect(EXERCISES).toHaveLength(1324)
    expect(new Set(EXERCISES.map((entry) => entry.id)).size).toBe(1324)
    expect(EXERCISES.every((entry) => entry.equipment.length > 0)).toBe(true)
  })

  it("carries one descending involvement weight per muscle", () => {
    EXERCISES.forEach((entry) => {
      expect(entry.muscleWeights).toHaveLength(entry.muscles.length)
      expect(entry.muscles.length).toBeGreaterThan(0)
      expect(entry.muscleWeights[0]).toBeLessThanOrEqual(1)
      expect([...entry.muscleWeights].sort((a, b) => b - a)).toEqual(
        entry.muscleWeights
      )
    })
  })

  it("orders equipment by editorial popularity", () => {
    expect(EQUIPMENT_OPTIONS.slice(0, 5)).toEqual([
      "body weight",
      "dumbbell",
      "barbell",
      "cable",
      "kettlebell",
    ])
    expect(new Set(EQUIPMENT_OPTIONS).size).toBe(EQUIPMENT_OPTIONS.length)
  })
})

describe("equipmentForMuscles", () => {
  it("returns all EQUIPMENT_OPTIONS when no muscles are passed", () => {
    expect(equipmentForMuscles([])).toEqual(EQUIPMENT_OPTIONS)
  })

  it("returns only equipment used for selected muscles", () => {
    const chestEquipment = equipmentForMuscles(["chest"])
    expect(chestEquipment).toContain("barbell")
    expect(chestEquipment).toContain("dumbbell")
    expect(chestEquipment).toContain("body weight")

    // Equipment with no chest exercises should NOT be present
    expect(chestEquipment).not.toContain("rope")
    expect(chestEquipment).not.toContain("hammer")
    expect(chestEquipment).not.toContain("sled machine")
    expect(chestEquipment).not.toContain("tire")
    expect(chestEquipment).not.toContain("elliptical machine")
  })

  it("returns union of equipment when multiple muscles are selected", () => {
    const tibialisEquipment = equipmentForMuscles(["tibialis"])
    expect(tibialisEquipment).toEqual(["smith machine"])

    const combinedEquipment = equipmentForMuscles(["tibialis", "trapezius"])
    expect(combinedEquipment).toContain("smith machine")
    expect(combinedEquipment).toContain("barbell")
    expect(combinedEquipment).toContain("cable")
  })

  it("preserves relative order from EQUIPMENT_OPTIONS", () => {
    const chestEquipment = equipmentForMuscles(["chest"])
    const expected = EQUIPMENT_OPTIONS.filter((item) =>
      chestEquipment.includes(item)
    )
    expect(chestEquipment).toEqual(expected)
  })

  it("filters accurately on custom fixtures", () => {
    expect(equipmentForMuscles(["biceps"], fixture)).toEqual(["barbell"])
    expect(equipmentForMuscles(["chest"], fixture)).toEqual([
      "body weight",
      "barbell",
      "cable",
    ])
  })
})

describe("filtering", () => {
  it("requires both filter groups", () => {
    expect(filterExercises(fixture, [], ["barbell"])).toEqual([])
    expect(filterExercises(fixture, ["chest"], [])).toEqual([])
  })

  it("uses OR within groups and AND between groups", () => {
    expect(
      ids(filterExercises(fixture, ["chest", "biceps"], anyEquipment)).sort()
    ).toEqual(["bench", "dip", "fly", "row", "stretch"])

    expect(
      ids(filterExercises(fixture, ["chest", "biceps"], ["barbell"]))
    ).toEqual(["bench", "row"])
  })

  it("matches secondary muscles", () => {
    expect(ids(filterExercises(fixture, ["biceps"], anyEquipment))).toEqual([
      "row",
    ])
  })
})

describe("exercise alternatives", () => {
  it("keeps the same muscles while changing equipment", () => {
    const source = EXERCISES.find((entry) => entry.id === "0001")!
    const alternatives = findExerciseAlternatives(source, ["0010"])

    expect(alternatives.length).toBeGreaterThan(0)
    expect(alternatives.some((entry) => entry.id === "0010")).toBe(false)
    alternatives.forEach((alternative) => {
      expect(alternative.equipment).not.toBe(source.equipment)
      expect(new Set(alternative.muscles)).toEqual(new Set(source.muscles))
    })
  })
})

describe("relevance ranking", () => {
  it("puts exercises built around the muscle above ones that assist it", () => {
    const ranked = ids(filterExercises(fixture, ["triceps"], anyEquipment))
    expect(ranked).toEqual(["dip", "bench"])

    expect(ids(filterExercises(fixture, ["chest"], anyEquipment))).toEqual([
      "fly",
      "stretch",
      "bench",
      "dip",
    ])
  })

  it("rewards covering more of a multi-muscle selection", () => {
    // The dip spends everything it has on the pair and the bench covers both,
    // so the two of them clear the exercises that only reach chest.
    expect(
      ids(filterExercises(fixture, ["chest", "triceps"], anyEquipment))
    ).toEqual(["dip", "bench", "fly", "stretch"])
  })

  it("demotes a stretch below movements that match as well", () => {
    const ranked = ids(filterExercises([fly, stretch], ["chest"], anyEquipment))
    expect(ranked).toEqual(["fly", "stretch"])
  })

  it("splits the list where exercises stop being about the selection", () => {
    const ranked = filterExercises(fixture, ["chest"], anyEquipment)
    // fly, stretch and bench are chest exercises; the dip only assists.
    expect(supportingFromIndex(ranked, ["chest"])).toBe(3)
    expect(ranked[3].id).toBe("dip")
  })

  it("keeps the whole list when nothing is built around the selection", () => {
    // No exercise in the library targets obliques, so a relative cut applies
    // instead of the absolute one.
    const ranked = filterExercises(EXERCISES, ["obliques"], EQUIPMENT_OPTIONS)
    expect(ranked.length).toBeGreaterThan(50)
    expect(supportingFromIndex(ranked, ["obliques"])).toBeGreaterThan(
      ranked.length / 2
    )
  })

  it("keeps grip-work noise out of the focused forearm results", () => {
    const ranked = filterExercises(EXERCISES, ["forearm"], EQUIPMENT_OPTIONS)
    const focused = ranked.slice(0, supportingFromIndex(ranked, ["forearm"]))

    expect(focused.length).toBeGreaterThan(20)
    expect(focused.every((entry) => entry.primaryMuscle === "forearm")).toBe(
      true
    )
  })
})
