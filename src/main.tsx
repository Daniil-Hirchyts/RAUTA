import { StrictMode } from "react"
import { createRoot } from "react-dom/client"

import "./index.css"
import App from "./App.tsx"
import { hideSplashAfterPaint, initNativeShell } from "@/lib/native-shell"

void initNativeShell()

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>
)

hideSplashAfterPaint()
