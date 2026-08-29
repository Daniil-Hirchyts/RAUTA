import { create } from "zustand"
import { persist } from "zustand/middleware"

export type FavoritesState = {
  favoriteIds: string[]
  toggleFavorite: (exerciseId: string) => void
  isFavorite: (exerciseId: string) => boolean
}

export const useFavorites = create<FavoritesState>()(
  persist(
    (set, get) => ({
      favoriteIds: [],
      toggleFavorite: (exerciseId) =>
        set((state) => ({
          favoriteIds: state.favoriteIds.includes(exerciseId)
            ? state.favoriteIds.filter((id) => id !== exerciseId)
            : [...state.favoriteIds, exerciseId],
        })),
      isFavorite: (exerciseId) => get().favoriteIds.includes(exerciseId),
    }),
    { name: "gym-lib-favorites" }
  )
)
