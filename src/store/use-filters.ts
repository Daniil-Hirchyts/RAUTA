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

export type EquipmentLoadIncrements = Record<string, number>

export type FilterState = {
  selectedMuscles: MuscleId[]
  selectedEquipment: string[]
  /** The equipment you actually have, as opposed to `selectedEquipment`, which
   *  filters one browse and is cleared whenever a new one starts. Kept in this
   *  store so there is one equipment vocabulary, one preset list, and one
   *  place either selection is sanitized. */
  gymEquipment: string[]
  equipmentPresets: EquipmentPreset[]
  /** Physical load step offered by the user's actual equipment. The basis
   *  (total vs each) remains catalogue-defined; this only describes the rack,
   *  stack or plates the person has access to. */
  equipmentLoadIncrements: EquipmentLoadIncrements
  toggleMuscle: (muscle: MuscleId) => void
  toggleEquipment: (equipment: string) => void
  toggleGymEquipment: (equipment: string) => void
  setMuscles: (muscles: MuscleId[]) => void
  setEquipment: (equipment: string[]) => void
  setGymEquipment: (equipment: string[]) => void
  setEquipmentLoadIncrement: (equipment: string, incrementKg: number) => void
  clearEquipmentLoadIncrement: (equipment: string) => void
  saveEquipmentPreset: (name: string, equipment?: string[]) => void
  applyEquipmentPreset: (id: string) => void
  deleteEquipmentPreset: (id: string) => void
  reset: () => void
}

type PersistedFilterState = Pick<
  FilterState,
  | "selectedMuscles"
  | "selectedEquipment"
  | "gymEquipment"
  | "equipmentPresets"
  | "equipmentLoadIncrements"
>

const equipmentSet = new Set(EQUIPMENT_OPTIONS)

function validEquipment(value: string) {
  return equipmentSet.has(value)
}

export function sanitizeFilterState(value: unknown): PersistedFilterState {
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
  const rawLoadIncrements = isRecord(state.equipmentLoadIncrements)
    ? state.equipmentLoadIncrements
    : {}
  const equipmentLoadIncrements = Object.fromEntries(
    Object.entries(rawLoadIncrements).flatMap(([equipment, value]) =>
      validEquipment(equipment) &&
      typeof value === "number" &&
      Number.isFinite(value) &&
      value >= 0.25 &&
      value <= 50
        ? [[equipment, Math.round(value * 100) / 100]]
        : []
    )
  )

  return {
    selectedMuscles: validUniqueStrings(
      state.selectedMuscles,
      isMuscleId
    ) as MuscleId[],
    selectedEquipment: validUniqueStrings(
      state.selectedEquipment,
      validEquipment
    ),
    gymEquipment: validUniqueStrings(state.gymEquipment, validEquipment),
    equipmentPresets,
    equipmentLoadIncrements,
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
      gymEquipment: [],
      equipmentPresets: [],
      equipmentLoadIncrements: {},
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
      toggleGymEquipment: (equipment) =>
        validEquipment(equipment)
          ? set((state) => ({
              gymEquipment: toggleValue(state.gymEquipment, equipment),
            }))
          : undefined,
      setMuscles: (muscles) =>
        set({
          selectedMuscles: validUniqueStrings(
            muscles,
            isMuscleId
          ) as MuscleId[],
        }),
      setEquipment: (equipment) =>
        set({
          selectedEquipment: validUniqueStrings(equipment, validEquipment),
        }),
      setGymEquipment: (equipment) =>
        set({
          gymEquipment: validUniqueStrings(equipment, validEquipment),
        }),
      setEquipmentLoadIncrement: (equipment, incrementKg) =>
        validEquipment(equipment) &&
        Number.isFinite(incrementKg) &&
        incrementKg >= 0.25 &&
        incrementKg <= 50
          ? set((state) => ({
              equipmentLoadIncrements: {
                ...state.equipmentLoadIncrements,
                [equipment]: Math.round(incrementKg * 100) / 100,
              },
            }))
          : undefined,
      clearEquipmentLoadIncrement: (equipment) =>
        set((state) => {
          if (!(equipment in state.equipmentLoadIncrements)) return state
          const equipmentLoadIncrements = { ...state.equipmentLoadIncrements }
          delete equipmentLoadIncrements[equipment]
          return { equipmentLoadIncrements }
        }),
      // Saving takes an explicit selection so the same preset list can be
      // filled from the browse filter or from the equipment the profile holds,
      // rather than either surface growing a preset store of its own.
      saveEquipmentPreset: (name, equipment) =>
        set((state) => {
          const normalizedName = name.trim()
          const selection = validUniqueStrings(
            equipment ?? state.selectedEquipment,
            validEquipment
          )
          if (!normalizedName || selection.length === 0) return state

          const existing = state.equipmentPresets.find(
            (preset) =>
              preset.name.toLowerCase() === normalizedName.toLowerCase()
          )
          if (existing) {
            return {
              equipmentPresets: state.equipmentPresets.map((preset) =>
                preset.id === existing.id
                  ? { ...preset, equipment: selection }
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
                equipment: selection,
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
        gymEquipment,
        equipmentPresets,
        equipmentLoadIncrements,
      }) => ({
        selectedMuscles,
        selectedEquipment,
        gymEquipment,
        equipmentPresets,
        equipmentLoadIncrements,
      }),
    }
  )
)
