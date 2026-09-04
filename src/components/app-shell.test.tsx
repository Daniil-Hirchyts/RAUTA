import { useRef } from "react"
import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import { AppShellHeader } from "@/components/app-shell"

function HeaderHarness() {
  const scrollRef = useRef<HTMLDivElement>(null)

  return (
    <div>
      <AppShellHeader scrollRef={scrollRef} title="Page title" />
      <div data-testid="scroller" ref={scrollRef} />
    </div>
  )
}

function setScrollMetrics(
  element: HTMLElement,
  { clientHeight, scrollHeight }: { clientHeight: number; scrollHeight: number }
) {
  Object.defineProperties(element, {
    clientHeight: { configurable: true, value: clientHeight },
    scrollHeight: { configurable: true, value: scrollHeight },
  })
}

describe("AppShellHeader", () => {
  it("hides while a scrollable page moves down and returns on scroll up", async () => {
    render(<HeaderHarness />)
    const header = screen.getByRole("banner")
    const scroller = screen.getByTestId("scroller")
    setScrollMetrics(scroller, { clientHeight: 400, scrollHeight: 1200 })

    scroller.scrollTop = 120
    fireEvent.scroll(scroller)
    await waitFor(() => expect(header).toHaveAttribute("data-hidden", "true"))

    scroller.scrollTop = 60
    fireEvent.scroll(scroller)
    await waitFor(() => expect(header).not.toHaveAttribute("data-hidden"))
  })

  it("ignores a scroll too short to read as a deliberate one", async () => {
    render(<HeaderHarness />)
    const header = screen.getByRole("banner")
    const scroller = screen.getByTestId("scroller")
    setScrollMetrics(scroller, { clientHeight: 400, scrollHeight: 1200 })

    scroller.scrollTop = 40
    fireEvent.scroll(scroller)
    await waitFor(() => expect(header).not.toHaveAttribute("data-hidden"))
  })

  it("stays visible when the page cannot scroll", async () => {
    render(<HeaderHarness />)
    const header = screen.getByRole("banner")
    const scroller = screen.getByTestId("scroller")
    setScrollMetrics(scroller, { clientHeight: 100, scrollHeight: 100 })

    scroller.scrollTop = 40
    fireEvent.scroll(scroller)
    await waitFor(() => expect(header).not.toHaveAttribute("data-hidden"))
  })

  it("supports multiline titles and adapts size based on length", () => {
    const { rerender } = render(
      <AppShellHeader title="Short title" titleMultiline />
    )
    const heading = screen.getByRole("heading", { name: "Short title" })
    expect(heading).toHaveAttribute("data-multiline", "true")
    expect(heading).not.toHaveAttribute("data-size")

    rerender(
      <AppShellHeader title="Barbell Bent Arm Pullover" titleMultiline />
    )
    const mdHeading = screen.getByRole("heading", {
      name: "Barbell Bent Arm Pullover",
    })
    expect(mdHeading).toHaveAttribute("data-multiline", "true")
    expect(mdHeading).toHaveAttribute("data-size", "md")

    rerender(
      <AppShellHeader
        title="Vertical Leg Raise (On Parallel Bars)"
        titleMultiline
      />
    )
    const smHeading = screen.getByRole("heading", {
      name: "Vertical Leg Raise (On Parallel Bars)",
    })
    expect(smHeading).toHaveAttribute("data-multiline", "true")
    expect(smHeading).toHaveAttribute("data-size", "sm")

    rerender(
      <AppShellHeader
        title="Assisted Seated Pectoralis Major Stretch With Stability Ball"
        titleMultiline
      />
    )
    const xsHeading = screen.getByRole("heading", {
      name: "Assisted Seated Pectoralis Major Stretch With Stability Ball",
    })
    expect(xsHeading).toHaveAttribute("data-multiline", "true")
    expect(xsHeading).toHaveAttribute("data-size", "xs")
  })

  it("renders subtitle with proper styling without affecting title structure", () => {
    const { rerender } = render(<AppShellHeader title="Muscles" />)
    const heading = screen.getByRole("heading", { name: "Muscles" })
    expect(heading).toBeInTheDocument()
    expect(screen.queryByTestId("stage-subtitle")).toBeNull()

    rerender(
      <AppShellHeader
        subtitle={<span key="count">2 selected</span>}
        title="Muscles"
      />
    )

    expect(screen.getByRole("heading", { name: "Muscles" })).toBe(heading)
    const subtitle = screen.getByTestId("stage-subtitle")
    expect(subtitle).toBeInTheDocument()
    expect(subtitle).toHaveClass("app-shell-header-subtitle")
    expect(subtitle).toHaveTextContent("2 selected")
  })
})
