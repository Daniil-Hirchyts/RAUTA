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
