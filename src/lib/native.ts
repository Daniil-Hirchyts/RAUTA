import { Capacitor } from "@capacitor/core"

/**
 * True only inside the Capacitor iOS shell. On the web build (and in tests)
 * this is always false, so every native-only path stays tree-shakeable and
 * the browser behavior is untouched.
 */
export function isNative() {
  return Capacitor.isNativePlatform()
}
