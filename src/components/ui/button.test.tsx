import { fireEvent, render, screen } from "@testing-library/react"
import { afterEach, describe, expect, it, vi } from "vitest"

import { Button } from "@/components/ui/button"

afterEach(() => {
  vi.useRealTimers()
})

describe("Button", () => {
  it("refuses a disabled press with a shake instead of swallowing it", () => {
    const onClick = vi.fn()
    render(
      <Button disabled onClick={onClick}>
        Continue
      </Button>
    )

    const button = screen.getByRole("button", { name: "Continue" })
    // Marked refused rather than natively disabled, which is what keeps the
    // press reaching the element at all.
    expect(button).toHaveAttribute("aria-disabled", "true")

    fireEvent.pointerDown(button)
    expect(button).toHaveAttribute("data-shake", "true")

    fireEvent.click(button)
    expect(onClick).not.toHaveBeenCalled()

    fireEvent.animationEnd(button)
    expect(button).not.toHaveAttribute("data-shake")
  })

  it("leaves an enabled press alone", () => {
    const onClick = vi.fn()
    render(<Button onClick={onClick}>Continue</Button>)

    const button = screen.getByRole("button", { name: "Continue" })
    fireEvent.pointerDown(button)
    expect(button).not.toHaveAttribute("data-shake")

    fireEvent.click(button)
    expect(onClick).toHaveBeenCalledTimes(1)
  })

  it("runs a hammered action once, then answers again once the guard lapses", () => {
    vi.useFakeTimers()
    const onClick = vi.fn()
    render(<Button onClick={onClick}>Create workout</Button>)

    const button = screen.getByRole("button", { name: "Create workout" })
    fireEvent.click(button)
    fireEvent.click(button)
    fireEvent.click(button)
    expect(onClick).toHaveBeenCalledTimes(1)

    vi.advanceTimersByTime(350)
    fireEvent.click(button)
    expect(onClick).toHaveBeenCalledTimes(2)
  })

  it("lets a reused button through as soon as it offers something else", () => {
    vi.useFakeTimers()
    const onClick = vi.fn()
    const { rerender } = render(
      <Button aria-label="Pause workout" onClick={onClick} />
    )

    fireEvent.click(screen.getByRole("button", { name: "Pause workout" }))
    // Same element, new question — the guard must not answer it for the user.
    rerender(<Button aria-label="Resume workout" onClick={onClick} />)
    fireEvent.click(screen.getByRole("button", { name: "Resume workout" }))
    expect(onClick).toHaveBeenCalledTimes(2)
  })

  it("drops its pending guard when the action unmounts the button", () => {
    vi.useFakeTimers()
    const clearTimeoutSpy = vi.spyOn(globalThis, "clearTimeout")
    const { unmount } = render(<Button>Delete workout</Button>)

    fireEvent.click(screen.getByRole("button", { name: "Delete workout" }))
    unmount()
    expect(clearTimeoutSpy).toHaveBeenCalled()
    clearTimeoutSpy.mockRestore()
  })
})
