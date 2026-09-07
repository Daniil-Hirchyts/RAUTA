import { fireEvent, render, screen } from "@testing-library/react"
import { afterEach, describe, expect, it, vi } from "vitest"

import { Stepper } from "@/components/ui/stepper"

function renderStepper() {
  const steps: number[] = []
  render(
    <Stepper
      display="0"
      label="Load"
      onStep={(direction) => steps.push(direction)}
    />
  )
  return steps
}

describe("Stepper", () => {
  afterEach(() => {
    vi.useRealTimers()
  })

  it("steps once per press and keeps counting while the press is held", () => {
    vi.useFakeTimers()
    const steps = renderStepper()
    const increase = screen.getByRole("button", { name: "Increase load" })

    fireEvent.pointerDown(increase, { button: 0, pointerId: 1 })
    expect(steps).toEqual([1])

    // A hold is how a bar goes from empty to working weight without thirty
    // taps: the repeats close up the longer it is held.
    vi.advanceTimersByTime(2000)
    expect(steps.length).toBeGreaterThan(8)
    expect(steps.every((direction) => direction === 1)).toBe(true)

    const held = steps.length
    fireEvent.pointerUp(increase, { pointerId: 1 })
    vi.advanceTimersByTime(2000)
    expect(steps).toHaveLength(held)
  })

  it("does not double-count a pointer press that also reports a click", () => {
    const steps = renderStepper()
    const decrease = screen.getByRole("button", { name: "Decrease load" })

    fireEvent.pointerDown(decrease, { button: 0, pointerId: 1 })
    fireEvent.pointerUp(decrease, { pointerId: 1 })
    fireEvent.click(decrease, { detail: 1 })
    expect(steps).toEqual([-1])

    // Keyboard activation reports no pointer, and is the one click that steps.
    fireEvent.click(decrease, { detail: 0 })
    expect(steps).toEqual([-1, -1])
  })
})
