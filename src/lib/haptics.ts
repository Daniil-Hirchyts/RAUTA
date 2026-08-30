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
 * not, so stable HTML buttons are enhanced separately by
 * installDirectTouchHaptics().
 */
export function triggerHaptic(input: HapticInput) {
  if (typeof navigator === "undefined" || !("vibrate" in navigator)) return
  navigator.vibrate(VIBRATION_PATTERNS[input])
}

const HAPTIC_TARGETS = "button:not([data-haptics=off])"
const UNSAFE_GESTURE_SURFACE =
  '[data-slot="drawer-popup"], [data-swipe-ignore], [draggable="true"]'
const SCROLLABLE_OVERFLOW = new Set(["auto", "scroll"])

function isIOS() {
  if (typeof navigator === "undefined") return false
  return (
    /iP(?:hone|ad|od)/.test(navigator.userAgent) ||
    (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
  )
}

/**
 * ios-haptics works by placing a transparent native switch directly above a
 * button. That is fine for a tap-only control, but the switch becomes the
 * gesture target and can interfere with scrolling, dragging, and swiping.
 * Never install it on controls that live in those interaction surfaces.
 */
function isDirectTouchSafe(button: HTMLButtonElement) {
  if (button.closest(UNSAFE_GESTURE_SURFACE)) return false

  let element: HTMLElement | null = button.parentElement
  while (element && element !== document.body) {
    const style = getComputedStyle(element)
    if (
      SCROLLABLE_OVERFLOW.has(style.overflowX) ||
      SCROLLABLE_OVERFLOW.has(style.overflowY)
    ) {
      return false
    }
    element = element.parentElement
  }

  return true
}

function enhanceButton(button: HTMLButtonElement) {
  if (!isIOS()) return
  if (button.disabled) return
  if (!isDirectTouchSafe(button)) return
  if (button.dataset.hapticReady === "true") return
  button.dataset.hapticReady = "true"

  // ios-haptics renders a real, transparent input[switch] over the button.
  // Restrict this to stable tap-only controls; gesture surfaces are handled by
  // their normal pointer/touch events without an overlay.
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
 * Installs direct-touch iOS haptics on current and future stable buttons,
 * including content rendered through portals. Scrollable, draggable, and
 * swipeable interaction surfaces are deliberately left untouched.
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
