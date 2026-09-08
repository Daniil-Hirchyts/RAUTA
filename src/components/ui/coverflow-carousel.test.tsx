import { useState } from "react"
import { fireEvent, render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import { CoverflowCarousel } from "@/components/ui/coverflow-carousel"

/** jsdom lays nothing out, and the deck measures one card to work out
 *  everything else. This is that measurement. */
const CARD = 240
/** Card width plus the default gap: how far one card sits from the next. */
const PITCH = CARD * 1.05

const SLIDES = [
  { id: "one", title: "Card one", description: "The first", media: null },
  { id: "two", title: "Card two", description: "The second", media: null },
  { id: "three", title: "Card three", description: "The third", media: null },
  { id: "four", title: "Card four", description: "The fourth", media: null },
]

function Deck({ onChange }: { onChange?: (id: string) => void }) {
  const [value, setValue] = useState("one")
  return (
    <CoverflowCarousel
      label="Cards"
      onChange={(next) => {
        setValue(next)
        onChange?.(next)
      }}
      slides={SLIDES}
      value={value}
    />
  )
}

function card(name: string) {
  return screen.getByRole("radio", { name: new RegExp(name) })
}

/** A pointer event with a clock of its own: the throw at the end of a drag is
 *  measured in cards per second, and jsdom's own timestamps would make every
 *  drag a flick. */
function pointer(
  target: Element,
  type: string,
  props: { clientX: number; time: number }
) {
  const event = new Event(type, { bubbles: true, cancelable: true })
  Object.assign(event, { buttons: 1, clientX: props.clientX, pointerId: 1 })
  Object.defineProperty(event, "timeStamp", { value: props.time })
  fireEvent(target, event)
}

describe("CoverflowCarousel", () => {
  beforeEach(() => {
    Object.defineProperty(HTMLElement.prototype, "offsetWidth", {
      configurable: true,
      value: CARD,
    })
  })

  afterEach(() => {
    Reflect.deleteProperty(HTMLElement.prototype, "offsetWidth")
  })

  it("is a radio group with the value checked and the only tab stop", () => {
    render(<Deck />)

    expect(screen.getByRole("radiogroup", { name: "Cards" })).toBeVisible()
    expect(screen.getAllByRole("radio")).toHaveLength(SLIDES.length)
    expect(card("Card one")).toHaveAttribute("aria-checked", "true")
    expect(card("Card one")).toHaveAttribute("tabindex", "0")
    expect(card("Card three")).toHaveAttribute("aria-checked", "false")
    expect(card("Card three")).toHaveAttribute("tabindex", "-1")
    // The description is said once under the deck, and again with the card it
    // belongs to for anyone who never sees the deck.
    expect(screen.getAllByText("The first")).toHaveLength(2)
    expect(screen.getAllByText("The third")).toHaveLength(1)
  })

  it("answers with the card that was tapped", async () => {
    const user = userEvent.setup()
    const onChange = vi.fn()
    render(<Deck onChange={onChange} />)

    await user.click(card("Card three"))
    expect(onChange).toHaveBeenCalledExactlyOnceWith("three")
    expect(card("Card three")).toHaveAttribute("aria-checked", "true")
    expect(screen.getAllByText("The third")).toHaveLength(2)
    expect(screen.getAllByText("The first")).toHaveLength(1)

    // Tapping the card that is already the answer is not an answer.
    await user.click(card("Card three"))
    expect(onChange).toHaveBeenCalledOnce()
  })

  it("turns one card per arrow key, the short way round the ring", async () => {
    const user = userEvent.setup()
    const onChange = vi.fn()
    render(<Deck onChange={onChange} />)

    card("Card one").focus()
    await user.keyboard("{ArrowRight}")
    expect(onChange).toHaveBeenLastCalledWith("two")
    // Focus rides along: the answer is the card with the tab stop.
    expect(card("Card two")).toHaveFocus()

    await user.keyboard("{ArrowLeft}{ArrowLeft}")
    expect(onChange).toHaveBeenLastCalledWith("four")
    expect(card("Card four")).toHaveAttribute("aria-checked", "true")
  })

  it("answers as the deck passes each card, and settles where it is let go", () => {
    const onChange = vi.fn()
    render(<Deck onChange={onChange} />)
    const deck = screen.getByRole("radiogroup", { name: "Cards" })

    pointer(deck, "pointerdown", { clientX: 300, time: 0 })
    // Still a press: nothing has travelled far enough to be a drag yet.
    pointer(deck, "pointermove", { clientX: 297, time: 40 })
    expect(onChange).not.toHaveBeenCalled()

    // Far enough to be a drag, then most of a card to the left.
    pointer(deck, "pointermove", { clientX: 290, time: 80 })
    pointer(deck, "pointermove", { clientX: 290 - PITCH * 0.6, time: 180 })
    expect(onChange).toHaveBeenCalledExactlyOnceWith("two")

    // Let go without a flick: it stays on the card it is closest to.
    pointer(deck, "pointermove", { clientX: 290 - PITCH * 0.62, time: 400 })
    pointer(deck, "pointerup", { clientX: 290 - PITCH * 0.62, time: 420 })
    expect(onChange).toHaveBeenCalledOnce()
    expect(card("Card two")).toHaveAttribute("aria-checked", "true")
  })

  it("travels to a value set anywhere else without answering back", () => {
    const onChange = vi.fn()
    const { rerender } = render(
      <CoverflowCarousel
        label="Cards"
        onChange={onChange}
        slides={SLIDES}
        value="one"
      />
    )

    rerender(
      <CoverflowCarousel
        label="Cards"
        onChange={onChange}
        slides={SLIDES}
        value="four"
      />
    )

    expect(card("Card four")).toHaveAttribute("aria-checked", "true")
    expect(onChange).not.toHaveBeenCalled()
  })

  it("keeps every card reachable, not just the one facing you", () => {
    render(<Deck />)
    const deck = screen.getByRole("radiogroup", { name: "Cards" })

    // Nothing here has a layout, so this is the one invariant a test can hold:
    // every card but the middle one is pushed back in Z, and the plane they
    // stand on would take their taps if it answered to the pointer at all.
    expect(deck.firstElementChild).toHaveStyle({ pointerEvents: "none" })
    expect(card("Card three")).toHaveStyle({ pointerEvents: "auto" })
    // The shell's edge-swipe navigation stays out of a deck that reads its own
    // horizontal drag.
    expect(deck).toHaveAttribute("data-swipe-ignore")
  })
})
