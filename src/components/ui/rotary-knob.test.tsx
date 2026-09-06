import { useState } from "react"
import { fireEvent, render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { describe, expect, it, vi } from "vitest"

import { RotaryKnob } from "@/components/ui/rotary-knob"
import { snapToRange } from "@/lib/utils"

const SIZE = 200
const CENTER = SIZE / 2

function Dial({
  initial = 30,
  max = 100,
  min = 18,
  onChange,
  step = 1,
}: {
  initial?: number
  max?: number
  min?: number
  onChange?: (value: number) => void
  step?: number
}) {
  const [value, setValue] = useState(initial)
  return (
    <RotaryKnob
      ariaLabel="Age"
      max={max}
      min={min}
      onChange={(next) => {
        setValue(next)
        onChange?.(next)
      }}
      step={step}
      unit="years"
      value={value}
    />
  )
}

function dial() {
  const knob = screen.getByRole("slider", { name: "Age" })
  // jsdom lays nothing out, so the dial is told where it is on screen.
  knob.getBoundingClientRect = () =>
    ({
      bottom: SIZE,
      height: SIZE,
      left: 0,
      right: SIZE,
      top: 0,
      width: SIZE,
      x: 0,
      y: 0,
      toJSON: () => "",
    }) as DOMRect
  return knob
}

/** A point on the dial's circle, measured the way the control reads angles:
 *  zero at twelve o'clock, growing clockwise. */
function at(degrees: number, distance = 90) {
  const radians = ((degrees - 90) * Math.PI) / 180
  return {
    clientX: CENTER + distance * Math.cos(radians),
    clientY: CENTER + distance * Math.sin(radians),
  }
}

describe("snapToRange", () => {
  it("clamps to the ends and lands on whole steps", () => {
    const range = { min: 20, max: 120, step: 5 }
    expect(snapToRange(-40, range)).toBe(20)
    expect(snapToRange(1000, range)).toBe(120)
    expect(snapToRange(47, range)).toBe(45)
    expect(snapToRange(47.5, range)).toBe(50)
    expect(snapToRange(Number.NaN, range)).toBe(20)
    expect(snapToRange("nope", range)).toBe(20)
    // Repeated stepping must not accumulate binary-float dust.
    expect(snapToRange(20 + 13 * 2.5, { min: 20, max: 120, step: 2.5 })).toBe(
      52.5
    )
  })
})

describe("RotaryKnob", () => {
  it("reports itself as a slider with the value a person would read", () => {
    render(<Dial initial={24} />)
    const knob = screen.getByRole("slider", { name: "Age" })

    expect(knob).toHaveAttribute("aria-valuenow", "24")
    expect(knob).toHaveAttribute("aria-valuemin", "18")
    expect(knob).toHaveAttribute("aria-valuemax", "100")
    expect(knob).toHaveAttribute("aria-valuetext", "24 years")
    expect(knob).toHaveAttribute("tabindex", "0")
    expect(screen.getByText("24")).toBeVisible()
    expect(screen.getByText("years")).toBeVisible()
  })

  it("never puts a text box on screen for a number", () => {
    render(<Dial />)
    expect(screen.queryByRole("textbox")).not.toBeInTheDocument()
    expect(screen.queryByRole("spinbutton")).not.toBeInTheDocument()
    expect(document.querySelector("input")).toBeNull()
  })

  it("turns with a drag around its centre and stops at both ends", () => {
    const onChange = vi.fn()
    render(<Dial initial={50} onChange={onChange} />)
    const knob = dial()

    fireEvent.pointerDown(knob, { pointerId: 1, ...at(0) })
    // 90° of the 270° sweep is a third of the 18–100 range.
    fireEvent.pointerMove(knob, { pointerId: 1, ...at(90) })
    expect(knob).toHaveAttribute("aria-valuenow", "77")

    // Grabbing anywhere never jumps the value: only the turn since the grab
    // counts, so coming back to where the drag started restores it exactly.
    fireEvent.pointerMove(knob, { pointerId: 1, ...at(0) })
    expect(knob).toHaveAttribute("aria-valuenow", "50")

    fireEvent.pointerMove(knob, { pointerId: 1, ...at(-90) })
    expect(knob).toHaveAttribute("aria-valuenow", "23")

    // Winding past the end pins the value there, and turning back answers on
    // the first degree rather than unwinding the overshoot first.
    fireEvent.pointerMove(knob, { pointerId: 1, ...at(-179) })
    expect(knob).toHaveAttribute("aria-valuenow", "18")
    fireEvent.pointerMove(knob, { pointerId: 1, ...at(-135) })
    expect(knob).toHaveAttribute("aria-valuenow", "31")
    fireEvent.pointerUp(knob, { pointerId: 1 })

    // Released: the dial no longer follows the pointer across the screen.
    fireEvent.pointerMove(knob, { pointerId: 1, ...at(90) })
    expect(knob).toHaveAttribute("aria-valuenow", "31")
    expect(onChange).toHaveBeenCalled()
  })

  it("keeps the page still while it is being turned", () => {
    render(<Dial />)
    const knob = dial()
    expect(knob.className).toContain("touch-none")
    expect(knob).toHaveAttribute("data-swipe-ignore")

    fireEvent.pointerDown(knob, { pointerId: 1, ...at(0) })
    const move = new Event("pointermove", { bubbles: true, cancelable: true })
    Object.assign(move, { pointerId: 1, ...at(45) })
    knob.dispatchEvent(move)
    expect(move.defaultPrevented).toBe(true)
  })

  it("steps with a hardware keyboard", async () => {
    const user = userEvent.setup()
    render(<Dial initial={30} step={5} min={20} max={120} />)
    const knob = screen.getByRole("slider", { name: "Age" })

    await user.click(knob)
    await user.keyboard("{ArrowUp}")
    expect(knob).toHaveAttribute("aria-valuenow", "35")
    await user.keyboard("{ArrowLeft}")
    expect(knob).toHaveAttribute("aria-valuenow", "30")
    await user.keyboard("{PageUp}")
    expect(knob).toHaveAttribute("aria-valuenow", "55")
    await user.keyboard("{Home}")
    expect(knob).toHaveAttribute("aria-valuenow", "20")
    await user.keyboard("{ArrowDown}")
    expect(knob).toHaveAttribute("aria-valuenow", "20")
    await user.keyboard("{End}")
    expect(knob).toHaveAttribute("aria-valuenow", "120")
  })

  it("ignores a drag and the keyboard while disabled", () => {
    const onChange = vi.fn()
    render(
      <RotaryKnob
        ariaLabel="Age"
        disabled
        max={100}
        min={18}
        onChange={onChange}
        value={30}
      />
    )
    const knob = dial()

    fireEvent.pointerDown(knob, { pointerId: 1, ...at(0) })
    fireEvent.pointerMove(knob, { pointerId: 1, ...at(90) })
    fireEvent.keyDown(knob, { key: "ArrowUp" })

    expect(onChange).not.toHaveBeenCalled()
    expect(knob).toHaveAttribute("tabindex", "-1")
  })
})
