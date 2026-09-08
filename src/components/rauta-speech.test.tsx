import { act, fireEvent, render, screen } from "@testing-library/react"
import { afterEach, describe, expect, it, vi } from "vitest"
import { Rauta } from "./rauta"

vi.mock("./rauta-runtime", () => ({
  default: ({
    label,
    onActivate,
  }: {
    label?: string
    onActivate?: () => void
  }) => <button aria-label={label} onClick={onActivate} type="button" />,
}))

afterEach(() => vi.useRealTimers())

/** A page inside the shell, with the character in its scrolling content. */
function shell() {
  const view = render(
    <div className="app-shell-frame">
      <div className="app-surface" />
      <div className="app-screen">
        <div className="app-scroll-region">
          <Rauta speech="Ready when you are." />
        </div>
      </div>
    </div>
  )
  const frame = view.container.querySelector<HTMLElement>(".app-shell-frame")!
  const surface = view.container.querySelector<HTMLElement>(".app-surface")!
  const scroller = view.container.querySelector<HTMLElement>(
    ".app-scroll-region"
  )!
  const anchor = scroller.firstElementChild as HTMLElement
  box(frame, { left: 0, top: 0, width: 390, height: 844 })
  box(surface, { left: 4, top: 4, width: 382, height: 744 })
  // jsdom lays nothing out, so the slot reports where it would really be: a
  // fixed place in the page, moving up as the page is scrolled.
  anchor.getBoundingClientRect = () =>
    ({ left: 20, top: 280 - scroller.scrollTop, width: 104, height: 104 }) as DOMRect
  return { anchor, scroller }
}

function box(
  node: HTMLElement,
  rect: { left: number; top: number; width: number; height: number }
) {
  node.getBoundingClientRect = () =>
    ({
      ...rect,
      right: rect.left + rect.width,
      bottom: rect.top + rect.height,
    }) as DOMRect
}

function character() {
  return document.querySelector<HTMLElement>("[data-rauta-character]")!
}

describe("RAUTA's place on the page", () => {
  it("keeps its place on the screen while the page scrolls under it", () => {
    const { scroller } = shell()
    act(() => {
      window.dispatchEvent(new Event("resize"))
    })
    const before = character().style.top

    scroller.scrollTop = 240
    act(() => {
      scroller.dispatchEvent(new Event("scroll", { bubbles: true }))
      // Even a re-measure caused by something else finds it in the same place.
      window.dispatchEvent(new Event("resize"))
    })

    expect(character().style.top).toBe(before)
  })
})

describe("RAUTA speech", () => {
  it("dismisses guidance after reading time and repeats it on demand", async () => {
    vi.useFakeTimers()
    render(<Rauta speech="Pick the days you can train." />)
    await act(async () => {
      await vi.advanceTimersByTimeAsync(400)
    })
    expect(screen.getByRole("status")).toHaveTextContent("Pick the days")
    await act(async () => {
      await vi.advanceTimersByTimeAsync(5500)
    })
    await act(async () => {
      await vi.advanceTimersByTimeAsync(500)
    })
    expect(screen.queryByRole("status")).toBeNull()
    fireEvent.click(screen.getByRole("button", { name: "Interact with RAUTA" }))
    expect(screen.getByRole("status")).toHaveTextContent("Pick the days")
  })

  it("answers a changed setting with new guidance", async () => {
    vi.useFakeTimers()
    const view = render(<Rauta speech="Build muscle." />)
    await act(async () => {
      await vi.advanceTimersByTimeAsync(6000)
    })
    view.rerender(<Rauta speech="Get stronger." />)
    await act(async () => {
      await vi.advanceTimersByTimeAsync(400)
    })
    expect(screen.getByRole("status")).toHaveTextContent("Get stronger.")
  })
})
