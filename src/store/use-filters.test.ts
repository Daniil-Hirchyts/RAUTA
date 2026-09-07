import { beforeEach, describe, expect, it } from "vitest"

import { useFilters } from "@/store/use-filters"

describe("filter store", () => {
  beforeEach(() => {
    localStorage.clear()
    useFilters.setState({
      selectedMuscles: [],
      selectedEquipment: [],
      gymEquipment: [],
      equipmentPresets: [],
      equipmentLoadIncrements: {},
    })
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
      gymEquipment: [],
      equipmentPresets: [],
      equipmentLoadIncrements: {},
    })
  })

  it("persists and sanitizes equipment load increments", async () => {
    useFilters.getState().setEquipmentLoadIncrement("dumbbell", 2.5)
    expect(useFilters.getState().equipmentLoadIncrements).toEqual({
      dumbbell: 2.5,
    })

    useFilters.getState().clearEquipmentLoadIncrement("dumbbell")
    expect(useFilters.getState().equipmentLoadIncrements).toEqual({})

    localStorage.setItem(
      "gym-lib-filters",
      JSON.stringify({
        state: {
          selectedMuscles: [],
          selectedEquipment: [],
          gymEquipment: ["dumbbell"],
          equipmentPresets: [],
          equipmentLoadIncrements: {
            dumbbell: 1.25,
            barbell: 0,
            cable: 100,
            unknown: 5,
          },
        },
        version: 1,
      })
    )
    await useFilters.persist.rehydrate()
    expect(useFilters.getState().equipmentLoadIncrements).toEqual({
      dumbbell: 1.25,
    })
  })

  it("creates, applies, updates, and deletes equipment presets", () => {
    useFilters.getState().setEquipment(["dumbbell", "band"])
    useFilters.getState().saveEquipmentPreset("Home")

    const preset = useFilters.getState().equipmentPresets[0]
    expect(preset).toMatchObject({
      name: "Home",
      equipment: ["dumbbell", "band"],
    })

    useFilters.getState().setEquipment(["barbell"])
    useFilters.getState().applyEquipmentPreset(preset.id)
    expect(useFilters.getState().selectedEquipment).toEqual([
      "dumbbell",
      "band",
    ])

    useFilters.getState().setEquipment(["kettlebell"])
    useFilters.getState().saveEquipmentPreset("home")
    expect(useFilters.getState().equipmentPresets).toHaveLength(1)
    expect(useFilters.getState().equipmentPresets[0].equipment).toEqual([
      "kettlebell",
    ])

    useFilters.getState().deleteEquipmentPreset(preset.id)
    expect(useFilters.getState().equipmentPresets).toEqual([])
  })

  it("rehydrates stored selections", async () => {
    localStorage.setItem(
      "gym-lib-filters",
      JSON.stringify({
        state: {
          selectedMuscles: ["chest"],
          selectedEquipment: ["barbell"],
          equipmentPresets: [
            { id: "gym", name: "Gym", equipment: ["barbell"] },
          ],
          equipmentLoadIncrements: { barbell: 2.5 },
        },
        version: 0,
      })
    )

    await useFilters.persist.rehydrate()
    expect(useFilters.getState().selectedMuscles).toEqual(["chest"])
    expect(useFilters.getState().selectedEquipment).toEqual(["barbell"])
    expect(useFilters.getState().equipmentPresets).toEqual([
      { id: "gym", name: "Gym", equipment: ["barbell"] },
    ])
    expect(useFilters.getState().equipmentLoadIncrements).toEqual({
      barbell: 2.5,
    })
  })

  it("migrates and removes invalid persisted filter values", async () => {
    localStorage.setItem(
      "gym-lib-filters",
      JSON.stringify({
        state: {
          selectedMuscles: ["chest", "not-a-muscle", "chest"],
          selectedEquipment: ["barbell", "not-equipment", "barbell"],
          equipmentPresets: [
            {
              id: "valid",
              name: "  Garage  ",
              equipment: ["dumbbell", "not-equipment"],
            },
            { id: "invalid", name: "Empty", equipment: ["unknown"] },
          ],
          equipmentLoadIncrements: {
            dumbbell: 1.5,
            unknown: 5,
            cable: -1,
          },
        },
        version: 0,
      })
    )

    await useFilters.persist.rehydrate()

    expect(useFilters.persist.getOptions().version).toBe(1)
    expect(useFilters.getState().selectedMuscles).toEqual(["chest"])
    expect(useFilters.getState().selectedEquipment).toEqual(["barbell"])
    expect(useFilters.getState().equipmentPresets).toEqual([
      { id: "valid", name: "Garage", equipment: ["dumbbell"] },
    ])
    expect(useFilters.getState().equipmentLoadIncrements).toEqual({
      dumbbell: 1.5,
    })
  })
})
