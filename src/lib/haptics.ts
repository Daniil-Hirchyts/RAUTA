import { hapticTrigger } from "ios-haptics"

export type HapticInput =
  "selection" | "light" | "medium" | "heavy" | "success" | "warning"

const VIBRATION_PATTERNS: Record<HapticInput, number | number[]> = {
  selection: 8,
  light: 12,
  medium: 22,
  heavy: 36,
  success: [12, 35, 18],
  warning: [24, 45, 24],
}

/**
 * Android and other compatible browsers expose the Vibration API. iOS does
 * not, so direct-tap native switch overlays are installed separately by
 * installDirectTouchHaptics().
 */
export function triggerHaptic(input: HapticInput) {
  if (typeof navigator === "undefined" || !("vibrate" in navigator)) return
  navigator.vibrate(VIBRATION_PATTERNS[input])
}

/**
 * Adds an iOS native switch directly over a custom visual hit target. This is
 * used for the SVG muscle map, where separate HTML buttons cannot follow the
 * irregular muscle shapes. The callback receives the original touch point so
 * the map can resolve the SVG region underneath the transparent switch.
 */
export function installDirectTouchTarget(
  element: HTMLElement | null,
  onTouch: (point: { clientX: number; clientY: number }) => void
) {
  if (!element || !isIOS()) return () => undefined

  const originalInlinePosition = element.style.position
  const wasStaticallyPositioned =
    getComputedStyle(element).position === "static"
  hapticTrigger(element)
  if (!wasStaticallyPositioned) element.style.position = originalInlinePosition

  const switchInput = element.querySelector<HTMLInputElement>(
    ":scope > input[type='checkbox'][switch]"
  )
  if (!switchInput) return () => undefined
  switchInput.dataset.hapticTrigger = ""
  switchInput.setAttribute("aria-hidden", "true")
  switchInput.tabIndex = -1
  switchInput.style.pointerEvents = "auto"
  // Keep "manipulation" (ios-haptics' own default, which we'd otherwise be
  // overriding): it permits scrolling in both axes while telling Safari
  // there's no double-tap-to-zoom to wait for, so a tap fires its click
  // immediately. A narrower value like "pan-y" reintroduces that
  // ambiguity — Safari then waits to see whether the gesture becomes a
  // scroll before committing to a click, and on this full-figure overlay
  // (which swallows every touch under it) that wait routinely eats the tap
  // outright, so muscles stop responding to touch while mouse clicks on
  // desktop are unaffected.
  switchInput.style.touchAction = "manipulation"

  const handleClick = (event: MouseEvent) => {
    event.stopPropagation()
    onTouch({ clientX: event.clientX, clientY: event.clientY })
  }
  switchInput.addEventListener("click", handleClick)

  return () => {
    switchInput.removeEventListener("click", handleClick)
    switchInput.remove()
  }
}

const HAPTIC_TARGETS = "button:not([data-haptics=off])"

function isIOS() {
  if (typeof navigator === "undefined") return false
  return (
    /iP(?:hone|ad|od)/.test(navigator.userAgent) ||
    (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
  )
}

function enhanceButton(button: HTMLButtonElement) {
  if (!isIOS()) return
  if (button.disabled) return
  if (button.dataset.hapticReady === "true") return
  button.dataset.hapticReady = "true"

  // ios-haptics 3 renders a real, transparent input[switch] over the button.
  // That direct finger contact is required on iOS 26.5+, where a
  // programmatically clicked hidden switch no longer produces feedback.
  const originalInlinePosition = button.style.position
  const wasStaticallyPositioned = getComputedStyle(button).position === "static"
  hapticTrigger(button)
  if (!wasStaticallyPositioned) button.style.position = originalInlinePosition

  const switchInput = button.querySelector<HTMLInputElement>(
    ":scope > input[type='checkbox'][switch]"
  )
  if (!switchInput) return
  switchInput.dataset.hapticTrigger = ""
  switchInput.setAttribute("aria-hidden", "true")
  switchInput.tabIndex = -1

  switchInput.addEventListener("click", (event) => {
    // Keep the native switch's default toggle (and therefore its haptic), but
    // route the action to the real button exactly once. This also preserves
    // submit-button behavior inside forms.
    event.stopPropagation()
    queueMicrotask(() => button.click())
  })
}

function syncButton(button: HTMLButtonElement) {
  enhanceButton(button)
  const switchInput = button.querySelector<HTMLInputElement>(
    ":scope > input[type='checkbox'][switch]"
  )
  if (switchInput) switchInput.disabled = button.disabled
}

function enhanceTree(root: ParentNode) {
  root.querySelectorAll<HTMLButtonElement>(HAPTIC_TARGETS).forEach(syncButton)
}

/**
 * Installs direct-touch iOS haptics on current and future buttons, including
 * drawer content rendered through portals. Returns a cleanup function.
 */
export function installDirectTouchHaptics() {
  if (typeof document === "undefined") return () => undefined

  enhanceTree(document)

  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      if (
        mutation.type === "attributes" &&
        mutation.target instanceof HTMLButtonElement
      ) {
        syncButton(mutation.target)
      }
      mutation.addedNodes.forEach((node) => {
        if (!(node instanceof HTMLElement)) return
        if (node.matches(HAPTIC_TARGETS) && node instanceof HTMLButtonElement) {
          syncButton(node)
        }
        enhanceTree(node)
      })
    }
  })

  observer.observe(document.body, {
    attributeFilter: ["disabled"],
    attributes: true,
    childList: true,
    subtree: true,
  })
  return () => observer.disconnect()
}
