import { useEffect, useRef, type ComponentProps } from "react"

import { cn } from "@/lib/utils"

/** Image with a paint-only loaded state. Mutating the element avoids a React
 * render when several thumbnails finish during a scroll or page transition. */
type AppImageProps = ComponentProps<"img"> & {
  /** Release animated image decoders once the image is well outside its
   * scroll viewport. This avoids WKWebView retaining hundreds of animations. */
  recycleOffscreen?: boolean
}

export function AppImage({
  className,
  onError,
  onLoad,
  recycleOffscreen = false,
  src,
  ...props
}: AppImageProps) {
  const imageRef = useRef<HTMLImageElement>(null)

  useEffect(() => {
    if (!recycleOffscreen || !src) return
    const element = imageRef.current
    if (!element) return
    if (typeof IntersectionObserver === "undefined") {
      element.src = src
      return
    }

    const root = element.closest<HTMLElement>(
      ".app-scroll-content, .app-scroll-region"
    )
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry?.isIntersecting) {
          if (element.getAttribute("src") !== src) element.src = src
        } else {
          element.removeAttribute("src")
          delete element.dataset.loaded
        }
      },
      { root, rootMargin: "480px 0px" }
    )
    observer.observe(element)
    return () => observer.disconnect()
  }, [recycleOffscreen, src])

  return (
    <img
      {...props}
      className={cn("app-media", className)}
      ref={imageRef}
      src={recycleOffscreen ? undefined : src}
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
