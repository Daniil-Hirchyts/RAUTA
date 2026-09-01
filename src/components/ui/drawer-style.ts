import type { CSSProperties } from "react"

/**
 * A drawer that comes all the way up, leaving only the sliver of background
 * that says the screen underneath is still there. For surfaces whose content
 * is a list long enough that a shorter sheet would be mostly scrollbar.
 *
 * It lives beside the drawer rather than inside it because Fast Refresh only
 * works for modules that export components alone.
 */
export const FULL_HEIGHT_DRAWER_STYLE = {
  "--drawer-content-max-height":
    "calc(var(--app-viewport-height) - 0.5rem - env(safe-area-inset-top))",
  "--drawer-height":
    "calc(var(--app-viewport-height) - 0.5rem - env(safe-area-inset-top))",
} as CSSProperties
