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

  it("toggles a muscle from a touch pointer without a synthesized click", () => {
    const onToggle = vi.fn()
    render(<BodyMap onToggle={onToggle} selectedMuscles={[]} />)
    const chest = screen.getByRole("button", { name: "Front Chest" })

    fireEvent.pointerDown(chest, {
      clientX: 120,
      clientY: 220,
      pointerId: 1,
      pointerType: "touch",
    })
    fireEvent.pointerUp(chest, {
      clientX: 123,
      clientY: 221,
      pointerId: 1,
      pointerType: "touch",
    })

    expect(onToggle).toHaveBeenCalledOnce()
    expect(onToggle).toHaveBeenCalledWith("chest")
  })

  it("does not toggle a muscle when the pointer gesture is a swipe", () => {
    const onToggle = vi.fn()
    render(<BodyMap onToggle={onToggle} selectedMuscles={[]} />)
    const chest = screen.getByRole("button", { name: "Front Chest" })

    fireEvent.pointerDown(chest, {
      clientX: 280,
      clientY: 220,
      pointerId: 1,
      pointerType: "touch",
    })
    fireEvent.pointerUp(chest, {
      clientX: 120,
      clientY: 220,
      pointerId: 1,
      pointerType: "touch",
    })

    expect(onToggle).not.toHaveBeenCalled()
    expect(screen.getByText("Back")).toBeInTheDocument()
  })

  it("supports zero-detail click activation for accessibility", () => {
    const onToggle = vi.fn()
    render(<BodyMap onToggle={onToggle} selectedMuscles={[]} />)

    fireEvent.click(screen.getByRole("button", { name: "Front Chest" }), {
      detail: 0,
    })

    expect(onToggle).toHaveBeenCalledWith("chest")
  })

  it("flips to the back view and supports keyboard toggling", () => {
    const onToggle = vi.fn()
    render(<BodyMap onToggle={onToggle} selectedMuscles={["upper-back"]} />)

    fireEvent.click(screen.getByRole("button", { name: "Show back" }))

    expect(navigator.vibrate).toHaveBeenCalled()
    const upperBack = screen.getByRole("button", { name: "Back Upper back" })
    expect(upperBack).toHaveAttribute("aria-pressed", "true")
    fireEvent.keyDown(upperBack, { key: "Enter" })
    expect(onToggle).toHaveBeenCalledWith("upper-back")
  })

  it("renders the count of selected muscles in the corner when enabled", () => {
    render(
      <BodyMap
        onToggle={() => {}}
        selectedMuscles={["chest", "upper-back"]}
        showCornerCount
      />
    )
    expect(screen.getByTestId("stage-count")).toHaveTextContent("2 selected")
  })
})
