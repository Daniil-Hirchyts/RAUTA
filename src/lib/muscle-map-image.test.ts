import { describe, expect, it } from "vitest"

import { EXERCISES_BY_ID } from "@/lib/exercises"
import {
  muscleMapKey,
  muscleMapPng,
  muscleMapSvg,
  preferredSide,
} from "@/lib/muscle-map-image"

describe("preferredSide", () => {
  it("faces the figure the way the exercise is about", () => {
    expect(preferredSide(["chest", "triceps", "deltoids"])).toBe("front")
    expect(preferredSide(["gluteal", "hamstring", "lower-back"])).toBe("back")
    expect(preferredSide(["upper-back", "biceps", "forearm"])).toBe("back")
  })

  it("keeps a body with nothing to show facing forward", () => {
    expect(preferredSide([])).toBe("front")
  })
})

describe("muscleMapKey", () => {
  it("names the drawing by its side and the muscles in it", () => {
    expect(muscleMapKey(["chest", "triceps"])).toBe("front-chest-triceps")
    expect(muscleMapKey(["chest", "chest", "triceps"])).toBe(
      "front-chest-triceps"
    )
  })

  it("is empty for an exercise with no muscles to draw", () => {
    expect(muscleMapKey([])).toBe("")
  })
})

describe("muscleMapSvg", () => {
  it("draws one figure with the worked muscles picked out", () => {
    const exercise = EXERCISES_BY_ID.get("0001")!
    const svg = muscleMapSvg(exercise.muscles)

    // A single body, at the size the native side rasterizes it to.
    expect(svg).toContain('viewBox="0 0 727 1280"')
    expect(svg).toContain('width="300" height="528"')
    expect(svg).toContain('fill="#ff6633"')
    expect(svg).toContain('fill="#4b4b56"')
  })

  it("brings whichever figure it drew back onto the canvas origin", () => {
    // The back view's own box starts at x=718; drawn on its own it has to come
    // back to zero or the whole body falls outside the canvas.
    expect(muscleMapSvg(["gluteal", "hamstring"])).toContain(
      'transform="translate(-718 -95)"'
    )
    expect(muscleMapSvg(["chest"])).toContain('transform="translate(0 -95)"')
  })

  it("leaves every muscle unlit when nothing is worked", () => {
    expect(muscleMapSvg([])).not.toContain('fill="#ff6633"')
  })
})

describe("muscleMapPng", () => {
  it("prepares nothing off the native shell, where there is no card to draw", () => {
    const exercise = EXERCISES_BY_ID.get("0001")!
    expect(muscleMapPng(exercise.muscles)).toBeNull()
  })
})
