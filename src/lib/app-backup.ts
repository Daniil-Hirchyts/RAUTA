import { Directory, Encoding, Filesystem } from "@capacitor/filesystem"
import { Share } from "@capacitor/share"

import { isNative } from "@/lib/native"
import { isRecord } from "@/store/persistence"
import { useActiveWorkout } from "@/store/use-active-workout"
import { sanitizeFavoritesState, useFavorites } from "@/store/use-favorites"
import { sanitizeFilterState, useFilters } from "@/store/use-filters"
import {
  DEFAULT_SETTINGS,
  sanitizeSettings,
  useSettings,
} from "@/store/use-settings"
import { sanitizeWorkoutsState, useWorkouts } from "@/store/use-workouts"
import { useTrainingRecords } from "@/store/use-training-records"
import {
  isTrainingProfileConfigured,
  sanitizeTrainingProfileState,
  useTrainingProfile,
} from "@/store/use-training-profile"
import {
  createEmptyPersistedTrainingState,
  type PersistedTrainingStateLatest,
} from "@/training-persistence/schema"
import { validatePersistedTrainingState } from "@/training-persistence/validation"

const BACKUP_VERSION = 1

function hasKey(value: unknown, key: string) {
  return isRecord(value) && value[key] !== undefined
}

export function createGymLibBackup(
  createdAt = new Date().toISOString(),
  pretty = true,
  includeLocalTraining = false
) {
  const favorites = useFavorites.getState()
  const filters = useFilters.getState()
  const settings = useSettings.getState()
  const workouts = useWorkouts.getState()
  const trainingProfile = useTrainingProfile.getState()

  return JSON.stringify(
    {
      app: "RAUTA",
      createdAt,
      version: BACKUP_VERSION,
      data: {
        favorites: { favoriteIds: favorites.favoriteIds },
        filters: {
          selectedMuscles: filters.selectedMuscles,
          selectedEquipment: filters.selectedEquipment,
          gymEquipment: filters.gymEquipment,
          equipmentPresets: filters.equipmentPresets,
        },
        trainingProfile: {
          profile: trainingProfile.profile,
          onboarding: trainingProfile.onboarding,
        },
        settings: sanitizeSettings(settings),
        workouts: { workouts: workouts.workouts },
        ...(includeLocalTraining
          ? { training: useTrainingRecords.getState().data }
          : {}),
      },
    },
    null,
    pretty ? 2 : undefined
  )
}

/** Defaults do not need to win a first-run conflict over an existing cloud copy. */
export function hasMeaningfulGymLibData() {
  const favorites = useFavorites.getState()
  const filters = useFilters.getState()
  const settings = sanitizeSettings(useSettings.getState())
  const workouts = useWorkouts.getState()

  return (
    favorites.favoriteIds.length > 0 ||
    filters.selectedMuscles.length > 0 ||
    filters.selectedEquipment.length > 0 ||
    filters.gymEquipment.length > 0 ||
    filters.equipmentPresets.length > 0 ||
    workouts.workouts.length > 0 ||
    isTrainingProfileConfigured(useTrainingProfile.getState()) ||
    JSON.stringify(settings) !== JSON.stringify(DEFAULT_SETTINGS)
  )
}

export async function exportGymLibData() {
  // Manual exports include local training; the existing iCloud snapshot stays unchanged.
  const data = createGymLibBackup(new Date().toISOString(), true, true)
  const date = new Date().toISOString().slice(0, 10)
  const filename = `rauta-backup-${date}.json`

  if (isNative()) {
    const file = await Filesystem.writeFile({
      data,
      directory: Directory.Cache,
      encoding: Encoding.UTF8,
      path: filename,
    })
    await Share.share({
      dialogTitle: "Export RAUTA data",
      files: [file.uri],
      title: "RAUTA backup",
    })
    return
  }

  const url = URL.createObjectURL(
    new Blob([data], { type: "application/json" })
  )
  const link = document.createElement("a")
  link.download = filename
  link.href = url
  link.click()
  URL.revokeObjectURL(url)
}

export function importGymLibData(json: string) {
  const backup: unknown = JSON.parse(json)
  if (
    !isRecord(backup) ||
    (backup.app !== "RAUTA" && backup.app !== "Gym Lib") ||
    backup.version !== BACKUP_VERSION
  ) {
    throw new Error("This is not a supported RAUTA backup.")
  }
  if (!isRecord(backup.data)) {
    throw new Error("The backup does not contain app data.")
  }

  const data = backup.data
  if (
    data.training !== undefined &&
    validatePersistedTrainingState(data.training).length
  )
    throw new Error("The backup contains invalid training records.")
  const favorites = sanitizeFavoritesState(data.favorites)
  const filters = sanitizeFilterState(data.filters)
  const settings = sanitizeSettings(data.settings)
  const workouts = sanitizeWorkoutsState(data.workouts)

  useActiveWorkout.setState({ lastOutcome: "cancelled", session: null })
  useFavorites.setState(favorites)
  // A backup written before a field existed says nothing about it, which is
  // not the same as saying it is empty. Anything the file does not carry is
  // left exactly as this device already has it.
  useFilters.setState({
    ...filters,
    gymEquipment: hasKey(data.filters, "gymEquipment")
      ? filters.gymEquipment
      : useFilters.getState().gymEquipment,
  })
  useSettings.setState(settings)
  useWorkouts.setState(workouts)
  if (data.trainingProfile !== undefined)
    useTrainingProfile.setState(
      sanitizeTrainingProfileState(data.trainingProfile)
    )
  if (data.training !== undefined)
    useTrainingRecords.setState({
      data: structuredClone(data.training) as PersistedTrainingStateLatest,
    })
}

export function clearAllGymLibData() {
  useActiveWorkout.setState({ lastOutcome: "cancelled", session: null })
  useFavorites.setState({ favoriteIds: [] })
  useFilters.setState({
    equipmentPresets: [],
    gymEquipment: [],
    selectedEquipment: [],
    selectedMuscles: [],
  })
  useWorkouts.setState({ workouts: [] })
  useTrainingRecords.setState({
    data: createEmptyPersistedTrainingState(),
    persistenceIssues: [],
  })
  useSettings.getState().resetSettings()
  useTrainingProfile.getState().resetTrainingProfile()
  localStorage.removeItem("gym-lib-app-session")
}
