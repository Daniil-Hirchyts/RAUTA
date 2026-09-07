import { describe, expect, it } from "vitest"

import { progressionNote } from "@/lib/progression-note"
import type { ProgressionRecommendation } from "@/training"

const LOAD = {
  type: "external_load",
  kg: 82.5,
  stationId: "barbell",
  basis: "total",
} as const

function recommendation(
  patch: Partial<ProgressionRecommendation>
): ProgressionRecommendation {
  return {
    action: "hold",
    resistance: LOAD,
    targetReps: { min: 8, max: 12 },
    confidence: "medium",
    reasons: ["within_range"],
    ...patch,
  }
}

describe("what RAUTA is allowed to say about a load", () => {
  it("quotes the step only when it is a step on the same station", () => {
    const note = progressionNote(
      recommendation({ action: "increase_load", reasons: ["top_of_range"] }),
      80
    )
    expect(note).toMatchObject({ kg: 82.5, basis: "total" })
    expect(note?.text).toBe("You hit the top of the range last time. +2.5 kg.")

    // Without a comparable previous load there is no step to name, and none is
    // invented: the claim shrinks to what the engine actually established.
    expect(
      progressionNote(
        recommendation({ action: "increase_load", reasons: ["top_of_range"] })
      )?.text
    ).toBe("You hit the top of the range last time.")
  })

  it("names the reason the engine gave for holding, never a nicer one", () => {
    expect(
      progressionNote(recommendation({ reasons: ["incomplete_sets"] }))?.text
    ).toBe("Last session came up short. Same load again.")
    expect(
      progressionNote(recommendation({ reasons: ["missing_effort"] }))?.text
    ).toBe("No RIR logged last time, so nothing to progress from.")
    expect(
      progressionNote(recommendation({ reasons: ["within_range"] }))?.text
    ).toBe("Keep this load until you reach the top of the range.")
  })

  it("says a station changed rather than pretending the history still applies", () => {
    const note = progressionNote(
      recommendation({
        action: "calibrate",
        resistance: { type: "unknown" },
        reasons: ["context_changed"],
        confidence: "none",
      })
    )
    expect(note).toMatchObject({ kg: null, basis: null })
    expect(note?.text).toBe("Different station today — recalibrating.")
  })

  it("admits to having no evidence at all", () => {
    expect(
      progressionNote(
        recommendation({
          action: "calibrate",
          resistance: { type: "unknown" },
          reasons: ["no_history"],
          confidence: "none",
        })
      )?.text
    ).toBe("Not enough logged sets yet. Find a working load.")
    expect(
      progressionNote(
        recommendation({
          action: "calibrate",
          resistance: { type: "bodyweight" },
          reasons: ["stale_history"],
          confidence: "none",
        })
      )?.text
    ).toBe("It has been a while. Find the load again, easy first set.")
  })

  it("explains a coarse grid as reps rather than as a load it cannot offer", () => {
    expect(
      progressionNote(
        recommendation({
          action: "coarse_grid_progression",
          targetReps: { min: 8, max: 15 },
          reasons: ["coarse_load_grid"],
        })
      )?.text
    ).toBe(
      "This station jumps too far in one step. Hold the load and work to 15 reps."
    )
    expect(
      progressionNote(
        recommendation({
          action: "increase_reps",
          targetReps: { min: 8, max: 13 },
          reasons: ["coarse_load_grid"],
        })
      )?.text
    ).toBe("Next load up is a big jump. Add reps first — up to 13.")
  })

  it("keeps assistance going down rather than reading it as load going up", () => {
    expect(
      progressionNote(
        recommendation({
          action: "reduce_assistance",
          resistance: {
            type: "assistance",
            kg: 15,
            stationId: "assisted",
            basis: "total",
          },
          reasons: ["top_of_range"],
        }),
        20
      )?.text
    ).toBe("Top of the range last time. 5 kg less assist.")
  })

  it("stays silent where the engine gave a reason it cannot honestly phrase", () => {
    expect(
      progressionNote(
        recommendation({
          reasons: ["coarse_grid_requires_alternative_progression"],
        })
      )
    ).toBeNull()
  })
})
