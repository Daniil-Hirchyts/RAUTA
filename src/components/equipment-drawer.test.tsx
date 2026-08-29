import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, describe, expect, it } from "vitest"

import { EquipmentDrawer } from "@/components/equipment-drawer"
import { useFilters } from "@/store/use-filters"

describe("EquipmentDrawer", () => {
  beforeEach(() => {
    localStorage.clear()
    useFilters.setState({ selectedMuscles: [], selectedEquipment: [] })
  })

  it("selects equipment from the bottom drawer", async () => {
    const user = userEvent.setup()
    render(
      <EquipmentDrawer>
        <span>Open equipment</span>
      </EquipmentDrawer>
    )

    await user.click(screen.getByRole("button", { name: "Choose equipment" }))
    const bodyWeight = (await screen.findAllByLabelText("Body Weight")).find(
      (element) => element.getAttribute("role") === "checkbox"
    )
    expect(bodyWeight).toBeDefined()
    await user.click(bodyWeight!)

    expect(useFilters.getState().selectedEquipment).toContain("body weight")
    expect(screen.getByRole("button", { name: "Done" })).toBeInTheDocument()
  })
})
