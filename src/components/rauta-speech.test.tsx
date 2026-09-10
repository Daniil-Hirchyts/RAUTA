import { act, fireEvent, render, screen } from "@testing-library/react"
import type { ComponentProps, ReactNode } from "react"
import { afterEach, describe, expect, it, vi } from "vitest"
import { cueRauta } from "@/lib/rauta-cues"
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
function shell({
  floor = 0,
  ...props
}: { floor?: number } & ComponentProps<typeof Rauta> = {}) {
  const page = (rauta: ReactNode) => (
    <div className="app-shell-frame">
      <div className="app-surface" />
      <div className="app-screen">
        <div className="app-scroll-region">{rauta}</div>
        {floor ? <div data-rauta-floor /> : null}
      </div>
    </div>
  )
  const view = render(page(<Rauta speech="Ready when you are." {...props} />))
  const frame = view.container.querySelector<HTMLElement>(".app-shell-frame")!
  const surface = view.container.querySelector<HTMLElement>(".app-surface")!
  const scroller =
    view.container.querySelector<HTMLElement>(".app-scroll-region")!
  const anchor = scroller.querySelector<HTMLElement>("[data-rauta-slot]")!
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
  const show = (next: ComponentProps<typeof Rauta>) =>
    view.rerender(page(<Rauta speech="Ready when you are." {...next} />))
  return { anchor, scroller, show, view }
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

    // On top of the band rather than in front of it, and lifted clear of it
    // by the few pixels the character floats above whatever it stands on.
    expect(offset().y).toBeCloseTo(742 - 140 - 104 - 8, 0)
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

describe("what RAUTA says", () => {
  it("keeps the screen's line up, and follows it when the screen changes it", () => {
    const { show } = shell()
    expect(screen.getByRole("status")).toHaveTextContent("Ready when you are.")

    show({ speech: "Pick the days you can train." })
    expect(screen.getByRole("status")).toHaveTextContent("Pick the days")
  })

  it("says its own remark over the top of it, then gives the line back", async () => {
    vi.useFakeTimers()
    const { anchor } = shell()
    const bot = character()
    // Carried across the screen and let go: worth a word, and only a word.
    fireEvent.pointerDown(bot, { pointerId: 1, clientX: 40, clientY: 640 })
    fireEvent.pointerMove(bot, { pointerId: 1, clientX: 180, clientY: 500 })
    fireEvent.pointerUp(bot, { pointerId: 1 })
    expect(screen.getByRole("status")).toHaveTextContent("Back to my post.")

    await act(async () => {
      await vi.advanceTimersByTimeAsync(3000)
    })
    expect(screen.getByRole("status")).toHaveTextContent("Ready when you are.")
    expect(anchor.className).toContain("hidden")
  })

  it("answers meaningful workout actions without replacing the standing line", async () => {
    vi.useFakeTimers()
    shell()

    act(() => cueRauta("workout-paused"))
    expect(screen.getByRole("status")).toHaveTextContent(/paused|hold|break/i)

    await act(async () => {
      await vi.advanceTimersByTimeAsync(3000)
    })
    expect(screen.getByRole("status")).toHaveTextContent("Ready when you are.")
  })

  it("treats a passing line as a remark rather than as the state of the screen", async () => {
    vi.useFakeTimers()
    const { show } = shell({
      speech: "Log the first set when it's done.",
      transient: true,
    })
    expect(screen.getByRole("status")).toHaveTextContent("Log the first set")

    // It is said once and it is over — a screen being worked on gets its
    // screen back rather than keeping a panel over the set being logged.
    // (What is left behind here is the panel on its way out: the exit is an
    // animation, and there are no frames to run it in.)
    await act(async () => {
      await vi.advanceTimersByTimeAsync(3000)
    })
    show({ speech: "Two sets in. Keep the pace.", transient: true })
    expect(screen.getByRole("status")).toHaveTextContent("Two sets in")
  })

  it("is not there at all when there is nothing to say", () => {
    shell({ speech: undefined })

    expect(screen.queryByRole("status")).toBeNull()
  })

  it("grows to hold what it offers, instead of opening a window over the page", () => {
    const chosen = vi.fn()
    shell({
      actions: [{ label: "Choose exercises", onSelect: chosen }],
      label: "Open RAUTA actions",
    })
    expect(
      screen.queryByRole("button", { name: "Choose exercises" })
    ).toBeNull()

    fireEvent.click(screen.getByRole("button", { name: "RAUTA actions" }))
    fireEvent.click(screen.getByRole("button", { name: "Choose exercises" }))
    expect(chosen).toHaveBeenCalledOnce()
    // No dialog: the panel it was already speaking from is where this happens.
    expect(screen.queryByRole("dialog")).toBeNull()
  })
})
