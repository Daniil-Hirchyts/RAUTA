import { beforeEach, describe, expect, it } from "vitest"

import {
  DEFAULT_APP_SESSION,
  readAppSession,
  writeAppSession,
} from "@/store/app-session"

const KEY = "gym-lib-app-session"

describe("app session v3", () => {
  beforeEach(() => localStorage.clear())

  it("round-trips the internal page stack", () => {
    writeAppSession({
      ...DEFAULT_APP_SESSION,
      pages: [
        { type: "workouts" },
        { type: "muscles" },
        { type: "equipment" },
        { type: "exercises" },
        { type: "exercise-detail", exerciseId: "0001" },
      ],
      selectedIds: ["0001"],
      selectMode: true,
    })

    expect(readAppSession()).toMatchObject({
      pages: [
        { type: "workouts" },
        { type: "muscles", preferredWorkoutId: null },
        { type: "equipment", preferredWorkoutId: null },
        { type: "exercises", preferredWorkoutId: null },
        { type: "exercise-detail", exerciseId: "0001" },
      ],
      selectedIds: ["0001"],
      selectMode: true,
    })
  })

  it("preserves next-week lineage when planning is restored", () => {
    writeAppSession({
      ...DEFAULT_APP_SESSION,
      pages: [
        { type: "workouts" },
        { type: "plan-week", sourceProgramId: "program-source" },
      ],
    })

    expect(readAppSession().pages).toEqual([
      { type: "workouts" },
      { type: "plan-week", sourceProgramId: "program-source" },
    ])
  })

  // Confirmations used to be pages, and a session written by that build can
  // still be sitting in storage.
  it("drops a stored page this build no longer has", () => {
    localStorage.setItem(
      KEY,
      JSON.stringify({
        state: {
          ...DEFAULT_APP_SESSION,
          pages: [
            { type: "workouts" },
            { type: "settings" },
            { type: "confirmation", kind: "clear-data" },
          ],
        },
        version: 3,
      })
    )
    expect(readAppSession().pages).toEqual([
      { type: "workouts" },
      { type: "settings" },
    ])
  })

  it("migrates a valid version-2 flow into equivalent pages", () => {
    localStorage.setItem(
      KEY,
      JSON.stringify({
        version: 2,
        state: {
          detailExerciseId: "0001",
          detailOpen: true,
          selectedIds: ["0001"],
          selectMode: true,
          stage: 3,
          view: { type: "flow" },
          workoutFormOpen: false,
        },
      })
    )

    expect(readAppSession()).toMatchObject({
      pages: [
        { type: "workouts" },
        { type: "muscles", preferredWorkoutId: null },
        { type: "equipment", preferredWorkoutId: null },
        { type: "exercises", preferredWorkoutId: null },
        { type: "exercise-detail", exerciseId: "0001" },
      ],
      selectedIds: ["0001"],
      selectMode: true,
    })
  })

  it("drops invalid identifiers while keeping a valid root", () => {
    localStorage.setItem(
      KEY,
      JSON.stringify({
        version: 3,
        state: {
          pages: [
            { type: "workout-detail", workoutId: "" },
            { type: "exercise-detail", exerciseId: "unknown" },
          ],
        },
      })
    )
    expect(readAppSession().pages).toEqual([{ type: "workouts" }])
  })
})
