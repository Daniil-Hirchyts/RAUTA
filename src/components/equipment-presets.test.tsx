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

  it("applies a starter preset", async () => {
    const user = userEvent.setup()
    render(<EquipmentPresets />)

    await user.click(screen.getByRole("button", { name: "Home kit" }))
    expect(useFilters.getState().selectedEquipment).toEqual([
      "body weight",
      "band",
      "resistance band",
      "dumbbell",
      "kettlebell",
    ])
  })

  it("creates and reuses a custom preset", async () => {
    const user = userEvent.setup()
    render(<EquipmentPresets />)

    await user.click(
      screen.getByRole("button", { name: "Save current selection as a preset" })
    )
    await user.type(screen.getByLabelText("Preset name"), "Travel")
    await user.click(screen.getByRole("button", { name: "Save preset" }))

    expect(useFilters.getState().equipmentPresets[0]).toMatchObject({
      name: "Travel",
      equipment: ["dumbbell", "band"],
    })

    useFilters.getState().setEquipment(["barbell"])
    await user.click(screen.getByRole("button", { name: "Travel" }))
    expect(useFilters.getState().selectedEquipment).toEqual([
      "dumbbell",
      "band",
    ])
  })
})
