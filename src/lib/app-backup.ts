import { Directory, Encoding, Filesystem } from "@capacitor/filesystem"
import { Share } from "@capacitor/share"

import { isNative } from "@/lib/native"
import { isRecord } from "@/store/persistence"
import { useActiveWorkout } from "@/store/use-active-workout"
import { sanitizeFavoritesState, useFavorites } from "@/store/use-favorites"
import { sanitizeFilterState, useFilters } from "@/store/use-filters"
import { sanitizeSettings, useSettings } from "@/store/use-settings"
import { sanitizeWorkoutsState, useWorkouts } from "@/store/use-workouts"

const BACKUP_VERSION = 1

export function createGymLibBackup() {
  const favorites = useFavorites.getState()
  const filters = useFilters.getState()
  const settings = useSettings.getState()
  const workouts = useWorkouts.getState()

  return JSON.stringify(
    {
      app: "Gym Lib",
      createdAt: new Date().toISOString(),
      version: BACKUP_VERSION,
      data: {
        favorites: { favoriteIds: favorites.favoriteIds },
        filters: {
          selectedMuscles: filters.selectedMuscles,
          selectedEquipment: filters.selectedEquipment,
          equipmentPresets: filters.equipmentPresets,
        },
        settings: sanitizeSettings(settings),
        workouts: { workouts: workouts.workouts },
      },
    },
    null,
    2
  )
}

export async function exportGymLibData() {
  const data = createGymLibBackup()
  const date = new Date().toISOString().slice(0, 10)
  const filename = `gym-lib-backup-${date}.json`

  if (isNative()) {
    const file = await Filesystem.writeFile({
      data,
      directory: Directory.Cache,
      encoding: Encoding.UTF8,
      path: filename,
    })
    await Share.share({
      dialogTitle: "Export Gym Lib data",
      files: [file.uri],
      title: "Gym Lib backup",
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
    backup.app !== "Gym Lib" ||
    backup.version !== BACKUP_VERSION
  ) {
    throw new Error("This is not a supported Gym Lib backup.")
  }
  if (!isRecord(backup.data)) {
    throw new Error("The backup does not contain app data.")
  }

  const data = backup.data
  const favorites = sanitizeFavoritesState(data.favorites)
  const filters = sanitizeFilterState(data.filters)
  const settings = sanitizeSettings(data.settings)
  const workouts = sanitizeWorkoutsState(data.workouts)

  useActiveWorkout.setState({ lastOutcome: "cancelled", session: null })
  useFavorites.setState(favorites)
  useFilters.setState(filters)
  useSettings.setState(settings)
  useWorkouts.setState(workouts)
}

export function clearAllGymLibData() {
  useActiveWorkout.setState({ lastOutcome: "cancelled", session: null })
  useFavorites.setState({ favoriteIds: [] })
  useFilters.setState({
    equipmentPresets: [],
    selectedEquipment: [],
    selectedMuscles: [],
  })
  useWorkouts.setState({ workouts: [] })
  useSettings.getState().resetSettings()
  localStorage.removeItem("gym-lib-app-session")
}
