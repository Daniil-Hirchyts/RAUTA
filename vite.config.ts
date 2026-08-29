import path from "path"
import { cloudflare } from "@cloudflare/vite-plugin"
import { sites } from "@openai/sites-vite-plugin"
import tailwindcss from "@tailwindcss/vite"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    sites(),
    cloudflare({
      viteEnvironment: { name: "server" },
      config: {
        name: "gym-lib",
        main: "./worker/index.ts",
        compatibility_date: "2026-05-22",
        assets: { not_found_handling: "single-page-application" },
      },
    }),
  ],
  resolve: {
    alias: {
      "@": path.resolve(import.meta.dirname, "./src"),
    },
  },
})
