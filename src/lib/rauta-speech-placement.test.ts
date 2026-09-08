import { describe, expect, it } from "vitest"

import { placeRautaSpeech } from "@/lib/rauta-speech-placement"

/**
 * Where the bubble lands.
 *
 * What is tested here is what a person can see: the bubble is next to the
 * character, it is wholly on the screen however far the character has been
 * thrown, and it stays off the page's own title.
 */

/** A phone-shaped surface with a title bar at the top of it. */
const FRAME = { left: 4, top: 64, width: 382, height: 660 }
const BUBBLE = { width: 240, height: 96 }
const SIZE = 104

function character(left: number, top: number) {
  return { left, top, width: SIZE, height: SIZE }
}

describe("placing what RAUTA says", () => {
  it("speaks above itself, pointing down at its own head", () => {
    const spot = placeRautaSpeech({
      character: character(140, 400),
      bubble: BUBBLE,
      frame: FRAME,
    })

    expect(spot.side).toBe("top")
    // Ten pixels of air between the bubble's foot and the character.
    expect(400 + spot.y + BUBBLE.height).toBe(400 - 10)
    // Centred on the character.
    expect(140 + spot.x + BUBBLE.width / 2).toBe(140 + SIZE / 2)
  })

  it("moves under the character rather than over the page's title", () => {
    const spot = placeRautaSpeech({
      character: character(140, FRAME.top + 8),
      bubble: BUBBLE,
      frame: FRAME,
    })

    expect(spot.side).toBe("bottom")
    expect(FRAME.top + 8 + spot.y).toBeGreaterThanOrEqual(FRAME.top)
  })

  it("stays on the screen when the character is thrown into a corner", () => {
    const corner = character(FRAME.left + FRAME.width - SIZE, 300)
    const spot = placeRautaSpeech({
      character: corner,
      bubble: BUBBLE,
      frame: FRAME,
    })

    const left = corner.left + spot.x
    expect(left).toBeGreaterThanOrEqual(FRAME.left)
    expect(left + BUBBLE.width).toBeLessThanOrEqual(FRAME.left + FRAME.width)
  })

  it("respects room a screen asks to keep clear", () => {
    const spot = placeRautaSpeech({
      character: character(140, 560),
      bubble: BUBBLE,
      frame: FRAME,
      inset: { bottom: 220 },
    })

    // The bubble cannot use the reserved strip, so it goes above instead.
    expect(spot.side).toBe("top")
    expect(560 + spot.y + BUBBLE.height).toBeLessThanOrEqual(
      FRAME.top + FRAME.height - 220
    )
  })

  it("is still shown in full on a screen too small for it", () => {
    const tiny = { left: 0, top: 0, width: 200, height: 120 }
    const spot = placeRautaSpeech({
      character: character(40, 20),
      bubble: BUBBLE,
      frame: tiny,
    })

    // Nothing fits, so the bubble is clamped to the corner it can reach rather
    // than being placed off the screen entirely.
    expect(40 + spot.x).toBeLessThanOrEqual(tiny.left + 8)
    expect(20 + spot.y).toBeLessThanOrEqual(tiny.top + 8)
    expect(40 + spot.x).toBeGreaterThanOrEqual(
      tiny.left + tiny.width - BUBBLE.width - 8
    )
  })
})
