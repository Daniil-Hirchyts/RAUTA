import { EXERCISES_BY_ID } from "@/lib/exercises"
import type { AppPage } from "@/store/app-navigation"
import { isRecord, validString, validUniqueStrings } from "@/store/persistence"

export type AppSession = {
  detailExerciseId: string | null
  favoritesOnly: boolean
  pages: AppPage[]
  selectedIds: string[]
  selectMode: boolean
}

const APP_SESSION_KEY = "gym-lib-app-session"
const APP_SESSION_VERSION = 3

export const DEFAULT_APP_SESSION: AppSession = {
  detailExerciseId: null,
  favoritesOnly: false,
  pages: [{ type: "workouts" }],
  selectedIds: [],
  selectMode: false,
}

function isExerciseId(id: string) {
  return EXERCISES_BY_ID.has(id)
}

function optionalString(value: unknown) {
  return validString(value) || null
}

function parsePage(value: unknown): AppPage | null {
  if (!isRecord(value) || typeof value.type !== "string") return null

  switch (value.type) {
    case "workouts":
    case "settings":
    case "equipment-preset":
      return { type: value.type }
    case "workout-detail": {
      const workoutId = validString(value.workoutId)
      return workoutId ? { type: value.type, workoutId } : null
    }
    case "muscles":
    case "equipment":
    case "exercises":
    case "workout-destination":
      return {
        type: value.type,
        preferredWorkoutId: optionalString(value.preferredWorkoutId),
      }
    case "exercise-detail": {
      const exerciseId = validString(value.exerciseId)
      if (!exerciseId || !isExerciseId(exerciseId)) return null
      return {
        type: "exercise-detail",
        exerciseId,
        selectable: value.selectable === true,
      }
    }
    case "workout-form":
      return {
        type: "workout-form",
        exerciseIds: validUniqueStrings(value.exerciseIds, isExerciseId),
        workoutId: optionalString(value.workoutId),
      }
    case "exercise-alternatives": {
      const exerciseId = validString(value.exerciseId)
      const workoutId = validString(value.workoutId)
      if (!exerciseId || !isExerciseId(exerciseId) || !workoutId) return null
      return { type: "exercise-alternatives", exerciseId, workoutId }
    }
    default:
      return null
  }
}

function sanitizePages(value: unknown): AppPage[] {
  const parsed = Array.isArray(value)
    ? value
        .slice(0, 12)
        .map(parsePage)
        .filter((page): page is AppPage => Boolean(page))
    : []

  if (parsed.length === 0) return [...DEFAULT_APP_SESSION.pages]
  if (parsed[0].type !== "workouts") parsed.unshift({ type: "workouts" })
  return parsed
}

function sanitizeSession(value: unknown): AppSession {
  const state = isRecord(value) ? value : {}
  const detailExerciseId = validString(state.detailExerciseId) || null
  const validDetailExerciseId =
    detailExerciseId && isExerciseId(detailExerciseId) ? detailExerciseId : null

  return {
    detailExerciseId: validDetailExerciseId,
    favoritesOnly: state.favoritesOnly === true,
    pages: sanitizePages(state.pages),
    selectedIds: validUniqueStrings(state.selectedIds, isExerciseId),
    selectMode: state.selectMode === true,
  }
}

function migrateVersion2(value: unknown): AppSession {
  const state = isRecord(value) ? value : {}
  const view = isRecord(state.view) ? state.view : {}
  const pages: AppPage[] = [{ type: "workouts" }]

  if (view.type === "settings") {
    pages.push({ type: "settings" })
  } else if (view.type === "workout-detail") {
    const workoutId = validString(view.workoutId)
    if (workoutId) pages.push({ type: "workout-detail", workoutId })
  } else if (view.type === "flow") {
    pages.push({ type: "muscles" })
    if (state.stage === 2 || state.stage === 3)
      pages.push({ type: "equipment" })
    if (state.stage === 3) pages.push({ type: "exercises" })
  }

  if (state.workoutFormOpen === true) {
    pages.push({
      type: "workout-form",
      exerciseIds: validUniqueStrings(
        state.workoutFormExerciseIds,
        isExerciseId
      ),
      workoutId: optionalString(state.workoutFormWorkoutId),
    })
  }

  const detailExerciseId = validString(state.detailExerciseId)
  if (
    state.detailOpen === true &&
    detailExerciseId &&
    isExerciseId(detailExerciseId)
  ) {
    pages.push({
      type: "exercise-detail",
      exerciseId: detailExerciseId,
      selectable: view.type === "flow",
    })
  }

  return sanitizeSession({ ...state, pages })
}

export function readAppSession(): AppSession {
  if (typeof localStorage === "undefined") return DEFAULT_APP_SESSION

  try {
    const stored = JSON.parse(localStorage.getItem(APP_SESSION_KEY) ?? "null")
    if (!isRecord(stored)) {
      return DEFAULT_APP_SESSION
    }
    if (stored.version === 2) return migrateVersion2(stored.state)
    if (stored.version !== APP_SESSION_VERSION) return DEFAULT_APP_SESSION
    return sanitizeSession(stored.state)
  } catch {
    return DEFAULT_APP_SESSION
  }
}

export function writeAppSession(session: AppSession) {
  if (typeof localStorage === "undefined") return
  try {
    localStorage.setItem(
      APP_SESSION_KEY,
      JSON.stringify({
        state: sanitizeSession(session),
        version: APP_SESSION_VERSION,
      })
    )
  } catch {
    // Storage can be unavailable in restricted/private Safari contexts.
    // Keeping the in-memory session working is preferable to crashing.
  }
}
