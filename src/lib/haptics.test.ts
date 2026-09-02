import { afterEach, describe, expect, it, vi } from "vitest"

import { installDirectTouchHaptics, triggerHaptic } from "@/lib/haptics"

const originalUserAgent = navigator.userAgent

function mockIOS() {
  Object.defineProperty(navigator, "userAgent", {
    configurable: true,
    value: "Mozilla/5.0 (iPhone; CPU iPhone OS 26_5 like Mac OS X)",
  })
}

async function flushHapticObserver() {
  await Promise.resolve()
  await Promise.resolve()
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

  it("does not overlay buttons inside swipe or retained inactive pages", () => {
    mockIOS()

    const swipeSurface = document.createElement("div")
    swipeSurface.dataset.swipeIgnore = ""
    const swipeButton = document.createElement("button")
    swipeSurface.append(swipeButton)

    const inactivePage = document.createElement("section")
    inactivePage.setAttribute("inert", "")
    const inactiveButton = document.createElement("button")
    inactivePage.append(inactiveButton)

    document.body.append(swipeSurface, inactivePage)

    const stop = installDirectTouchHaptics()

    expect(
      swipeButton.querySelector("input[type='checkbox'][switch]")
    ).not.toBeInTheDocument()
    expect(
      inactiveButton.querySelector("input[type='checkbox'][switch]")
    ).not.toBeInTheDocument()

    stop()
  })

  it("keeps stable page haptics when another page is mounted", async () => {
    mockIOS()

    const stableButton = document.createElement("button")
    document.body.append(stableButton)

    const stop = installDirectTouchHaptics()
    expect(
      stableButton.querySelector("input[type='checkbox'][switch]")
    ).toBeInTheDocument()

    const page = document.createElement("section")
    const pageButton = document.createElement("button")
    page.append(pageButton)
    document.body.append(page)
    await flushHapticObserver()

    expect(
      stableButton.querySelector("input[type='checkbox'][switch]")
    ).toBeInTheDocument()
    expect(
      pageButton.querySelector("input[type='checkbox'][switch]")
    ).toBeInTheDocument()

    stop()
  })
})
