import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import { Button } from "@/components/ui/button"

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
})
