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
import { useTrainingProfile } from "@/store/use-training-profile"
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

  it("carries the training profile and gym equipment out and back", () => {
    useTrainingProfile.getState().updateProfile({
      name: "Alex",
      age: 41,
      goal: "hypertrophy",
      preferredSessionDurationMinutes: 45,
    })
    useTrainingProfile.getState().toggleHealthLimitation("pregnancy")
    useTrainingProfile.getState().setMusclePriority("gluteal", "high")
    useTrainingProfile.getState().completeOnboarding("2026-09-01T12:00:00.000Z")
    useFilters.getState().setGymEquipment(["barbell", "cable"])

    const backup = createGymLibBackup()
    clearAllGymLibData()
    expect(useTrainingProfile.getState().profile.name).toBe("")
    importGymLibData(backup)

    expect(useTrainingProfile.getState().profile).toMatchObject({
      name: "Alex",
      age: 41,
      goal: "hypertrophy",
      preferredSessionDurationMinutes: 45,
      health: { status: "unsupported", reasons: ["pregnancy"] },
      priorityMuscles: [{ muscleId: "gluteal", level: "high" }],
    })
    expect(useTrainingProfile.getState().onboarding).toEqual({
      completed: true,
      completedAt: "2026-09-01T12:00:00.000Z",
    })
    expect(useFilters.getState().gymEquipment).toEqual(["barbell", "cable"])
  })

  it("rejects impossible profile values in an edited backup", () => {
    const backup = JSON.parse(createGymLibBackup())
    backup.data.trainingProfile.profile.age = 4
    backup.data.trainingProfile.profile.goal = "power"
    importGymLibData(JSON.stringify(backup))

    expect(useTrainingProfile.getState().profile).toMatchObject({
      age: 18,
      goal: "general_fitness",
    })
  })

  it("keeps profile and gym equipment a backup predates rather than wiping them", () => {
    const older = JSON.parse(createGymLibBackup())
    delete older.data.trainingProfile
    delete older.data.filters.gymEquipment
    older.data.favorites.favoriteIds = [EXERCISES[0].id]

    useTrainingProfile.getState().updateProfile({ name: "Alex", age: 41 })
    useFilters.getState().setGymEquipment(["kettlebell"])
    importGymLibData(JSON.stringify(older))

    expect(useFavorites.getState().favoriteIds).toEqual([EXERCISES[0].id])
    expect(useTrainingProfile.getState().profile).toMatchObject({
      name: "Alex",
      age: 41,
    })
    expect(useFilters.getState().gymEquipment).toEqual(["kettlebell"])
  })

  it("counts a configured profile as data worth keeping", () => {
    expect(hasMeaningfulGymLibData()).toBe(false)

    useTrainingProfile.getState().updateProfile({ age: 41 })
    expect(hasMeaningfulGymLibData()).toBe(true)

    clearAllGymLibData()
    expect(hasMeaningfulGymLibData()).toBe(false)

    useFilters.getState().setGymEquipment(["dumbbell"])
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
  useTrainingRecords.getState().addUnplannedSet({
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
