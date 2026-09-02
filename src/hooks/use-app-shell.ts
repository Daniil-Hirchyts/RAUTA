import { createContext, use } from "react"

export const ControlsHostContext = createContext<HTMLDivElement | null>(null)

export function useControlsHost() {
  return use(ControlsHostContext)
}

export type PageLayerContextValue = {
  active: boolean
  entryId: string
}

export const PageLayerContext = createContext<PageLayerContextValue>({
  active: true,
  entryId: "standalone",
})

export function usePageLayer() {
  return use(PageLayerContext)
}
