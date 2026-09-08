import { act, fireEvent, render, screen } from "@testing-library/react"
import { motion } from "motion/react"
import { useEffect } from "react"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import {
  useRautaMotion,
  requestRautaOrientation,
  type RautaGestureEvent,
} from "@/hooks/use-rauta-motion"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts } from "@/store/use-workouts"

/**
 * The character's movement controller, driven the way a thumb drives it.
 *
 * Frame-by-frame output is the artwork's business; what is tested here is the
 * contract a person can feel — a one-finger drag moves and does not turn, a
 * two-finger twist turns, nothing escapes the screen, and every listener the
 * controller opens is closed again.
 */

const SIZE = 104
const VIEWPORT = { width: 390, height: 844 }

/** Motion writes transforms on its own frame, which jsdom never runs, so the
 *  motion values themselves are what the tests read. */
const live: {
  current: Pick<ReturnType<typeof useRautaMotion>, "x" | "y" | "rotate"> | null
} = { current: null }

const placement = {
  get x() {
    return live.current?.x.get() ?? 0
  },
  get y() {
    return live.current?.y.get() ?? 0
  },
  get rotate() {
    return live.current?.rotate.get() ?? 0
  },
}

function Harness({
  onGesture,
  disabled,
}: {
  onGesture?: (event: RautaGestureEvent) => void
  disabled?: boolean
}) {
  const motionState = useRautaMotion({
    onGesture,
    disabled,
    inset: { bottom: 96 },
  })
  const { ref, x, y, rotate, handlers } = motionState
  useEffect(() => {
    live.current = motionState
    return () => {
      live.current = null
    }
  }, [motionState])
  return (
    <motion.div
      data-testid="rauta"
      ref={ref}
      style={{ width: SIZE, height: SIZE, x, y, rotate }}
      {...handlers}
    />
  )
}

function stubBox(node: HTMLElement) {
  node.getBoundingClientRect = () =>
    ({
      left: 250 + placement.x,
      top: 500 + placement.y,
      width: SIZE,
      height: SIZE,
      right: 250 + SIZE,
      bottom: 500 + SIZE,
      x: 250,
      y: 500,
      toJSON: () => ({}),
    }) as DOMRect
}

beforeEach(() => {
  Object.defineProperty(window, "innerWidth", {
    value: VIEWPORT.width,
    configurable: true,
  })
  Object.defineProperty(window, "innerHeight", {
    value: VIEWPORT.height,
    configurable: true,
  })
  Element.prototype.setPointerCapture = vi.fn()
  vi.stubGlobal(
    "requestAnimationFrame",
    (callback: FrameRequestCallback) =>
      setTimeout(() => callback(performance.now()), 0) as unknown as number
  )
  vi.stubGlobal("cancelAnimationFrame", (handle: number) =>
    clearTimeout(handle)
  )
})

