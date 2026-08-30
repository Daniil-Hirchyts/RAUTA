import { useEffect } from "react"

import { installDirectTouchHaptics } from "@/lib/haptics"

export function HapticLayer() {
  useEffect(() => installDirectTouchHaptics(), [])
  return null
}
