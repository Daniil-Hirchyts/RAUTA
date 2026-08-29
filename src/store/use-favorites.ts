import { create } from "zustand"
import { persist } from "zustand/middleware"

import { EXERCISES_BY_ID } from "@/lib/exercises"
import { isRecord, validUniqueStrings } from "@/store/persistence"

export type FavoritesState = {
  favoriteIds: string[]
  toggleFavorite: (exerciseId: string) => void
  isFavorite: (exerciseId: string) => boolean
}

type PersistedFavoritesState = Pick<FavoritesState, "favoriteIds">

function sanitizeFavoritesState(value: unknown): PersistedFavoritesState {
  const state = isRecord(value) ? value : {}
  return {
    favoriteIds: validUniqueStrings(state.favoriteIds, (id) =>
      EXERCISES_BY_ID.has(id)
    ),
  }
}

export const useFavorites = create<FavoritesState>()(
  persist<FavoritesState, [], [], PersistedFavoritesState>(
    (set, get) => ({
      favoriteIds: [],
      toggleFavorite: (exerciseId) =>
        EXERCISES_BY_ID.has(exerciseId)
          ? set((state) => ({
              favoriteIds: state.favoriteIds.includes(exerciseId)
                ? state.favoriteIds.filter((id) => id !== exerciseId)
                : [...state.favoriteIds, exerciseId],
            }))
          : undefined,
      isFavorite: (exerciseId) => get().favoriteIds.includes(exerciseId),
    }),
    {
      name: "gym-lib-favorites",
      version: 1,
      migrate: (persistedState) => sanitizeFavoritesState(persistedState),
      merge: (persistedState, currentState) => ({
        ...currentState,
        ...sanitizeFavoritesState(persistedState),
      }),
      partialize: ({ favoriteIds }) => ({ favoriteIds }),
    }
  )
)
