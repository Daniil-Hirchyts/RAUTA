import type { CapacitorConfig } from "@capacitor/cli"

/**
 * Gym Lib ships as a fully offline native shell: the Vite build in `dist` is
 * bundled into the app, so there is no `server.url` and no network dependency
 * at runtime.
 */
const config: CapacitorConfig = {
  appId: "com.hirchyts.gymlib",
  appName: "Gym Lib",
  webDir: "dist",
  ios: {
    // The web layer paints its own dark background and already handles safe
    // areas with env(safe-area-inset-*), so let it draw edge to edge and keep
    // WebKit from adding scroll-view insets of its own.
    contentInset: "never",
    // The same black the shell paints (--app-shell): what shows around and
    // behind the web view is the app's own surround, not a mismatched edge.
    backgroundColor: "#000000",
    // The shell itself is overflow-hidden and every scrolling region is an
    // inner container, so the web view's own scroll view only ever produces
    // an unwanted whole-screen rubber band.
    scrollEnabled: false,
  },
  plugins: {
    SplashScreen: {
      // The web app renders instantly from a local bundle, so hold the splash
      // until React has actually painted, then fade it out from JS.
      launchAutoHide: false,
      backgroundColor: "#000000",
      showSpinner: false,
    },
    Keyboard: {
      // Drawer forms size themselves against the viewport height, so let the
      // web view resize and they stay above the keyboard on their own.
      resize: "native",
      resizeOnFullScreen: true,
    },
  },
}

export default config
