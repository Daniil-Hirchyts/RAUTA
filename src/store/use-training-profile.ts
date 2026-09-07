import { create } from "zustand"
import { persist } from "zustand/middleware"

import { isMuscleId } from "@/lib/muscles"
import {
  isExperience,
  isHealthLimitation,
  isPriorityLevel,
  isSupportedGoal,
  nextPriorityLevel,
  PROFILE_AGE,
  SESSION_DURATION,
  type HealthLimitation,
  type MusclePriorityLevel,
  type SupportedTrainingGoal,
} from "@/lib/training-profile"
import { snapToRange, type NumericRange } from "@/lib/utils"
import { isRecord } from "@/store/persistence"
import type { Experience } from "@/training"
import type { MuscleId } from "@/types"

export const TRAINING_PROFILE_STORAGE_KEY = "gym-lib-training-profile"

/** Bumping this re-runs `sanitizeTrainingProfile` over stored values. It never
 *  touches the onboarding record, which is persisted beside the profile rather
 *  than inside it — a schema change is not a reason to ask someone to set the
 *  app up again. */
export const TRAINING_PROFILE_VERSION = 1

export const MAX_PROFILE_NAME_LENGTH = 40

export type MusclePriority = {
  muscleId: MuscleId
  level: MusclePriorityLevel
}

/** The engine's own health shape: healthy, or unsupported with the reasons it
 *  recognises. Stored canonically so the adapter never has to translate. */
export type TrainingProfileHealth =
  { status: "healthy" } | { status: "unsupported"; reasons: HealthLimitation[] }

/**
 * What RAUTA knows about the person training, kept stable so a generated
 * week never has to ask again. Deliberately not the engine's request object:
 * this is application state a person edits, versioned and migration-safe,
 * while the request is derived from it at the moment a plan is built.
 */
export type TrainingProfile = {
  version: number
  /** Empty when not given. The only field that opens a keyboard. */
  name: string
  age: number
  trainingExperience: Experience
  goal: SupportedTrainingGoal
  preferredSessionDurationMinutes: number
  health: TrainingProfileHealth
  /** Only muscles that differ from the engine's normal weighting. */
  priorityMuscles: MusclePriority[]
}

export type OnboardingRecord = {
  completed: boolean
  completedAt: string | null
}

export type PersistedTrainingProfileState = {
  profile: TrainingProfile
  onboarding: OnboardingRecord
}

type TrainingProfileState = PersistedTrainingProfileState & {
  updateProfile: (
    patch: Partial<Omit<TrainingProfile, "version" | "priorityMuscles">>
  ) => void
  setMusclePriority: (
    muscleId: MuscleId,
    level: MusclePriorityLevel | null
  ) => void
  /** Walk one muscle to its next level. Decided inside the update from what is
   *  stored, so a quick second tap advances rather than repeating the first. */
  cycleMusclePriority: (muscleId: MuscleId) => void
  clearMusclePriorities: () => void
  setHealthy: () => void
  toggleHealthLimitation: (limitation: HealthLimitation) => void
  completeOnboarding: (completedAt?: string) => void
  resetTrainingProfile: () => void
}

export function createDefaultTrainingProfile(): TrainingProfile {
  return {
    version: TRAINING_PROFILE_VERSION,
    name: "",
    age: 30,
    // The cautious end of the engine's scale: lower volume and more reps in
    // reserve is the safer thing to assume about someone who has not said.
    trainingExperience: "beginner",
    goal: "general_fitness",
    preferredSessionDurationMinutes: 60,
    health: { status: "healthy" },
    priorityMuscles: [],
  }
}

export const DEFAULT_ONBOARDING: OnboardingRecord = {
  completed: false,
  completedAt: null,
}

export function sanitizeTrainingProfile(value: unknown): TrainingProfile {
  const defaults = createDefaultTrainingProfile()
  const state = isRecord(value) ? value : {}

  const rawPriorities = Array.isArray(state.priorityMuscles)
    ? state.priorityMuscles
    : []
  const seen = new Set<MuscleId>()
  const priorityMuscles = rawPriorities.flatMap<MusclePriority>((entry) => {
    if (!isRecord(entry)) return []
    const muscleId = entry.muscleId
    if (typeof muscleId !== "string" || !isMuscleId(muscleId)) return []
    if (seen.has(muscleId) || !isPriorityLevel(entry.level)) return []
    seen.add(muscleId)
    return [{ muscleId, level: entry.level }]
  })

  return {
    version: TRAINING_PROFILE_VERSION,
    name:
      typeof state.name === "string"
        ? state.name.trim().slice(0, MAX_PROFILE_NAME_LENGTH)
        : defaults.name,
    age: sanitizeNumber(state.age, defaults.age, PROFILE_AGE),
    trainingExperience: isExperience(state.trainingExperience)
      ? state.trainingExperience
      : defaults.trainingExperience,
    goal: isSupportedGoal(state.goal) ? state.goal : defaults.goal,
    preferredSessionDurationMinutes: sanitizeNumber(
      state.preferredSessionDurationMinutes,
      defaults.preferredSessionDurationMinutes,
      SESSION_DURATION
    ),
    health: sanitizeHealth(state.health),
    priorityMuscles,
  }
}

