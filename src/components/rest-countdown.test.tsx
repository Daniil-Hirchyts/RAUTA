import { act, render, screen } from "@testing-library/react"
import { afterEach, describe, expect, it, vi } from "vitest"

import { RestCountdown } from "@/components/rest-countdown"

afterEach(() => vi.useRealTimers())

/**
 * The rest between sets.
 *
 * What matters is the part somebody feels: it says how long is left, it ends
 * when the plan says it ends, and it is heard rather than watched — nobody
 * stares at a phone between sets.
 */
describe("resting between sets", () => {
  it("counts the plan's rest down and calls time on it", async () => {
    vi.useFakeTimers()
    const done = vi.fn()
    render(<RestCountdown onDone={done} seconds={90} />)

    expect(screen.getByRole("timer")).toHaveTextContent("1:30")
    await act(async () => {
      await vi.advanceTimersByTimeAsync(31_000)
    })
    expect(screen.getByRole("timer")).toHaveTextContent("0:59")

    await act(async () => {
      await vi.advanceTimersByTimeAsync(60_000)
    })
    expect(screen.getByRole("timer")).toHaveTextContent("0:00")
    expect(done).toHaveBeenCalledOnce()
  })

  it("keeps counting the same rest when the screen around it re-renders", async () => {
    vi.useFakeTimers()
    const done = vi.fn()
    const view = render(<RestCountdown onDone={done} seconds={60} />)
    await act(async () => {
      await vi.advanceTimersByTimeAsync(20_000)
    })

    view.rerender(<RestCountdown onDone={done} seconds={60} />)
    expect(screen.getByRole("timer")).toHaveTextContent("0:40")
    expect(done).not.toHaveBeenCalled()
  })
})
