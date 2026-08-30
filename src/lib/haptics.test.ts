import { afterEach, describe, expect, it, vi } from "vitest"

import { installDirectTouchHaptics, triggerHaptic } from "@/lib/haptics"

const originalUserAgent = navigator.userAgent

function mockIOS() {
  Object.defineProperty(navigator, "userAgent", {
    configurable: true,
    value: "Mozilla/5.0 (iPhone; CPU iPhone OS 26_5 like Mac OS X)",
  })
}

afterEach(() => {
  Object.defineProperty(navigator, "userAgent", {
    configurable: true,
    value: originalUserAgent,
  })
  document.body.replaceChildren()
})

describe("haptics", () => {
  it("uses the Vibration API where it is available", () => {
    triggerHaptic("success")
    expect(navigator.vibrate).toHaveBeenCalledWith([12, 35, 18])
  })

  it("routes a direct iOS switch tap to a stable button action", async () => {
    mockIOS()

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
  })

  it("does not overlay buttons inside a scrollable surface", () => {
    mockIOS()

    const scroller = document.createElement("div")
    scroller.style.overflowY = "auto"
    const button = document.createElement("button")
    scroller.append(button)
    document.body.append(scroller)

    const stop = installDirectTouchHaptics()

    expect(
      button.querySelector("input[type='checkbox'][switch]")
    ).not.toBeInTheDocument()

    stop()
  })

  it("does not overlay buttons inside swipe or drawer surfaces", () => {
    mockIOS()

    const swipeSurface = document.createElement("div")
    swipeSurface.dataset.swipeIgnore = ""
    const swipeButton = document.createElement("button")
    swipeSurface.append(swipeButton)

    const drawer = document.createElement("div")
    drawer.dataset.slot = "drawer-popup"
    const drawerButton = document.createElement("button")
    drawer.append(drawerButton)

    document.body.append(swipeSurface, drawer)

    const stop = installDirectTouchHaptics()

    expect(
      swipeButton.querySelector("input[type='checkbox'][switch]")
    ).not.toBeInTheDocument()
    expect(
      drawerButton.querySelector("input[type='checkbox'][switch]")
    ).not.toBeInTheDocument()

    stop()
  })
})
