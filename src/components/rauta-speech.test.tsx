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
