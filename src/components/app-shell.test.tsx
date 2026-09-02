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
    setScrollMetrics(scroller, { clientHeight: 100, scrollHeight: 300 })

    scroller.scrollTop = 40
    fireEvent.scroll(scroller)
    await waitFor(() => expect(header).toHaveAttribute("data-hidden", "true"))

    scroller.scrollTop = 20
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
})
