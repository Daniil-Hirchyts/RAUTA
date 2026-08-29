import { beforeEach, describe, expect, it } from "vitest"

import { useFavorites } from "@/store/use-favorites"

describe("favorites store", () => {
  beforeEach(() => {
    localStorage.clear()
    useFavorites.setState({ favoriteIds: [] })
  })

  it("toggles favorites on and off", () => {
    useFavorites.getState().toggleFavorite("0001")
    expect(useFavorites.getState().favoriteIds).toEqual(["0001"])
    expect(useFavorites.getState().isFavorite("0001")).toBe(true)

    useFavorites.getState().toggleFavorite("0001")
    expect(useFavorites.getState().favoriteIds).toEqual([])
    expect(useFavorites.getState().isFavorite("0001")).toBe(false)
  })

  it("persists favorites to local storage", () => {
    useFavorites.getState().toggleFavorite("0002")
    const stored = JSON.parse(localStorage.getItem("gym-lib-favorites") ?? "{}")
    expect(stored.state.favoriteIds).toEqual(["0002"])
  })

  it("migrates and removes invalid persisted favorites", async () => {
    localStorage.setItem(
      "gym-lib-favorites",
      JSON.stringify({
        state: { favoriteIds: ["0001", "missing", "0001", 42] },
        version: 0,
      })
    )

    await useFavorites.persist.rehydrate()

    expect(useFavorites.persist.getOptions().version).toBe(1)
    expect(useFavorites.getState().favoriteIds).toEqual(["0001"])
  })
})
