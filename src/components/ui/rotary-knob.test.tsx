import { useState } from "react"
import { fireEvent, render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { describe, expect, it, vi } from "vitest"

import { RotaryKnob } from "@/components/ui/rotary-knob"
import { snapToRange } from "@/lib/utils"

const WIDTH = 240
const HEIGHT = 88
/** The wheel the drawing is a crown of: its centre sits below the box. These
 *  mirror the control's own geometry, which is what a drag is measured in. */
const ARC_RADIUS = 162
const ARC_CENTER = { x: WIDTH / 2, y: 194 }

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
      bottom: HEIGHT,
      height: HEIGHT,
      left: 0,
      right: WIDTH,
      top: 0,
      width: WIDTH,
      x: 0,
      y: 0,
      toJSON: () => "",
    }) as DOMRect
  return knob
}

/** A point on the wheel, measured the way the control reads angles: zero at
 *  the marker, growing clockwise — so a negative angle is a push to the
 *  left, which brings higher notches under the marker. */
function at(degrees: number) {
  const radians = (degrees * Math.PI) / 180
  return {
    clientX: ARC_CENTER.x + ARC_RADIUS * Math.sin(radians),
    clientY: ARC_CENTER.y - ARC_RADIUS * Math.cos(radians),
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
    // The readout is a row of digits that pop in one at a time; what it says
    // is carried on the group rather than in a single text node.
    expect(screen.getByLabelText("24")).toBeVisible()
    expect(screen.getByText("years")).toBeVisible()
  })

  it("never puts a text box on screen for a number", () => {
    render(<Dial />)
    expect(screen.queryByRole("textbox")).not.toBeInTheDocument()
    expect(screen.queryByRole("spinbutton")).not.toBeInTheDocument()
    expect(document.querySelector("input")).toBeNull()
  })

  it("turns with a drag along the band and stops at both ends", () => {
    const onChange = vi.fn()
    render(<Dial initial={50} onChange={onChange} />)
    const knob = dial()

    fireEvent.pointerDown(knob, { pointerId: 1, buttons: 1, ...at(0) })
    // The notches go with the finger: pushing the band left brings the ones
    // to its right — the higher ones — under the marker. Ten degrees of the
    // wheel is 28px of band, and the band is spaced ten to a notch.
    fireEvent.pointerMove(knob, { pointerId: 1, buttons: 1, ...at(-10) })
    expect(knob).toHaveAttribute("aria-valuenow", "53")
    fireEvent.pointerMove(knob, { pointerId: 1, buttons: 1, ...at(-20) })
    expect(knob).toHaveAttribute("aria-valuenow", "56")

    // Grabbing anywhere never jumps the value: only the turn since the grab
    // counts, so coming back to where the drag started restores it exactly.
    fireEvent.pointerMove(knob, { pointerId: 1, buttons: 1, ...at(0) })
    expect(knob).toHaveAttribute("aria-valuenow", "50")

    fireEvent.pointerMove(knob, { pointerId: 1, buttons: 1, ...at(10) })
    expect(knob).toHaveAttribute("aria-valuenow", "47")

    // Winding past the end pins the value there, and turning back answers on
    // the first notch rather than unwinding the overshoot first.
    fireEvent.pointerMove(knob, { pointerId: 1, buttons: 1, ...at(120) })
    expect(knob).toHaveAttribute("aria-valuenow", "18")
    fireEvent.pointerMove(knob, { pointerId: 1, buttons: 1, ...at(110) })
    expect(knob).toHaveAttribute("aria-valuenow", "21")
    fireEvent.pointerUp(knob, { pointerId: 1 })

    // Released: the dial no longer follows the pointer across the screen.
    fireEvent.pointerMove(knob, { pointerId: 1, buttons: 1, ...at(0) })
    expect(knob).toHaveAttribute("aria-valuenow", "21")
    expect(onChange).toHaveBeenCalled()
  })

  it("lets go when the pointer comes back up somewhere it could not see", () => {
    render(<Dial initial={50} />)
    const knob = dial()

    fireEvent.pointerDown(knob, { pointerId: 1, buttons: 1, ...at(0) })
    fireEvent.pointerMove(knob, { pointerId: 1, buttons: 1, ...at(-10) })
    expect(knob).toHaveAttribute("aria-valuenow", "53")

    // No release ever arrived — capture lost to another window, say. The next
    // move with nothing held ends the gesture instead of turning the dial.
    fireEvent.pointerMove(knob, { pointerId: 1, buttons: 0, ...at(-40) })
    fireEvent.pointerMove(knob, { pointerId: 1, buttons: 0, ...at(-80) })
    expect(knob).toHaveAttribute("aria-valuenow", "53")
  })

  it("paints a wider scale than it will accept, and stops at the range", () => {
    const onChange = vi.fn()
    const notches = () => dial().querySelectorAll("g line").length

    // Nothing is written on the band, so what says the wider scale is painted
    // is that there are more notches on it than the dial will stop at.
    const plain = render(
      <RotaryKnob
        ariaLabel="Age"
        max={75}
        min={18}
        onChange={() => {}}
        value={20}
      />
    )
    const within = notches()
    plain.unmount()

    render(
      <RotaryKnob
        ariaLabel="Age"
        max={75}
        min={18}
        onChange={onChange}
        scaleMax={100}
        scaleMin={0}
        value={20}
      />
    )
    const knob = dial()

    // Years the app will not train are still on the band, drawn faint.
    expect(notches()).toBeGreaterThan(within)
    expect(knob).toHaveAttribute("aria-valuemin", "18")

    fireEvent.pointerDown(knob, { pointerId: 1, buttons: 1, ...at(0) })
    fireEvent.pointerMove(knob, { pointerId: 1, buttons: 1, ...at(60) })
    expect(onChange).toHaveBeenLastCalledWith(18)
    expect(onChange).not.toHaveBeenCalledWith(17)
  })

  it("pops the digits on a step, and holds them still through a drag", () => {
    render(<Dial initial={50} />)
    const knob = dial()
    // The readout is above the wheel rather than inside it, so it is looked
    // for on the control as a whole.
    const digits = () => document.querySelector(".t-digit-group")

    // Arriving is not changing: the first value is drawn at rest.
    expect(digits()).not.toHaveClass("is-animating")

    fireEvent.keyDown(knob, { key: "ArrowUp" })
    expect(knob).toHaveAttribute("aria-valuenow", "51")
    expect(digits()).toHaveClass("is-animating")

    // A dial passing over a notch a frame would restart the pop before it had
    // played, so the number stays legible while it is being turned.
    fireEvent.pointerDown(knob, { pointerId: 1, buttons: 1, ...at(0) })
    fireEvent.pointerMove(knob, { pointerId: 1, buttons: 1, ...at(-10) })
    expect(knob).toHaveAttribute("aria-valuenow", "54")
    expect(digits()).not.toHaveClass("is-animating")
  })

  it("keeps the page still while it is being turned", () => {
    render(<Dial />)
    const knob = dial()
    expect(knob.className).toContain("touch-none")
    expect(knob).toHaveAttribute("data-swipe-ignore")

    fireEvent.pointerDown(knob, { pointerId: 1, ...at(0) })
    const move = new Event("pointermove", { bubbles: true, cancelable: true })
    Object.assign(move, { pointerId: 1, buttons: 1, ...at(20) })
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
    fireEvent.pointerMove(knob, { pointerId: 1, buttons: 1, ...at(-30) })
    fireEvent.keyDown(knob, { key: "ArrowUp" })

    expect(onChange).not.toHaveBeenCalled()
    expect(knob).toHaveAttribute("tabindex", "-1")
  })
})
