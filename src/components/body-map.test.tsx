import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import { BodyMap } from "@/components/body-map"
import bodyPathData from "@/data/body-paths.generated.json"
import { MUSCLE_IDS } from "@/types"

describe("BodyMap", () => {
  it("contains geometry for every selectable muscle", () => {
    const available = new Set([
      ...bodyPathData.front.parts.map((part) => part.slug),
      ...bodyPathData.back.parts.map((part) => part.slug),
    ])
    expect(MUSCLE_IDS.every((muscle) => available.has(muscle))).toBe(true)
  })

  it("toggles a muscle by touch/click", () => {
    const onToggle = vi.fn()
    render(<BodyMap onToggle={onToggle} selectedMuscles={[]} />)
    fireEvent.click(screen.getByRole("button", { name: "Front Chest" }))
    expect(onToggle).toHaveBeenCalledWith("chest")
  })

  it("flips to the back view and supports keyboard toggling", () => {
    const onToggle = vi.fn()
    render(<BodyMap onToggle={onToggle} selectedMuscles={["upper-back"]} />)

    fireEvent.click(screen.getByRole("button", { name: "Show back view" }))

    expect(navigator.vibrate).toHaveBeenCalled()
    const upperBack = screen.getByRole("button", { name: "Back Upper back" })
    expect(upperBack).toHaveAttribute("aria-pressed", "true")
    fireEvent.keyDown(upperBack, { key: "Enter" })
    expect(onToggle).toHaveBeenCalledWith("upper-back")
  })
})
