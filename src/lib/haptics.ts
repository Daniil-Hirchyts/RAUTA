import { WebHaptics, type HapticInput } from "web-haptics"

let haptics: WebHaptics | undefined

function getHaptics() {
  if (typeof window === "undefined") return undefined
  haptics ??= new WebHaptics()
  return haptics
}

export function triggerHaptic(input: HapticInput) {
  void getHaptics()?.trigger(input)
}
