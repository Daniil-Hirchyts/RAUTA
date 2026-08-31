import { useEffect } from "react"

import { setScreenAwake } from "@/lib/keep-awake"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useSettings } from "@/store/use-settings"

export function SettingsEffects() {
  const keepAwake = useSettings((state) => state.keepAwake)
  const workoutActive = useActiveWorkout((state) => state.session !== null)

  useEffect(() => {
    void setScreenAwake(keepAwake && workoutActive)
    return () => {
      void setScreenAwake(false)
    }
  }, [keepAwake, workoutActive])

  return null
}
