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

/** A page inside the shell, with the character written into its scrolling
 *  content — which is not where it ends up standing. `floor` is a band the
 *  page keeps at its own foot: a timer, a row of presets. */
function shell({ floor = 0 } = {}) {
  const view = render(
    <div className="app-shell-frame">
      <div className="app-surface" />
      <div className="app-screen">
        <div className="app-scroll-region">
          <Rauta speech="Ready when you are." />
        </div>
        {floor ? <div data-rauta-floor /> : null}
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
  box(surface, { left: 4, top: 4, width: 382, height: 742 })
  // jsdom lays nothing out, so the surface reports the inside of itself: the
  // box an absolutely positioned character is placed in.
  for (const [name, value] of [
    ["clientLeft", 0],
    ["clientTop", 0],
    ["clientWidth", 382],
    ["clientHeight", 742],
  ] as const)
    Object.defineProperty(surface, name, { configurable: true, value })
  const band = view.container.querySelector<HTMLElement>("[data-rauta-floor]")
  if (band)
    box(band, { left: 4, top: 4 + 742 - floor, width: 382, height: floor })
  // The slot the character was written into is a long way down the page, and
  // travels up as the page is scrolled.
  anchor.getBoundingClientRect = () =>
    ({
      left: 20,
      top: 280 - scroller.scrollTop,
      width: 104,
      height: 104,
    }) as DOMRect
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

/** Where the character is, read back off the transform it is placed with. */
function offset() {
  const transform = character().style.transform
  const read = (axis: string) =>
    Number(
      new RegExp(`translate${axis}\\((-?[\\d.]+)px\\)`).exec(transform)?.[1] ??
        0
    )
  return { x: read("X"), y: read("Y") }
}

/** Position is written to the element on the next frame, never during a
 *  render, so a reading is taken once that frame has run. */
function painted() {
  return new Promise((resolve) => requestAnimationFrame(resolve))
}

describe("RAUTA's place on the page", () => {
  it("stands at the foot of the screen, not in the slot it was written in", async () => {
    shell()
    await act(async () => {
      window.dispatchEvent(new Event("resize"))
      await painted()
    })

    // Written into the page 280px down; standing on the floor of the surface.
    expect(offset().y).toBeGreaterThan(600)
  })

  it("takes no room in the page it was written into", async () => {
    const { anchor } = shell()
    await act(async () => {
      window.dispatchEvent(new Event("resize"))
      await painted()
    })

    // The row it sits in closes up around it: nothing is reserved for a
    // character that is not standing there.
    expect(anchor.style.width).toBe("")
    expect(anchor.style.height).toBe("")
    expect(anchor.className).toContain("hidden")
  })

  it("stands on the band a page keeps at its own foot", async () => {
    shell({ floor: 140 })
    await act(async () => {
      window.dispatchEvent(new Event("resize"))
      await painted()
    })

    // On top of the band rather than in front of it.
    expect(offset().y).toBeCloseTo(742 - 140 - 104, 0)
  })

  it("keeps that place while the page scrolls behind it", async () => {
    const { scroller } = shell()
    await act(async () => {
      window.dispatchEvent(new Event("resize"))
      await painted()
    })
    const before = offset()

    scroller.scrollTop = 240
    await act(async () => {
      scroller.dispatchEvent(new Event("scroll", { bubbles: true }))
      await painted()
    })

    expect(offset()).toEqual(before)
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

  it("hands its lines to a screen that speaks for it, and floats no bubble", async () => {
    vi.useFakeTimers()
    const lines: (string | null)[] = []
    render(
      <Rauta
        speech="Pick the days you can train."
        onSay={(line) => lines.push(line)}
      />
    )
    await act(async () => {
      await vi.advanceTimersByTimeAsync(400)
    })

    expect(lines.at(-1)).toBe("Pick the days you can train.")
    // One voice: the panel is saying it, so nothing floats over the page.
    expect(screen.queryByRole("status")).toBeNull()

    await act(async () => {
      await vi.advanceTimersByTimeAsync(5000)
    })
    // And told when the line is over, so the panel can go back to its own.
    expect(lines.at(-1)).toBeNull()
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
