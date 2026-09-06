import { spawnSync } from "node:child_process"
import { describe, expect, it } from "vitest"
import {
  compositeAnimationFrame,
  createAnimationCanvas,
  disposeAnimationFrame,
  parseAnimationInfo,
  type AnimationFrame,
} from "../webp-compositor"

describe("animated WebP compositor", () => {
  it("parses the reviewed 1394 delta-frame geometry", () => {
    const result = spawnSync(
      "webpmux",
      ["-info", "public/assets/exercises/webp/1394.webp"],
      { encoding: "utf8" }
    )
    expect(result.status).toBe(0)
    const info = parseAnimationInfo(result.stdout, "1394.webp")
    expect(info.width).toBe(360)
    expect(info.height).toBe(360)
    expect(info.frames).toHaveLength(12)
    expect(info.frames[3]).toEqual({
      width: 259,
      height: 313,
      hasAlpha: true,
      x: 54,
      y: 24,
      disposeToBackground: false,
      blendWithPrevious: true,
    })
    expect(info.frames[4].disposeToBackground).toBe(true)
    expect(info.frames.some((frame) => frame.hasAlpha)).toBe(true)
    expect(
      info.frames.some(
        (frame) =>
          frame.x > 0 ||
          frame.y > 0 ||
          frame.width < info.width ||
          frame.height < info.height
      )
    ).toBe(true)
  })

  it("applies alpha blending at a sub-rectangle canvas offset", () => {
    const canvas = createAnimationCanvas(3, 2, [255, 0, 0, 255])
    const frame: AnimationFrame = {
      width: 1,
      height: 1,
      hasAlpha: true,
      x: 2,
      y: 1,
      disposeToBackground: false,
      blendWithPrevious: true,
    }
    compositeAnimationFrame(
      canvas,
      3,
      2,
      frame,
      new Uint8Array([0, 0, 255, 128])
    )
    expect([...canvas.slice(0, 4)]).toEqual([255, 0, 0, 255])
    expect([...canvas.slice(20, 24)]).toEqual([127, 0, 128, 255])
  })

  it("clears only a disposed frame rectangle to the animation background", () => {
    const background: [number, number, number, number] = [4, 5, 6, 255]
    const canvas = createAnimationCanvas(2, 2, background)
    const frame: AnimationFrame = {
      width: 1,
      height: 1,
      hasAlpha: false,
      x: 1,
      y: 0,
      disposeToBackground: true,
      blendWithPrevious: false,
    }
    compositeAnimationFrame(
      canvas,
      2,
      2,
      frame,
      new Uint8Array([100, 110, 120, 255])
    )
    expect([...canvas.slice(4, 8)]).toEqual([100, 110, 120, 255])
    disposeAnimationFrame(canvas, 2, frame, background)
    expect([...canvas.slice(4, 8)]).toEqual(background)
    expect([...canvas.slice(0, 4)]).toEqual(background)
  })
})
