import { Keyboard } from "@capacitor/keyboard"
import { SplashScreen } from "@capacitor/splash-screen"
import { StatusBar, Style } from "@capacitor/status-bar"

import { isNative } from "@/lib/native"

/**
 * Brings the native shell in line with what the web layout already assumes:
 * an edge-to-edge dark surface whose insets come from env(safe-area-inset-*),
 * exactly like the `black-translucent` PWA it was built as.
 *
 * Safe to call unconditionally — on the web it does nothing.
 */
export async function initNativeShell() {
  if (!isNative()) return

  await Promise.allSettled([
    // Light glyphs, and the web view keeps the space behind the status bar so
    // pt-[env(safe-area-inset-top)] stays the single source of inset truth.
    StatusBar.setStyle({ style: Style.Dark }),
    StatusBar.setOverlaysWebView({ overlay: true }),
    // Drawer forms scroll their own content, so the web view must not also
    // scroll itself out from under the keyboard.
    Keyboard.setScroll({ isDisabled: true }),
  ])
}

/**
 * Dismisses the launch image once React has actually painted a frame, so the
 * hand-off happens without a flash of empty background.
 */
export function hideSplashAfterPaint() {
  if (!isNative()) return

  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      void SplashScreen.hide({ fadeOutDuration: 200 }).catch(() => undefined)
    })
  })
}
