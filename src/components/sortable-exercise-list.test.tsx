import { render, screen, waitFor } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import { SortableExerciseList } from "@/components/sortable-exercise-list"

describe("exercise row accessibility", () => {
  it("keeps workout actions enabled when reordering is unavailable", async () => {
    const props = {
      exerciseIds: ["0025"],
      onFindAlternative: () => {},
      onOpenExercise: () => {},
    }
    const { rerender } = render(
      <SortableExerciseList {...props} onReorder={() => {}} />
    )
    rerender(<SortableExerciseList {...props} />)
    await waitFor(() => {
      const action = screen.getByRole("button", { name: "Find alternative" })
      expect(action.closest('[aria-disabled="true"]')).toBeNull()
      expect(action.closest("li")).not.toHaveAttribute("role", "button")
    })
  })
})
