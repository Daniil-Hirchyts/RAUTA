import { describe, expect, it } from "vitest"

import {
  appNavigationReducer,
  type AppPageEntry,
  type NavigationState,
} from "@/store/app-navigation"

const workouts: AppPageEntry = { id: "workouts", page: { type: "workouts" } }
const muscles: AppPageEntry = { id: "muscles", page: { type: "muscles" } }

function state(pages: AppPageEntry[] = [workouts]): NavigationState {
  return { direction: "forward", pages }
}

describe("appNavigationReducer", () => {
  it("pushes and pops pages directionally", () => {
    const pushed = appNavigationReducer(state(), {
      type: "push",
      entry: muscles,
    })
    expect(pushed).toEqual({ direction: "forward", pages: [workouts, muscles] })
    expect(appNavigationReducer(pushed, { type: "pop" })).toEqual({
      direction: "back",
      pages: [workouts],
    })
  })

  it("does not pop the root page", () => {
    const initial = state()
    expect(appNavigationReducer(initial, { type: "pop" })).toBe(initial)
  })

  it("replaces only the active page", () => {
    const settings: AppPageEntry = {
      id: "settings",
      page: { type: "settings" },
    }
    expect(
      appNavigationReducer(state([workouts, muscles]), {
        type: "replace",
        entry: settings,
      })
    ).toEqual({ direction: "forward", pages: [workouts, settings] })
  })

  it("resets the entire stack", () => {
    expect(
      appNavigationReducer(state([workouts, muscles]), {
        type: "reset",
        entries: [workouts],
      })
    ).toEqual({ direction: "back", pages: [workouts] })
  })

  it("rejects pages with invalid identifiers", () => {
    const initial = state()
    const invalid = {
      id: "invalid",
      page: { type: "workout-detail", workoutId: "" },
    } as AppPageEntry
    expect(
      appNavigationReducer(initial, { type: "push", entry: invalid })
    ).toBe(initial)
    expect(
      appNavigationReducer(initial, { type: "replace", entry: invalid })
    ).toBe(initial)
  })
})
