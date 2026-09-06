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
import { useTrainingRecords } from "@/store/use-training-records"
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
      name: "Core day",
      date: "2026-08-31",
      exerciseIds: [exerciseId],
    })

    const backup = createGymLibBackup()
    clearAllGymLibData()
    importGymLibData(backup)

    expect(useFavorites.getState().favoriteIds).toEqual([exerciseId])
    expect(useFilters.getState().equipmentPresets).toHaveLength(1)
    expect(useSettings.getState().soundChimesEnabled).toBe(true)
    expect(useWorkouts.getState().workouts[0]).toMatchObject({
      name: "Core day",
      exerciseIds: [exerciseId],
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

it("manual backups include local training while cloud snapshots leave it local", () => {
  clearAllGymLibData()
  useTrainingRecords.getState().startFreeWorkout(["0025"])
  const draft = useTrainingRecords.getState().data.activeWorkout!
  useTrainingRecords
    .getState()
    .addUnplannedSet({
      exerciseEntryId: draft.exercises[0].id,
      setType: "working",
      side: "both",
      observation: {
        reps: 9,
        resistance: { type: "bodyweight" },
        completed: false,
      },
    })
  const expected = JSON.parse(
    JSON.stringify(useTrainingRecords.getState().data)
  )
  const manual = createGymLibBackup(undefined, true, true)
  const cloud = createGymLibBackup()
  expect(JSON.parse(cloud).data.training).toBeUndefined()
  clearAllGymLibData()
  expect(useTrainingRecords.getState().data.activeWorkout).toBeNull()
  importGymLibData(manual)
  expect(useTrainingRecords.getState().data).toEqual(expected)
  importGymLibData(cloud)
  expect(useTrainingRecords.getState().data).toEqual(expected)
})

it("rejects invalid training in a manual backup before replacing current data", () => {
  clearAllGymLibData()
  useTrainingRecords.getState().startFreeWorkout(["0025"])
  const before = useTrainingRecords.getState().data
  const backup = JSON.parse(createGymLibBackup(undefined, true, true))
  backup.data.training.schemaVersion = 999
  expect(() => importGymLibData(JSON.stringify(backup))).toThrow(
    /invalid training/
  )
  expect(useTrainingRecords.getState().data).toEqual(before)
})
