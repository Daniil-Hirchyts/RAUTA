import { create } from "zustand"
import { persist } from "zustand/middleware"

import { isRecord } from "@/store/persistence"

export type HealthStatus = "idle" | "connected" | "unavailable" | "error"

export type SettingsPreferences = {
  appleHealthEnabled: boolean
  healthStatus: HealthStatus
  healthBodyWeightKg: number | null
  healthLastConnectedAt: string | null
  autoSyncWorkouts: boolean
  syncActiveCalories: boolean
  hapticsEnabled: boolean
  soundChimesEnabled: boolean
  keepAwake: boolean
}

type SettingsState = SettingsPreferences & {
  setPreference: <Key extends keyof SettingsPreferences>(
    key: Key,
    value: SettingsPreferences[Key]
  ) => void
  resetSettings: () => void
}

export const DEFAULT_SETTINGS: SettingsPreferences = {
  appleHealthEnabled: false,
  healthStatus: "idle",
  healthBodyWeightKg: null,
  healthLastConnectedAt: null,
  autoSyncWorkouts: false,
  syncActiveCalories: true,
  hapticsEnabled: true,
  soundChimesEnabled: false,
  keepAwake: false,
}

const HEALTH_STATUSES = new Set<HealthStatus>([
  "idle",
  "connected",
  "unavailable",
  "error",
])

function oneOf<Value extends string>(
  value: unknown,
  options: Set<Value>,
  fallback: Value
) {
  return typeof value === "string" && options.has(value as Value)
    ? (value as Value)
    : fallback
}

export function sanitizeSettings(value: unknown): SettingsPreferences {
  const state = isRecord(value) ? value : {}
  return {
    appleHealthEnabled: state.appleHealthEnabled === true,
    healthStatus: oneOf(
      state.healthStatus,
      HEALTH_STATUSES,
      DEFAULT_SETTINGS.healthStatus
    ),
    healthBodyWeightKg:
      typeof state.healthBodyWeightKg === "number" &&
      Number.isFinite(state.healthBodyWeightKg) &&
      state.healthBodyWeightKg >= 30 &&
      state.healthBodyWeightKg <= 300
        ? state.healthBodyWeightKg
        : null,
    healthLastConnectedAt:
      typeof state.healthLastConnectedAt === "string"
        ? state.healthLastConnectedAt
        : null,
    autoSyncWorkouts: state.autoSyncWorkouts === true,
    syncActiveCalories: state.syncActiveCalories !== false,
    hapticsEnabled: state.hapticsEnabled !== false,
    soundChimesEnabled: state.soundChimesEnabled === true,
    keepAwake: state.keepAwake === true,
  }
}

export const useSettings = create<SettingsState>()(
  persist<SettingsState, [], [], SettingsPreferences>(
    (set) => ({
      ...DEFAULT_SETTINGS,
      setPreference: (key, value) => set({ [key]: value }),
      resetSettings: () => set(DEFAULT_SETTINGS),
    }),
    {
      name: "gym-lib-settings",
      version: 3,
      migrate: sanitizeSettings,
      merge: (persistedState, currentState) => ({
        ...currentState,
        ...sanitizeSettings(persistedState),
      }),
      partialize: (state) => sanitizeSettings(state),
    }
  )
)
