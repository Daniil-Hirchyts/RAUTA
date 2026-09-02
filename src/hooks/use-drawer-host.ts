import { createContext, use, type RefObject } from "react"

/**
 * The element drawers portal into: the shell's inner area, provided by
 * AppDrawerHost. Null outside the shell, so a drawer rendered on its own (in a
 * test, say) falls back to the document body.
 */
export const DrawerHostContext =
  createContext<RefObject<HTMLDivElement | null> | null>(null)

export function useDrawerHost() {
  return use(DrawerHostContext)
}
