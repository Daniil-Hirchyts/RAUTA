import { Health } from "@flomentumsolutions/capacitor-health-extended"

import { isNative } from "@/lib/native"

const WRITE_PERMISSIONS = {
  permissions: ["WRITE_WORKOUTS", "WRITE_ACTIVE_CALORIES", "READ_WEIGHT"],
} as const

export type AppleHealthConnectionResult =
  | { status: "connected"; bodyWeightKg: number | null }
  | { status: "unavailable"; bodyWeightKg: null }

function weightInKilograms(value: number | undefined, unit: string) {
  if (!value || !Number.isFinite(value) || value <= 0) return null
  const normalizedUnit = unit.toLowerCase()
  const kilograms = normalizedUnit.includes("lb") ? value * 0.45359237 : value
  return kilograms >= 30 && kilograms <= 300
    ? Math.round(kilograms * 10) / 10
    : null
}

export async function requestAppleHealthAccess(): Promise<AppleHealthConnectionResult> {
  if (!isNative()) return { status: "unavailable", bodyWeightKg: null }

  const { available } = await Health.isHealthAvailable()
  if (!available) return { status: "unavailable", bodyWeightKg: null }

  const response = await Health.requestHealthPermissions({
    permissions: [...WRITE_PERMISSIONS.permissions],
  })
  if (!response.permissions.WRITE_WORKOUTS) {
    return { status: "unavailable", bodyWeightKg: null }
  }

  let bodyWeightKg: number | null = null
  if (response.permissions.READ_WEIGHT) {
    try {
      const weight = await Health.queryWeight()
      bodyWeightKg = weightInKilograms(weight.value, weight.unit)
    } catch {
      // A denied/empty read does not prevent workout writes. HealthKit does
      // not distinguish those two cases, so calories use the safe fallback.
    }
  }

  return { status: "connected", bodyWeightKg }
}

export async function openAppleHealthSettings() {
  if (!isNative()) return
  await Health.openAppleHealthSettings()
}

export async function saveCompletedWorkoutToHealth(input: {
  startDate: string
  endDate: string
  activeCalories?: number
  workoutId: string
  workoutName: string
}) {
  if (!isNative()) return false
  const result = await Health.saveWorkout({
    activityType: "strength-training",
    startDate: input.startDate,
    endDate: input.endDate,
    calories: input.activeCalories,
    metadata: {
      gymLibWorkoutId: input.workoutId,
      workoutName: input.workoutName,
    },
  })
  return result.success
}
