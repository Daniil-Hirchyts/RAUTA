import { beforeEach, describe, expect, it } from "vitest"

import { EXERCISES } from "@/lib/exercises"
import {
  clearAllGymLibData,
  createGymLibBackup,
  hasMeaningfulGymLibData,
  importGymLibData,
} from "@/lib/app-backup"
import { useFavorites } from "@/store/use-favorites"
import { useFilters } from "@/store/use-filters"
import { DEFAULT_SETTINGS, useSettings } from "@/store/use-settings"
import { useWorkouts } from "@/store/use-workouts"

describe("Gym Lib backup", () => {
  beforeEach(() => {
    localStorage.clear()
    clearAllGymLibData()
  })

  it("restores workouts, favorites, presets, and preferences", () => {
    const exerciseId = EXERCISES[0].id
    useFavorites.setState({ favoriteIds: [exerciseId] })
    useFilters.setState({
      equipmentPresets: [
        { id: "home", name: "Home", equipment: ["body weight"] },
      ],
      selectedEquipment: ["body weight"],
      selectedMuscles: ["abs"],
    })
    useSettings.setState({ ...DEFAULT_SETTINGS, soundChimesEnabled: true })
    useWorkouts.getState().createWorkout({
      date: "2026-08-31",
      exerciseIds: [exerciseId],
      name: "Core day",
    })

    const backup = createGymLibBackup()
    clearAllGymLibData()
    importGymLibData(backup)

    expect(useFavorites.getState().favoriteIds).toEqual([exerciseId])
    expect(useFilters.getState().equipmentPresets).toHaveLength(1)
    expect(useSettings.getState().soundChimesEnabled).toBe(true)
    expect(useWorkouts.getState().workouts[0]).toMatchObject({
      exerciseIds: [exerciseId],
      name: "Core day",
    })
  })

  it("rejects unrelated JSON", () => {
    expect(() => importGymLibData('{"version":99}')).toThrow(
      "not a supported Gym Lib backup"
    )
  })

  it("distinguishes a fresh install from data that should win a cloud conflict", () => {
    expect(hasMeaningfulGymLibData()).toBe(false)

    useSettings.setState({ ...DEFAULT_SETTINGS, keepAwake: true })
    expect(hasMeaningfulGymLibData()).toBe(true)

    clearAllGymLibData()
    useFavorites.setState({ favoriteIds: [EXERCISES[0].id] })
    expect(hasMeaningfulGymLibData()).toBe(true)
  })

  it("can stamp a cloud backup with the conflict-resolution timestamp", () => {
    const timestamp = "2026-09-01T09:30:00.000Z"
    const backup = JSON.parse(createGymLibBackup(timestamp))
    expect(backup.createdAt).toBe(timestamp)
  })
})
