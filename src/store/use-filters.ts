import { create } from "zustand"
import { persist } from "zustand/middleware"

import type { MuscleId } from "@/types"

export type FilterState = {
  selectedMuscles: MuscleId[]
  selectedEquipment: string[]
  toggleMuscle: (muscle: MuscleId) => void
  toggleEquipment: (equipment: string) => void
  reset: () => void
}

function toggleValue<T>(values: T[], value: T) {
  return values.includes(value)
    ? values.filter((current) => current !== value)
    : [...values, value]
}

export const useFilters = create<FilterState>()(
  persist(
    (set) => ({
      selectedMuscles: [],
      selectedEquipment: [],
      toggleMuscle: (muscle) =>
        set((state) => ({
          selectedMuscles: toggleValue(state.selectedMuscles, muscle),
        })),
      toggleEquipment: (equipment) =>
        set((state) => ({
          selectedEquipment: toggleValue(state.selectedEquipment, equipment),
        })),
      reset: () => set({ selectedMuscles: [], selectedEquipment: [] }),
    }),
    {
      name: "gym-lib-filters",
      partialize: ({ selectedMuscles, selectedEquipment }) => ({
        selectedMuscles,
        selectedEquipment,
      }),
    }
  )
)
