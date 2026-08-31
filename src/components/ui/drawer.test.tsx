import { fireEvent, render, screen } from "@testing-library/react"
import { useState } from "react"
import { describe, expect, it, vi } from "vitest"

import { Button } from "@/components/ui/button"
import { Drawer, DrawerContent, DrawerTitle } from "@/components/ui/drawer"

function DrawerHarness({ onAction }: { onAction?: () => void }) {
  const [open, setOpen] = useState(true)

  return (
    <Drawer onOpenChange={setOpen} open={open} swipeDirection="down">
      <DrawerContent>
        <DrawerTitle>Touch-safe drawer</DrawerTitle>
        <Button onClick={onAction}>Drawer action</Button>
      </DrawerContent>
    </Drawer>
  )
}

function touch(identifier: number, clientX: number, clientY: number) {
  return { clientX, clientY, identifier, target: document.body }
}

describe("Drawer", () => {
  it("marks interactive controls as swipe-ignored before interaction", () => {
    render(<DrawerHarness />)

    expect(
      screen.getByRole("button", { name: "Drawer action" })
    ).toHaveAttribute("data-base-ui-swipe-ignore", "")
  })

  it("does not dismiss when mobile hit testing misattributes a control tap", () => {
    const onAction = vi.fn()
    render(<DrawerHarness onAction={onAction} />)

    const button = screen.getByRole("button", { name: "Drawer action" })
    const popup = button.closest<HTMLElement>('[data-slot="drawer-popup"]')
    expect(popup).not.toBeNull()

    // Recreate the physical-mobile failure mode: the native event still
    // targets the button, but Base UI's elementFromPoint() lookup sees the
    // animated drawer surface and starts swipe recognition.
    button.removeAttribute("data-base-ui-swipe-ignore")
    const elementFromPoint = document.elementFromPoint
    Object.defineProperty(document, "elementFromPoint", {
      configurable: true,
      value: vi.fn(() => popup),
    })

    try {
      const start = touch(1, 100, 100)
      const firstMove = touch(1, 100, 180)
      const secondMove = touch(1, 100, 360)
      fireEvent.touchStart(button, {
        changedTouches: [start],
        touches: [start],
      })
      fireEvent.touchMove(button, {
        changedTouches: [firstMove],
        touches: [firstMove],
      })
      fireEvent.touchMove(button, {
        changedTouches: [secondMove],
        touches: [secondMove],
      })
      expect(popup).toHaveAttribute("data-swiping")
      fireEvent.touchEnd(button, {
        changedTouches: [secondMove],
        touches: [],
      })
      fireEvent.click(button)
    } finally {
      Object.defineProperty(document, "elementFromPoint", {
        configurable: true,
        value: elementFromPoint,
      })
    }

    expect(onAction).toHaveBeenCalledOnce()
    expect(
      screen.getByRole("dialog", { name: "Touch-safe drawer" })
    ).toBeInTheDocument()
  })

  it("still closes from its explicit close control", () => {
    render(<DrawerHarness />)

    fireEvent.click(screen.getByRole("button", { name: "Close drawer" }))

    expect(
      screen.queryByRole("dialog", { name: "Touch-safe drawer" })
    ).not.toBeInTheDocument()
  })
})
