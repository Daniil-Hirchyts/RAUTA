import { EXERCISES_BY_ID } from "@/lib/exercises"
import { isRecord, validString, validUniqueStrings } from "@/store/persistence"

export type AppStage = 1 | 2 | 3

export type AppView =
  | { type: "flow" }
  | { type: "workouts" }
  | { type: "workout-detail"; workoutId: string }

export type AppSession = {
  detailExerciseId: string | null
  detailOpen: boolean
  favoritesOnly: boolean
  selectedIds: string[]
  selectMode: boolean
  stage: AppStage
  view: AppView
  workoutFormExerciseIds: string[]
  workoutFormOpen: boolean
  workoutFormWorkoutId: string | null
}

const APP_SESSION_KEY = "gym-lib-app-session"
const APP_SESSION_VERSION = 2

export const DEFAULT_APP_SESSION: AppSession = {
  detailExerciseId: null,
  detailOpen: false,
  favoritesOnly: false,
  selectedIds: [],
  selectMode: false,
  stage: 1,
  view: { type: "workouts" },
  workoutFormExerciseIds: [],
  workoutFormOpen: false,
  workoutFormWorkoutId: null,
}

function isExerciseId(id: string) {
  return EXERCISES_BY_ID.has(id)
}

function parseView(value: unknown): AppView {
  if (!isRecord(value)) return DEFAULT_APP_SESSION.view
  if (value.type === "workouts") return { type: "workouts" }
  if (value.type === "workout-detail") {
    const workoutId = validString(value.workoutId)
    if (workoutId) return { type: "workout-detail", workoutId }
  }
  return { type: "flow" }
}

function sanitizeSession(value: unknown): AppSession {
  const state = isRecord(value) ? value : {}
  const stage = state.stage === 2 || state.stage === 3 ? state.stage : 1
  const detailExerciseId = validString(state.detailExerciseId) || null
  const validDetailExerciseId =
    detailExerciseId && isExerciseId(detailExerciseId) ? detailExerciseId : null
  const workoutFormWorkoutId = validString(state.workoutFormWorkoutId) || null

  return {
    detailExerciseId: validDetailExerciseId,
    detailOpen: state.detailOpen === true && Boolean(validDetailExerciseId),
    favoritesOnly: state.favoritesOnly === true,
    selectedIds: validUniqueStrings(state.selectedIds, isExerciseId),
    selectMode: state.selectMode === true,
    stage,
    view: parseView(state.view),
    workoutFormExerciseIds: validUniqueStrings(
      state.workoutFormExerciseIds,
      isExerciseId
    ),
    workoutFormOpen: state.workoutFormOpen === true,
    workoutFormWorkoutId,
  }
}

export function readAppSession(): AppSession {
  if (typeof localStorage === "undefined") return DEFAULT_APP_SESSION

  try {
    const stored = JSON.parse(localStorage.getItem(APP_SESSION_KEY) ?? "null")
    if (!isRecord(stored) || stored.version !== APP_SESSION_VERSION) {
      return DEFAULT_APP_SESSION
    }
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
