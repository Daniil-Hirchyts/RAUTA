import { StrictMode } from "react"
import { createRoot } from "react-dom/client"

import "./index.css"
import App from "./App.tsx"
import { startLiveActivitySync } from "@/lib/live-activity-sync"
import { startAppleHealthSync } from "@/lib/health-sync"
import { hideSplashAfterPaint, initNativeShell } from "@/lib/native-shell"

void initNativeShell()

// Mirrors the active workout onto the Lock Screen and Dynamic Island for as
// long as the web view is alive; a no-op outside the iOS shell.
startLiveActivitySync()
startAppleHealthSync()

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>
)

hideSplashAfterPaint()
