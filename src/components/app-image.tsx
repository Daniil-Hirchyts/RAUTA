import type { ComponentProps } from "react"

import { cn } from "@/lib/utils"

/** Image with a paint-only loaded state. Mutating the element avoids a React
 * render when several thumbnails finish during a scroll or page transition. */
export function AppImage({ className, onError, onLoad, ...props }: ComponentProps<"img">) {
  return (
    <img
      {...props}
      className={cn("app-media", className)}
      onError={(event) => {
        event.currentTarget.dataset.loaded = "true"
        onError?.(event)
      }}
      onLoad={(event) => {
        event.currentTarget.dataset.loaded = "true"
        onLoad?.(event)
      }}
    />
  )
}
