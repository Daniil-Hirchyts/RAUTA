import { create } from "zustand"
import { persist } from "zustand/middleware"

import { EQUIPMENT_OPTIONS } from "@/lib/exercises"
import { isMuscleId } from "@/lib/muscles"
import { isRecord, validUniqueStrings } from "@/store/persistence"
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

type PersistedFilterState = Pick<
  FilterState,
  "selectedMuscles" | "selectedEquipment" | "equipmentPresets"
>

const equipmentSet = new Set(EQUIPMENT_OPTIONS)

function validEquipment(value: string) {
  return equipmentSet.has(value)
}

function sanitizeFilterState(value: unknown): PersistedFilterState {
  const state = isRecord(value) ? value : {}
  const rawPresets = Array.isArray(state.equipmentPresets)
    ? state.equipmentPresets
    : []

  const equipmentPresets = rawPresets.flatMap((value) => {
    if (!isRecord(value)) return []
    const id = typeof value.id === "string" ? value.id : ""
    const name = typeof value.name === "string" ? value.name.trim() : ""
    const equipment = validUniqueStrings(value.equipment, validEquipment)

    return id && name && equipment.length > 0 ? [{ id, name, equipment }] : []
  })

  return {
    selectedMuscles: validUniqueStrings(
      state.selectedMuscles,
      isMuscleId
    ) as MuscleId[],
    selectedEquipment: validUniqueStrings(
      state.selectedEquipment,
      validEquipment
    ),
    equipmentPresets,
  }
}

function toggleValue<T>(values: T[], value: T) {
  return values.includes(value)
    ? values.filter((current) => current !== value)
    : [...values, value]
}

export const useFilters = create<FilterState>()(
  persist<FilterState, [], [], PersistedFilterState>(
    (set) => ({
      selectedMuscles: [],
      selectedEquipment: [],
      equipmentPresets: [],
      toggleMuscle: (muscle) =>
        set((state) => ({
          selectedMuscles: toggleValue(state.selectedMuscles, muscle),
        })),
      toggleEquipment: (equipment) =>
        validEquipment(equipment)
          ? set((state) => ({
              selectedEquipment: toggleValue(
                state.selectedEquipment,
                equipment
              ),
            }))
          : undefined,
      setEquipment: (equipment) =>
        set({
          selectedEquipment: validUniqueStrings(equipment, validEquipment),
        }),
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
      version: 1,
      migrate: (persistedState) => sanitizeFilterState(persistedState),
      merge: (persistedState, currentState) => ({
        ...currentState,
        ...sanitizeFilterState(persistedState),
      }),
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