/** A value that is missing rather than out of range keeps the default, not the
 *  bottom of the dial. */
function sanitizeNumber(value: unknown, fallback: number, range: NumericRange) {
  return snapToRange(
    typeof value === "number" && Number.isFinite(value) ? value : fallback,
    range
  )
}

function sanitizeHealth(value: unknown): TrainingProfileHealth {
  if (!isRecord(value) || value.status !== "unsupported") {
    return { status: "healthy" }
  }
  const reasons = Array.isArray(value.reasons)
    ? [...new Set(value.reasons.filter(isHealthLimitation))]
    : []
  // The engine rejects an unsupported status with no reason behind it.
  return reasons.length
    ? { status: "unsupported", reasons }
    : { status: "healthy" }
}

function sanitizeOnboarding(value: unknown): OnboardingRecord {
  const state = isRecord(value) ? value : {}
  const completedAt =
    typeof state.completedAt === "string" ? state.completedAt : null
  return {
    completed: state.completed === true,
    completedAt: state.completed === true ? completedAt : null,
  }
}

export function sanitizeTrainingProfileState(
  value: unknown
): PersistedTrainingProfileState {
  const state = isRecord(value) ? value : {}
  return {
    profile: sanitizeTrainingProfile(state.profile),
    onboarding: sanitizeOnboarding(state.onboarding),
  }
}

/** Whether anything in the profile has been said rather than assumed. Used to
 *  decide a first-run conflict against a cloud copy the same way the other
 *  stores do. */
export function isTrainingProfileConfigured(
  state: PersistedTrainingProfileState
) {
  return (
    state.onboarding.completed ||
    JSON.stringify(state.profile) !==
      JSON.stringify(createDefaultTrainingProfile())
  )
}

export const useTrainingProfile = create<TrainingProfileState>()(
  persist<TrainingProfileState, [], [], PersistedTrainingProfileState>(
    (set) => ({
      profile: createDefaultTrainingProfile(),
      onboarding: { ...DEFAULT_ONBOARDING },
      updateProfile: (patch) =>
        set((state) => ({
          profile: sanitizeTrainingProfile({ ...state.profile, ...patch }),
        })),
      setMusclePriority: (muscleId, level) =>
        set((state) => {
          const rest = state.profile.priorityMuscles.filter(
            (entry) => entry.muscleId !== muscleId
          )
          return {
            profile: {
              ...state.profile,
              priorityMuscles: level ? [...rest, { muscleId, level }] : rest,
            },
          }
        }),
      cycleMusclePriority: (muscleId) =>
        set((state) => {
          const current =
            state.profile.priorityMuscles.find(
              (entry) => entry.muscleId === muscleId
            )?.level ?? null
          const level = nextPriorityLevel(current)
          const rest = state.profile.priorityMuscles.filter(
            (entry) => entry.muscleId !== muscleId
          )
          return {
            profile: {
              ...state.profile,
              priorityMuscles: level ? [...rest, { muscleId, level }] : rest,
            },
          }
        }),
      clearMusclePriorities: () =>
        set((state) => ({
          profile: { ...state.profile, priorityMuscles: [] },
        })),
      setHealthy: () =>
        set((state) => ({
          profile: { ...state.profile, health: { status: "healthy" } },
        })),
      toggleHealthLimitation: (limitation) =>
        set((state) => {
          const current =
            state.profile.health.status === "unsupported"
              ? state.profile.health.reasons
              : []
          const reasons = current.includes(limitation)
            ? current.filter((reason) => reason !== limitation)
            : [...current, limitation]
          return {
            profile: {
              ...state.profile,
              health: reasons.length
                ? { status: "unsupported", reasons }
                : { status: "healthy" },
            },
          }
        }),
      completeOnboarding: (completedAt = new Date().toISOString()) =>
        set({ onboarding: { completed: true, completedAt } }),
      resetTrainingProfile: () =>
        set({
          profile: createDefaultTrainingProfile(),
          onboarding: { ...DEFAULT_ONBOARDING },
        }),
    }),
    {
      name: TRAINING_PROFILE_STORAGE_KEY,
      version: TRAINING_PROFILE_VERSION,
      migrate: (persistedState) => sanitizeTrainingProfileState(persistedState),
      merge: (persistedState, currentState) => ({
        ...currentState,
        ...sanitizeTrainingProfileState(persistedState),
      }),
      partialize: ({ onboarding, profile }) => ({ onboarding, profile }),
    }
  )
)
