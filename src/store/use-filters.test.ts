import { beforeEach, describe, expect, it } from "vitest"

import { useFilters } from "@/store/use-filters"

describe("filter store", () => {
  beforeEach(() => {
    localStorage.clear()
    useFilters.setState({ selectedMuscles: [], selectedEquipment: [] })
  })

  it("toggles and resets selections", () => {
    useFilters.getState().toggleMuscle("chest")
    useFilters.getState().toggleEquipment("barbell")
    expect(useFilters.getState().selectedMuscles).toEqual(["chest"])
    expect(useFilters.getState().selectedEquipment).toEqual(["barbell"])

    useFilters.getState().toggleMuscle("chest")
    expect(useFilters.getState().selectedMuscles).toEqual([])

    useFilters.getState().reset()
    expect(useFilters.getState().selectedEquipment).toEqual([])
  })

  it("persists selections to local storage", () => {
    useFilters.getState().toggleMuscle("biceps")
    useFilters.getState().toggleEquipment("dumbbell")

    const stored = JSON.parse(localStorage.getItem("gym-lib-filters") ?? "{}")
    expect(stored.state).toEqual({
      selectedMuscles: ["biceps"],
      selectedEquipment: ["dumbbell"],
    })
  })

  it("rehydrates stored selections", async () => {
    localStorage.setItem(
      "gym-lib-filters",
      JSON.stringify({
        state: {
          selectedMuscles: ["chest"],
          selectedEquipment: ["barbell"],
        },
        version: 0,
      })
    )

    await useFilters.persist.rehydrate()
    expect(useFilters.getState().selectedMuscles).toEqual(["chest"])
    expect(useFilters.getState().selectedEquipment).toEqual(["barbell"])
  })
})
