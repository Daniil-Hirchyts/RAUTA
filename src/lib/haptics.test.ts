import { afterEach, describe, expect, it, vi } from "vitest"

import { installDirectTouchHaptics, triggerHaptic } from "@/lib/haptics"

const originalUserAgent = navigator.userAgent

afterEach(() => {
  Object.defineProperty(navigator, "userAgent", {
    configurable: true,
    value: originalUserAgent,
  })
})

describe("haptics", () => {
  it("uses the Vibration API where it is available", () => {
    triggerHaptic("success")
    expect(navigator.vibrate).toHaveBeenCalledWith([12, 35, 18])
  })

  it("routes a direct iOS switch tap to its button action", async () => {
    Object.defineProperty(navigator, "userAgent", {
      configurable: true,
      value: "Mozilla/5.0 (iPhone; CPU iPhone OS 26_5 like Mac OS X)",
    })

    const button = document.createElement("button")
    const onClick = vi.fn()
    button.addEventListener("click", onClick)
    document.body.append(button)

    const stop = installDirectTouchHaptics()
    const switchInput = button.querySelector<HTMLInputElement>(
      "input[type='checkbox'][switch]"
    )
    expect(switchInput).toBeInTheDocument()

    switchInput?.click()
    await Promise.resolve()
    expect(onClick).toHaveBeenCalledOnce()

    stop()
    button.remove()
  })
})
