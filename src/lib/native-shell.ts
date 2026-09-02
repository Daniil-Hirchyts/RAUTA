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

  // Mark the bundled WKWebView before React mounts. A few rendering choices
  // deliberately differ from Safari: the native shell has a permanently
  // clipped viewport and is much more sensitive to masks and live SVG
  // filters while large layers are moving.
  document.documentElement.dataset.native = "ios"

  await Promise.allSettled([
    // Light glyphs, and the web view keeps the space behind the status bar so
    // the rounded app surface can paint underneath it while its content uses
    // env(safe-area-inset-top) as the single source of inset truth.
    StatusBar.setStyle({ style: Style.Dark }),
    StatusBar.setOverlaysWebView({ overlay: true }),
    // Forms scroll inside the stationary surface, so the web view must not
    // also scroll itself out from under the keyboard.
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
