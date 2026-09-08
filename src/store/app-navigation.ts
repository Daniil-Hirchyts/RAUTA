/** The pages the training profile is edited on. Grouped the way Settings
 *  groups its rows, so one page answers several related questions. */
export type ProfilePage =
  | { type: "profile-basics" }
  | { type: "profile-training" }
  | { type: "profile-health" }
  | { type: "profile-equipment" }
  | { type: "profile-load-steps" }
  | { type: "profile-priorities" }

export type AppPage =
  | { type: "workouts" }
  | { type: "settings" }
  | { type: "onboarding" }
  | ProfilePage
  | { type: "workout-detail"; workoutId: string }
  | { type: "plan-week"; sourceProgramId?: string }
  | { type: "muscles"; preferredWorkoutId?: string | null }
  | { type: "equipment"; preferredWorkoutId?: string | null }
  | { type: "exercises"; preferredWorkoutId?: string | null }
  | { type: "exercise-detail"; exerciseId: string }
  | { type: "workout-destination"; preferredWorkoutId?: string | null }
  | { type: "workout-form"; exerciseIds: string[]; workoutId?: string | null }
  | { type: "equipment-preset" }
  | {
      type: "exercise-alternatives"
      exerciseId: string
      workoutId: string
    }

export type AppPageEntry = {
  id: string
  page: AppPage
}

export type NavigationDirection = "forward" | "back"

export type NavigationState = {
  direction: NavigationDirection
  pages: AppPageEntry[]
}

export type NavigationAction =
  | { type: "push"; entry: AppPageEntry }
  | { type: "pop" }
  | { type: "replace"; entry: AppPageEntry }
  | { type: "reset"; entries: AppPageEntry[] }

function validIdentifier(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0
}

/** Runtime guard for restored state and any imperative navigation boundary. */
export function isValidAppPage(page: AppPage) {
  switch (page.type) {
    case "workouts":
    case "settings":
    case "onboarding":
    case "profile-basics":
    case "profile-training":
    case "profile-health":
    case "profile-equipment":
    case "profile-load-steps":
    case "profile-priorities":
    case "muscles":
    case "equipment":
    case "exercises":
    case "workout-destination":
    case "equipment-preset":
      return true
    case "plan-week":
      return (
        page.sourceProgramId === undefined ||
        validIdentifier(page.sourceProgramId)
      )
    case "workout-detail":
      return validIdentifier(page.workoutId)
    case "exercise-detail":
      return EXERCISES_BY_ID.has(page.exerciseId)
    case "exercise-alternatives":
      return (
        validIdentifier(page.workoutId) && EXERCISES_BY_ID.has(page.exerciseId)
      )
    case "workout-form":
      return (
        (page.workoutId == null || validIdentifier(page.workoutId)) &&
        page.exerciseIds.length > 0 &&
        page.exerciseIds.every((id) => EXERCISES_BY_ID.has(id))
      )
  }
}

export function appNavigationReducer(
  state: NavigationState,
  action: NavigationAction
): NavigationState {
  switch (action.type) {
    case "push":
      if (!isValidAppPage(action.entry.page)) return state
      return {
        direction: "forward",
        pages: [...state.pages, action.entry],
      }
    case "pop":
      if (state.pages.length <= 1) return state
      return {
        direction: "back",
        pages: state.pages.slice(0, -1),
      }
    case "replace":
      if (!isValidAppPage(action.entry.page)) return state
      return {
        direction: "forward",
        pages: [...state.pages.slice(0, -1), action.entry],
      }
    case "reset":
      if (
        action.entries.length === 0 ||
        action.entries.some((entry) => !isValidAppPage(entry.page))
      ) {
        return state
      }
      return {
        direction: "back",
        pages: action.entries,
      }
  }
}

export function pageHasControls(page: AppPage) {
  switch (page.type) {
    case "settings":
    case "workout-destination":
    case "exercise-alternatives":
    case "exercise-detail":
      return false
    default:
      return true
  }
}

export function pageKey(page: AppPage) {
  switch (page.type) {
    case "workout-detail":
      return `${page.type}:${page.workoutId}`
    case "exercise-detail":
      return `${page.type}:${page.exerciseId}`
    case "exercise-alternatives":
      return `${page.type}:${page.workoutId}:${page.exerciseId}`
    case "workout-form":
      return `${page.type}:${page.workoutId ?? "new"}:${page.exerciseIds.join(",")}`
    case "muscles":
    case "equipment":
    case "exercises":
    case "workout-destination":
      return `${page.type}:${page.preferredWorkoutId ?? "new"}`
    default:
      return page.type
  }
}
import { EXERCISES_BY_ID } from "@/lib/exercises"
