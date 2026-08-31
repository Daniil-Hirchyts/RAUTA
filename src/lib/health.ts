import { Health } from "@flomentumsolutions/capacitor-health-extended"

import { isNative } from "@/lib/native"

const WRITE_PERMISSIONS = {
  permissions: ["WRITE_WORKOUTS", "WRITE_ACTIVE_CALORIES"],
} as const

export type AppleHealthConnectionResult = "connected" | "unavailable"

export async function requestAppleHealthAccess(): Promise<AppleHealthConnectionResult> {
  if (!isNative()) return "unavailable"

  const { available } = await Health.isHealthAvailable()
  if (!available) return "unavailable"

  await Health.requestHealthPermissions({
    permissions: [...WRITE_PERMISSIONS.permissions],
  })
  return "connected"
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
