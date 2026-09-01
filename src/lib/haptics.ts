import { Haptics, ImpactStyle, NotificationType } from "@capacitor/haptics"
import { hapticTrigger } from "ios-haptics"

import { isNative } from "@/lib/native"
import { useSettings } from "@/store/use-settings"

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
 * Inside the native shell each input maps onto the real UIKit feedback
 * generator it was named for, which the web build cannot reach.
 */
const NATIVE_HAPTICS: Record<HapticInput, () => Promise<void>> = {
  selection: () => selectionTick(),
  light: () => Haptics.impact({ style: ImpactStyle.Light }),
  medium: () => Haptics.impact({ style: ImpactStyle.Medium }),
  heavy: () => Haptics.impact({ style: ImpactStyle.Heavy }),
  success: () => Haptics.notification({ type: NotificationType.Success }),
  warning: () => Haptics.notification({ type: NotificationType.Warning }),
}

let selectionGeneratorReady: Promise<void> | null = null

/**
 * UISelectionFeedbackGenerator only fires once it exists, and the plugin
 * creates it in selectionStart(). Without that first call selectionChanged()
 * is silently dropped, so prepare it once and keep it alive — a prepared
 * generator is also what keeps the tick latency low.
 */
function selectionTick() {
  selectionGeneratorReady ??= Haptics.selectionStart()
  return selectionGeneratorReady.then(() => Haptics.selectionChanged())
}

/**
 * Android and other compatible browsers expose the Vibration API. iOS Safari
 * does not, so stable HTML buttons are enhanced separately by
 * installDirectTouchHaptics(). The native shell needs neither and calls
 * straight into UIKit.
 */
export function triggerHaptic(input: HapticInput) {
  const { hapticsEnabled, soundChimesEnabled } = useSettings.getState()
  if (soundChimesEnabled && (input === "success" || input === "warning")) {
    playSoundChime(input)
  }
  if (!hapticsEnabled) return

  if (isNative()) {
    // Fire and forget: a dropped haptic must never surface as an unhandled
    // rejection or block the interaction that asked for it.
    void NATIVE_HAPTICS[input]().catch(() => undefined)
    return
  }

  if (typeof navigator === "undefined" || !("vibrate" in navigator)) return
  navigator.vibrate(VIBRATION_PATTERNS[input])
}

function playSoundChime(input: "success" | "warning") {
  if (typeof window === "undefined" || !("AudioContext" in window)) return

  try {
    const context = new AudioContext()
    const oscillator = context.createOscillator()
    const gain = context.createGain()
    oscillator.frequency.value = input === "success" ? 740 : 420
    oscillator.type = "sine"
    gain.gain.setValueAtTime(0.0001, context.currentTime)
    gain.gain.exponentialRampToValueAtTime(0.08, context.currentTime + 0.01)
    gain.gain.exponentialRampToValueAtTime(0.0001, context.currentTime + 0.16)
    oscillator.connect(gain)
    gain.connect(context.destination)
    oscillator.start()
    oscillator.stop(context.currentTime + 0.17)
    oscillator.addEventListener("ended", () => void context.close(), {
      once: true,
    })
  } catch {
    // Audio feedback is optional; unsupported or blocked playback is harmless.
  }
}

const HAPTIC_TARGETS = "button:not([data-haptics=off])"
const DRAWER_SURFACE = '[data-slot="drawer-popup"]'
const UNSAFE_GESTURE_SURFACE = `${DRAWER_SURFACE}, [data-swipe-ignore], [draggable="true"]`
const SCROLLABLE_OVERFLOW = new Set(["auto", "scroll"])

