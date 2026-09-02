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

/**
 * The shell's control band. Every set of bottom actions renders into it — a
 * screen's own and a drawer's alike — so the band is a fixed piece of the shell
 * that sheets slide up behind, and only its contents change hands.
 */
export const ControlsHostContext = createContext<HTMLDivElement | null>(null)

export function useControlsHost() {
  return use(ControlsHostContext)
}
