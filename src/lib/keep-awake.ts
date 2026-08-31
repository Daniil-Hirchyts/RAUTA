import { KeepAwake } from "@capacitor-community/keep-awake"

export async function setScreenAwake(enabled: boolean) {
  try {
    const { isSupported } = await KeepAwake.isSupported()
    if (!isSupported) return false
    if (enabled) await KeepAwake.keepAwake()
    else await KeepAwake.allowSleep()
    return true
  } catch {
    return false
  }
}
