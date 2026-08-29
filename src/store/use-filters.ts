import { create } from "zustand"
import { persist } from "zustand/middleware"

import type { MuscleId } from "@/types"

export type EquipmentPreset = {
  id: string
  name: string
  equipment: string[]
}

export type FilterState = {
  selectedMuscles: MuscleId[]
  selectedEquipment: string[]
  equipmentPresets: EquipmentPreset[]
  toggleMuscle: (muscle: MuscleId) => void
  toggleEquipment: (equipment: string) => void
  setEquipment: (equipment: string[]) => void
  saveEquipmentPreset: (name: string) => void
  applyEquipmentPreset: (id: string) => void
  deleteEquipmentPreset: (id: string) => void
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
      equipmentPresets: [],
      toggleMuscle: (muscle) =>
        set((state) => ({
          selectedMuscles: toggleValue(state.selectedMuscles, muscle),
        })),
      toggleEquipment: (equipment) =>
        set((state) => ({
          selectedEquipment: toggleValue(state.selectedEquipment, equipment),
        })),
      setEquipment: (equipment) =>
        set({ selectedEquipment: [...new Set(equipment)] }),
      saveEquipmentPreset: (name) =>
        set((state) => {
          const normalizedName = name.trim()
          if (!normalizedName || state.selectedEquipment.length === 0)
            return state

          const existing = state.equipmentPresets.find(
            (preset) =>
              preset.name.toLowerCase() === normalizedName.toLowerCase()
          )
          if (existing) {
            return {
              equipmentPresets: state.equipmentPresets.map((preset) =>
                preset.id === existing.id
                  ? { ...preset, equipment: [...state.selectedEquipment] }
                  : preset
              ),
            }
          }

          return {
            equipmentPresets: [
              ...state.equipmentPresets,
              {
                id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
                name: normalizedName,
                equipment: [...state.selectedEquipment],
              },
            ],
          }
        }),
      applyEquipmentPreset: (id) =>
        set((state) => {
          const preset = state.equipmentPresets.find((item) => item.id === id)
          return preset ? { selectedEquipment: [...preset.equipment] } : state
        }),
      deleteEquipmentPreset: (id) =>
        set((state) => ({
          equipmentPresets: state.equipmentPresets.filter(
            (preset) => preset.id !== id
          ),
        })),
      reset: () => set({ selectedMuscles: [], selectedEquipment: [] }),
    }),
    {
      name: "gym-lib-filters",
      partialize: ({
        selectedMuscles,
        selectedEquipment,
        equipmentPresets,
      }) => ({
        selectedMuscles,
        selectedEquipment,
        equipmentPresets,
      }),
    }
  )
)