function isIOS() {
  if (typeof navigator === "undefined") return false
  return (
    /iP(?:hone|ad|od)/.test(navigator.userAgent) ||
    (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
  )
}

function hasOpenDrawer() {
  // A dismissed drawer stays mounted through its exit animation, and stays
  // mounted indefinitely if the view changes before that animation finishes.
  // Matching on presence alone would then suspend button haptics forever.
  return document.querySelector(`${DRAWER_SURFACE}:not([data-closed])`) !== null
}

function getSwitchInput(button: HTMLButtonElement) {
  return button.querySelector<HTMLInputElement>(
    ":scope > input[type='checkbox'][switch]"
  )
}

function removeButtonHaptics(button: HTMLButtonElement) {
  getSwitchInput(button)?.remove()
  delete button.dataset.hapticReady
}

function suspendAllDirectTouchHaptics() {
  document
    .querySelectorAll<HTMLButtonElement>('button[data-haptic-ready="true"]')
    .forEach(removeButtonHaptics)
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
  if (hasOpenDrawer()) return
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

  const switchInput = getSwitchInput(button)
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
  if (!button.matches(HAPTIC_TARGETS) || !isDirectTouchSafe(button)) {
    removeButtonHaptics(button)
    return
  }

  enhanceButton(button)
  const switchInput = getSwitchInput(button)
  if (switchInput) switchInput.disabled = button.disabled
}

function enhanceTree(root: ParentNode) {
  root.querySelectorAll<HTMLButtonElement>(HAPTIC_TARGETS).forEach(syncButton)
}

function reconcileDirectTouchHaptics() {
  if (!isIOS()) return

  if (!useSettings.getState().hapticsEnabled) {
    suspendAllDirectTouchHaptics()
    return
  }

  // Base UI drawers are controlled gesture surfaces. Even a haptic switch on
  // an underlying page button can participate in the same iOS touch sequence
  // and make a drawer action close and immediately reopen. While any drawer is
  // mounted, remove all direct-touch switches. Normal drawer buttons and swipe
  // dismissal then operate without synthetic clicks. Stable-button haptics are
  // restored automatically after the drawer unmounts.
  if (hasOpenDrawer()) {
    suspendAllDirectTouchHaptics()
    return
  }

  document
    .querySelectorAll<HTMLButtonElement>('button[data-haptic-ready="true"]')
    .forEach((button) => {
      if (!button.matches(HAPTIC_TARGETS) || !isDirectTouchSafe(button)) {
        removeButtonHaptics(button)
      }
    })

  enhanceTree(document)
}

/**
 * Installs direct-touch iOS haptics on current and future stable buttons.
 * Scrollable, draggable, swipeable, and drawer interaction surfaces are
 * deliberately left untouched.
 *
 * The native shell has no use for any of this: triggerHaptic() reaches UIKit
 * directly, so the transparent switch overlay would add its gesture-target
 * hazards back for no benefit.
 */
export function installDirectTouchHaptics() {
  if (isNative()) return () => undefined
  if (typeof document === "undefined") return () => undefined
  // The transparent switch exists only to reach iOS Safari's haptics. Anywhere
  // else the observer would wake on every DOM mutation to decide it has
  // nothing to do, so never install it.
  if (!isIOS()) return () => undefined

  reconcileDirectTouchHaptics()
  let drawerWasOpen = hasOpenDrawer()

  // Reconciling the whole document per mutation batch costs an ancestor walk
  // and a getComputedStyle per button, on every React render — hundreds of
  // forced style resolutions while a results grid scrolls. Only the subtrees
  // that actually changed need syncing; the document-wide pass is reserved for
  // the two things that change what every button is allowed to do, a drawer
  // opening or closing and haptics being switched off.
  const pending = new Set<Element>()
  let reconcileQueued = false

  const queueReconcile = (records: MutationRecord[]) => {
    for (const record of records) {
      if (record.type === "attributes") {
        if (record.target instanceof HTMLButtonElement) {
          pending.add(record.target)
        }
        continue
      }
      record.addedNodes.forEach((node) => {
        if (node instanceof Element) pending.add(node)
      })
    }

    if (reconcileQueued) return
    reconcileQueued = true
    queueMicrotask(() => {
      reconcileQueued = false
      const roots = [...pending]
      pending.clear()

      const drawerOpen = hasOpenDrawer()
      const drawerChanged = drawerOpen !== drawerWasOpen
      drawerWasOpen = drawerOpen
      if (drawerChanged || !useSettings.getState().hapticsEnabled) {
        reconcileDirectTouchHaptics()
        return
      }
      if (drawerOpen) return

      roots.forEach((root) => {
        if (root instanceof HTMLButtonElement) syncButton(root)
        enhanceTree(root)
      })
    })
  }

  const observer = new MutationObserver(queueReconcile)
  observer.observe(document.body, {
    // data-closed marks a drawer playing its exit animation, which is what
    // hands control of the whole document back.
    attributeFilter: ["disabled", "data-haptics", "data-closed"],
    attributes: true,
    childList: true,
    subtree: true,
  })

  return () => {
    observer.disconnect()
    suspendAllDirectTouchHaptics()
  }
}
