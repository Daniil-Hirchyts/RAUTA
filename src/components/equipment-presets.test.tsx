import { useState } from "react"
import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, describe, expect, it } from "vitest"

import {
  EquipmentPresetEditor,
  EquipmentPresets,
} from "@/components/equipment-presets"
import { useFilters } from "@/store/use-filters"

function PresetHarness() {
  const [creating, setCreating] = useState(false)
  return creating ? (
    <EquipmentPresetEditor onSaved={() => setCreating(false)} />
  ) : (
    <>
      <EquipmentPresets />
      <button onClick={() => setCreating(true)} type="button">
        Create equipment preset
      </button>
    </>
  )
}

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
    render(<PresetHarness />)

    await user.click(
      screen.getByRole("button", { name: "Create equipment preset" })
    )
    expect(
      screen.queryByRole("button", { name: "Full gym" })
    ).not.toBeInTheDocument()
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

    await user.click(
      screen.getByRole("button", { name: "Delete Travel preset" })
    )
    expect(useFilters.getState().equipmentPresets).toHaveLength(0)
    expect(
      screen.queryByRole("button", { name: "Travel" })
    ).not.toBeInTheDocument()
  })
})