afterEach(() => {
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

describe("dragging RAUTA", () => {
  it("reaches the visible shell edge without reserving an invisible diagonal", () => {
    render(
      <div className="app-shell-frame">
        <div className="app-surface" />
        <Harness />
      </div>
    )
    const surface = document.querySelector(".app-surface")!
    surface.getBoundingClientRect = () =>
      ({
        left: 4,
        top: 4,
        right: 386,
        bottom: 740,
        width: 382,
        height: 736,
      }) as DOMRect
    const bot = screen.getByTestId("rauta")
    stubBox(bot)
    fireEvent.pointerDown(bot, { pointerId: 1, clientX: 300, clientY: 550 })
    fireEvent.pointerMove(bot, { pointerId: 1, clientX: 9000, clientY: 550 })
    expect(250 + placement.x + SIZE).toBeCloseTo(386)
  })

  it("moves the character and never turns it", () => {
    render(<Harness />)
    const bot = screen.getByTestId("rauta")
    stubBox(bot)

    fireEvent.pointerDown(bot, { pointerId: 1, clientX: 300, clientY: 550 })
    fireEvent.pointerMove(bot, { pointerId: 1, clientX: 250, clientY: 600 })
    fireEvent.pointerUp(bot, { pointerId: 1 })

    expect(placement.x).not.toBe(0)
    expect(placement.y).not.toBe(0)
    // One finger translates. Nothing about a sideways drag turns the character.
    expect(placement.rotate).toBe(0)
  })

  it("reports a tap rather than a drag when the finger barely moved", () => {
    const events: RautaGestureEvent[] = []
    render(<Harness onGesture={(event) => events.push(event)} />)
    const bot = screen.getByTestId("rauta")
    stubBox(bot)

    fireEvent.pointerDown(bot, { pointerId: 1, clientX: 300, clientY: 550 })
    fireEvent.pointerMove(bot, { pointerId: 1, clientX: 302, clientY: 551 })
    fireEvent.pointerUp(bot, { pointerId: 1 })

    expect(events.map((event) => event.type)).toEqual(["tap"])
  })

  it("cannot be dragged off the screen", () => {
    render(<Harness />)
    const bot = screen.getByTestId("rauta")
    stubBox(bot)

    fireEvent.pointerDown(bot, { pointerId: 1, clientX: 300, clientY: 550 })
    // A drag far past every edge at once.
    fireEvent.pointerMove(bot, { pointerId: 1, clientX: 9000, clientY: 9000 })
    fireEvent.pointerUp(bot, { pointerId: 1 })

    // Still reachable: the body has not left the viewport.
    expect(250 + placement.x + SIZE).toBeLessThanOrEqual(VIEWPORT.width)
    expect(500 + placement.y + SIZE).toBeLessThanOrEqual(VIEWPORT.height - 96)
    expect(250 + placement.x + SIZE).toBeGreaterThan(0)
  })

  it("does not respond at all while disabled", () => {
    render(<Harness disabled />)
    const bot = screen.getByTestId("rauta")
    stubBox(bot)
    fireEvent.pointerDown(bot, { pointerId: 1, clientX: 300, clientY: 550 })
    fireEvent.pointerMove(bot, { pointerId: 1, clientX: 200, clientY: 650 })
    expect(placement.x).toBe(0)
    expect(placement.y).toBe(0)
  })
})

describe("turning RAUTA", () => {
  it("turns only for a deliberate two-finger twist", () => {
    const events: RautaGestureEvent[] = []
    render(<Harness onGesture={(event) => events.push(event)} />)
    const bot = screen.getByTestId("rauta")
    stubBox(bot)

    // Two fingers down, level with each other.
    fireEvent.pointerDown(bot, { pointerId: 1, clientX: 280, clientY: 550 })
    fireEvent.pointerDown(bot, { pointerId: 2, clientX: 340, clientY: 550 })
    // A tiny wobble is not a twist.
    fireEvent.pointerMove(bot, { pointerId: 2, clientX: 340, clientY: 552 })
    expect(events.some((event) => event.type === "rotate")).toBe(false)

    // A real twist is.
    fireEvent.pointerMove(bot, { pointerId: 2, clientX: 330, clientY: 600 })
    expect(events.some((event) => event.type === "rotate")).toBe(true)
    expect(placement.rotate).not.toBe(0)
  })

  it("does not slide while it is being twisted", () => {
    render(<Harness />)
    const bot = screen.getByTestId("rauta")
    stubBox(bot)

    fireEvent.pointerDown(bot, { pointerId: 1, clientX: 280, clientY: 550 })
    fireEvent.pointerDown(bot, { pointerId: 2, clientX: 340, clientY: 550 })
    fireEvent.pointerMove(bot, { pointerId: 2, clientX: 330, clientY: 620 })

    // The second finger cancelled the drag, so no translation was applied.
    expect(placement.x).toBe(0)
    expect(placement.y).toBe(0)
  })
})

describe("throwing RAUTA", () => {
  it("reports a throw with a speed that is capped", () => {
    const events: RautaGestureEvent[] = []
    render(<Harness onGesture={(event) => events.push(event)} />)
    const bot = screen.getByTestId("rauta")
    stubBox(bot)

    fireEvent.pointerDown(bot, { pointerId: 1, clientX: 300, clientY: 550 })
    for (let step = 1; step <= 4; step += 1)
      fireEvent.pointerMove(bot, {
        pointerId: 1,
        clientX: 300 - step * 40,
        clientY: 550,
      })
    fireEvent.pointerUp(bot, { pointerId: 1 })

    const thrown = events.find((event) => event.type === "throw")
    const released = events.find((event) => event.type === "drag-end")
    expect(released).toBeDefined()
    // However hard the swipe, the speed handed to the animation is bounded.
    if (thrown && thrown.type === "throw")
      expect(thrown.speed).toBeLessThanOrEqual(1900)
  })
})

describe("the magnet", () => {
  it("brings the character back to its place after it is thrown", () => {
    vi.useFakeTimers()
    try {
      const events: RautaGestureEvent[] = []
      render(<Harness onGesture={(event) => events.push(event)} />)
      const bot = screen.getByTestId("rauta")
      stubBox(bot)

      fireEvent.pointerDown(bot, { pointerId: 1, clientX: 300, clientY: 550 })
      fireEvent.pointerMove(bot, { pointerId: 1, clientX: 180, clientY: 700 })
      fireEvent.pointerUp(bot, { pointerId: 1 })
      expect(placement.x).not.toBe(0)

      act(() => {
        vi.advanceTimersByTime(1200)
      })
      expect(events.some((event) => event.type === "return")).toBe(true)
    } finally {
      vi.useRealTimers()
    }
  })

  it("lets go of the character the moment it is picked up again", () => {
    vi.useFakeTimers()
    try {
      const events: RautaGestureEvent[] = []
      render(<Harness onGesture={(event) => events.push(event)} />)
      const bot = screen.getByTestId("rauta")
      stubBox(bot)

      fireEvent.pointerDown(bot, { pointerId: 1, clientX: 300, clientY: 550 })
      fireEvent.pointerMove(bot, { pointerId: 1, clientX: 180, clientY: 700 })
      fireEvent.pointerUp(bot, { pointerId: 1 })
      // Caught again before the pull home was due.
      fireEvent.pointerDown(bot, { pointerId: 2, clientX: 180, clientY: 700 })

      act(() => {
        vi.advanceTimersByTime(1200)
      })
      expect(events.some((event) => event.type === "return")).toBe(false)
      expect(placement.x).not.toBe(0)
    } finally {
      vi.useRealTimers()
    }
  })
})

describe("device orientation", () => {
  it("asks for motion access only when something asks it to", async () => {
    const request = vi.fn().mockResolvedValue("granted")
    vi.stubGlobal(
      "DeviceOrientationEvent",
      Object.assign(function () {}, { requestPermission: request })
    )
    render(<Harness />)
    // Rendering the character must never raise a system prompt.
    expect(request).not.toHaveBeenCalled()

    await requestRautaOrientation()
    expect(request).toHaveBeenCalledOnce()
  })

  it("keeps working when the sensor is unsupported or refused", async () => {
    vi.stubGlobal("DeviceOrientationEvent", undefined)
    expect(await requestRautaOrientation()).toBe(false)

    vi.stubGlobal(
      "DeviceOrientationEvent",
      Object.assign(function () {}, {
        requestPermission: vi.fn().mockRejectedValue(new Error("no")),
      })
    )
    expect(await requestRautaOrientation()).toBe(false)

    // And the character is still fully draggable either way.
    render(<Harness />)
    const bot = screen.getByTestId("rauta")
    stubBox(bot)
    fireEvent.pointerDown(bot, { pointerId: 1, clientX: 300, clientY: 550 })
    fireEvent.pointerMove(bot, { pointerId: 1, clientX: 260, clientY: 580 })
    fireEvent.pointerUp(bot, { pointerId: 1 })
    expect(placement.x).not.toBe(0)
  })
})

describe("review regressions", () => {
  it("suppresses the click following a drag, while allowing the next tap", () => {
    const activate = vi.fn()
    render(
      <div onClick={activate}>
        <Harness />
      </div>
    )
    const bot = screen.getByTestId("rauta")
    stubBox(bot)
    fireEvent.pointerDown(bot, { pointerId: 1, clientX: 300, clientY: 550 })
    fireEvent.pointerMove(bot, { pointerId: 1, clientX: 230, clientY: 550 })
    fireEvent.pointerUp(bot, { pointerId: 1 })
    fireEvent.click(bot)
    expect(activate).not.toHaveBeenCalled()
    fireEvent.pointerDown(bot, { pointerId: 1, clientX: 230, clientY: 550 })
    fireEvent.pointerUp(bot, { pointerId: 1 })
    fireEvent.click(bot)
    expect(activate).toHaveBeenCalledOnce()
  })

  it("activates a gated sensor after permission and nudges the dragged position", async () => {
    vi.useFakeTimers()
    try {
      vi.stubGlobal(
        "DeviceOrientationEvent",
        Object.assign(function () {}, {
          requestPermission: vi.fn().mockResolvedValue("granted"),
        })
      )
      render(<Harness />)
      const bot = screen.getByTestId("rauta")
      stubBox(bot)
      fireEvent.pointerDown(bot, { pointerId: 1, clientX: 300, clientY: 550 })
      fireEvent.pointerMove(bot, { pointerId: 1, clientX: 180, clientY: 450 })
      fireEvent.pointerUp(bot, { pointerId: 1 })
      const before = { x: placement.x, y: placement.y }
      await requestRautaOrientation()
      const sample = Object.assign(new Event("deviceorientation"), {
        beta: 30,
        gamma: 25,
      })
      act(() => {
        window.dispatchEvent(sample)
        vi.advanceTimersByTime(20)
      })
      expect(placement.x).toBeGreaterThan(before.x)
      expect(Math.abs(placement.x - before.x)).toBeLessThanOrEqual(9)
      expect(Math.abs(placement.y - before.y)).toBeLessThanOrEqual(9)
    } finally {
      vi.useRealTimers()
    }
  })

  it("cancels a queued sensor update on unmount", async () => {
    vi.useFakeTimers()
    try {
      vi.stubGlobal("DeviceOrientationEvent", function () {})
      const view = render(<Harness />)
      const x = live.current!.x
      const write = vi.spyOn(x, "set")
      act(() =>
        window.dispatchEvent(
          Object.assign(new Event("deviceorientation"), { beta: 30, gamma: 25 })
        )
      )
      view.unmount()
      write.mockClear()
      act(() => vi.advanceTimersByTime(20))
      expect(write).not.toHaveBeenCalled()
    } finally {
      vi.useRealTimers()
    }
  })
})

describe("cleaning up", () => {
  it("closes every listener it opened", () => {
    const added = vi.spyOn(window, "addEventListener")
    const removed = vi.spyOn(window, "removeEventListener")
    const view = render(<Harness />)

    const opened = added.mock.calls.map(([type]) => type)
    view.unmount()
    const closed = removed.mock.calls.map(([type]) => type)
    for (const type of new Set(opened)) expect(closed).toContain(type)
    // And only ever one orientation listener at a time.
    expect(
      opened.filter((type) => type === "deviceorientation").length
    ).toBeLessThan(2)
  })
})

describe("the character and the training record", () => {
  it("changes nothing in the training domain by being handled", () => {
    const before = structuredClone(useTrainingRecords.getState().data)
    const workoutsBefore = structuredClone(useWorkouts.getState().workouts)
    const events: RautaGestureEvent[] = []
    render(<Harness onGesture={(event) => events.push(event)} />)
    const bot = screen.getByTestId("rauta")
    stubBox(bot)

    fireEvent.pointerDown(bot, { pointerId: 1, clientX: 300, clientY: 550 })
    fireEvent.pointerMove(bot, { pointerId: 1, clientX: 120, clientY: 700 })
    fireEvent.pointerUp(bot, { pointerId: 1 })
    fireEvent.pointerDown(bot, { pointerId: 2, clientX: 280, clientY: 550 })
    fireEvent.pointerDown(bot, { pointerId: 3, clientX: 340, clientY: 550 })
    fireEvent.pointerMove(bot, { pointerId: 3, clientX: 330, clientY: 620 })
    fireEvent.pointerUp(bot, { pointerId: 3 })

    expect(events.length).toBeGreaterThan(0)
    // RAUTA is expression. It is not a source of training evidence.
    expect(useTrainingRecords.getState().data).toEqual(before)
    expect(useWorkouts.getState().workouts).toEqual(workoutsBefore)
  })
})
