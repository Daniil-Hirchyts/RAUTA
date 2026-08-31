import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, describe, expect, it } from "vitest"

import { EquipmentPresets } from "@/components/equipment-presets"
import { useFilters } from "@/store/use-filters"

describe("EquipmentPresets", () => {
  beforeEach(() => {
    localStorage.clear()
    useFilters.setState({
      selectedMuscles: [],
      selectedEquipment: ["dumbbell", "band"],
      equipmentPresets: [],
    })
  })

  it("applies and deselects a starter preset on repeat tap", async () => {
    const user = userEvent.setup()
    render(<EquipmentPresets />)

    const homeButton = screen.getByRole("button", { name: "Home kit" })
    await user.click(homeButton)
    expect(useFilters.getState().selectedEquipment).toEqual([
      "body weight",
      "band",
      "resistance band",
      "dumbbell",
      "kettlebell",
    ])
    expect(homeButton).toHaveAttribute("aria-pressed", "true")

    await user.click(homeButton)
    expect(useFilters.getState().selectedEquipment).toEqual([])
    expect(homeButton).toHaveAttribute("aria-pressed", "false")
  })

  it("creates, reuses, toggles, and deletes a custom preset", async () => {
    const user = userEvent.setup()
    render(<EquipmentPresets />)

    await user.click(
      screen.getByRole("button", { name: "Save current selection as a preset" })
    )
    expect(
      document.querySelector("[data-slot='drawer-swipe-handle']")
    ).not.toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: "Close drawer" })
    ).toBeInTheDocument()
    await user.type(screen.getByLabelText("Preset name"), "Travel")
    await user.click(screen.getByRole("button", { name: "Save preset" }))

    expect(useFilters.getState().equipmentPresets[0]).toMatchObject({
      name: "Travel",
      equipment: ["dumbbell", "band"],
    })

    useFilters.getState().setEquipment(["barbell"])
    const travelButton = screen.getByRole("button", { name: "Travel" })
    await user.click(travelButton)
    expect(useFilters.getState().selectedEquipment).toEqual([
      "dumbbell",
      "band",
    ])
    expect(travelButton).toHaveAttribute("aria-pressed", "true")

    await user.click(travelButton)
    expect(useFilters.getState().selectedEquipment).toEqual([])
    expect(travelButton).toHaveAttribute("aria-pressed", "false")

    await user.click(screen.getByRole("button", { name: "Delete Travel preset" }))
    expect(useFilters.getState().equipmentPresets).toHaveLength(0)
    expect(screen.queryByRole("button", { name: "Travel" })).not.toBeInTheDocument()
  })
})
