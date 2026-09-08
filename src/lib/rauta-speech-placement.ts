/**
 * Where RAUTA's speech bubble goes.
 *
 * The character can be dragged and thrown anywhere on the screen, so the bubble
 * that belongs to it has to follow — without running off an edge, and without
 * settling on top of the page's own title. So the bubble takes the side of the
 * character that has room for it, and slides along that side until it is fully
 * inside the area it is allowed to use.
 *
 * Pure arithmetic on measured boxes. The component measures, this decides, and
 * the answer is applied as a transform — so a bubble follows a drag without a
 * single re-render.
 */

export type SpeechSide = "top" | "bottom" | "left" | "right"

export type SpeechBox = {
  left: number
  top: number
  width: number
  height: number
}

export type SpeechPlacementInput = {
  /** The character's box, in the coordinates the bubble is positioned in. */
  character: SpeechBox
  /** The measured bubble. Zero until it has been rendered once. */
  bubble: { width: number; height: number }
  /** The area the bubble may use: the visible surface, less its header. */
  frame: SpeechBox
  /** Anything else this screen needs kept clear. */
  inset?: { top?: number; right?: number; bottom?: number; left?: number }
  /** Air between the character and the bubble. */
  gap?: number
}

export type SpeechPlacement = {
  /** Offset from the character's own top-left corner. */
  x: number
  y: number
  side: SpeechSide
}

export const SPEECH_GAP = 10

/** Breathing room kept at every edge of the area the bubble may use. */
const EDGE_MARGIN = 8

/**
 * Above first.
 *
 * A bubble that grows upward covers what has already been read rather than
 * what is about to be tapped, and the character usually sits above the
 * controls it is talking about. Sideways is the last resort: on a phone the
 * bubble is most of the width of the screen, so it almost never fits beside
 * anything.
 */
const SIDES: SpeechSide[] = ["top", "bottom", "right", "left"]

function clamp(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), Math.max(min, max))
}

export function placeRautaSpeech(input: SpeechPlacementInput): SpeechPlacement {
  const { bubble, character, frame } = input
  const gap = input.gap ?? SPEECH_GAP
  const safe = {
    left: frame.left + (input.inset?.left ?? 0) + EDGE_MARGIN,
    top: frame.top + (input.inset?.top ?? 0) + EDGE_MARGIN,
    right: frame.left + frame.width - (input.inset?.right ?? 0) - EDGE_MARGIN,
    bottom: frame.top + frame.height - (input.inset?.bottom ?? 0) - EDGE_MARGIN,
  }

  const room: Record<SpeechSide, number> = {
    top: character.top - gap - safe.top,
    bottom: safe.bottom - (character.top + character.height) - gap,
    left: character.left - gap - safe.left,
    right: safe.right - (character.left + character.width) - gap,
  }
  const needed: Record<SpeechSide, number> = {
    top: bubble.height,
    bottom: bubble.height,
    left: bubble.width,
    right: bubble.width,
  }

  // The first side it fits on, and failing that the side it overflows least —
  // a bubble on a screen too small for it is still clamped into view below.
  const side =
    SIDES.find((candidate) => room[candidate] >= needed[candidate]) ??
    SIDES.reduce((best, candidate) =>
      room[candidate] - needed[candidate] > room[best] - needed[best]
        ? candidate
        : best
    )

  const vertical = side === "top" || side === "bottom"
  const left = vertical
    ? clamp(
        character.left + character.width / 2 - bubble.width / 2,
        safe.left,
        safe.right - bubble.width
      )
    : side === "left"
      ? character.left - gap - bubble.width
      : character.left + character.width + gap
  const top = vertical
    ? side === "top"
      ? character.top - gap - bubble.height
      : character.top + character.height + gap
    : clamp(
        character.top + character.height / 2 - bubble.height / 2,
        safe.top,
        safe.bottom - bubble.height
      )

  // Clamped on both axes whichever side won, so a bubble taller than the room
  // above the character is pushed down into view rather than off the top.
  const x = clamp(left, safe.left, safe.right - bubble.width)
  const y = clamp(top, safe.top, safe.bottom - bubble.height)

  return { x: x - character.left, y: y - character.top, side }
}
