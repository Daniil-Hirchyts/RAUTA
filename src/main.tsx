import { StrictMode } from "react"
import { createRoot } from "react-dom/client"

import "./index.css"
import App from "./App.tsx"
import { startICloudSync } from "@/lib/icloud-sync"
import { startLiveActivitySync } from "@/lib/live-activity-sync"
import { startAppleHealthSync } from "@/lib/health-sync"
import { hideSplashAfterPaint, initNativeShell } from "@/lib/native-shell"

async function startApp() {
  // Restore a cached iCloud copy before the first React frame so reinstalling
  // does not briefly show an empty library and then replace it underneath the
  // user. Both calls are immediate no-ops in the browser build.
  await Promise.allSettled([initNativeShell(), startICloudSync()])

  // Mirrors native accessories for as long as the web view is alive; both are
  // no-ops outside the iOS shell.
  startLiveActivitySync()
  startAppleHealthSync()

  createRoot(document.getElementById("root")!).render(
    <StrictMode>
      <App />
    </StrictMode>
  )

  hideSplashAfterPaint()
}

void startApp()
