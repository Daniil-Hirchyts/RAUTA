import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import RautaRuntime from "./rauta-runtime"
import { WorkoutCompanion } from "./workout-companion"

const sdk = vi.hoisted(() => {
  const inputs = Object.fromEntries(
    [
      "status",
      "intensity",
      "facing",
      "gazeX",
      "gazeY",
      "pressed",
      "tapped",
      "acknowledge",
    ].map((name) => [name, { value: 0 as number | boolean, fire: vi.fn() }])
  )
  return { inputs, rive: { pause: vi.fn(), play: vi.fn() } }
})
vi.mock("@rive-app/react-canvas", () => ({
  RuntimeLoader: { setWasmUrl: vi.fn() },
  Layout: class {},
  Fit: { Contain: "contain" },
  Alignment: { Center: "center" },
  useRive: () => ({ rive: sdk.rive, RiveComponent: () => null }),
  useStateMachineInput: (_rive: unknown, _machine: string, name: string) =>
    sdk.inputs[name],
}))

describe("RAUTA interaction boundary", () => {
  it("maps moods and keyboard activation to real rig inputs", () => {
    const activate = vi.fn()
    const view = render(
      <RautaRuntime mood="focused" label="Bot" onActivate={activate} />
    )
    expect(sdk.inputs.status.value).toBe(7)
    fireEvent.click(screen.getByRole("button", { name: "Bot" }))
    expect(sdk.inputs.tapped.fire).toHaveBeenCalledOnce()
    expect(activate).toHaveBeenCalledOnce()
    view.rerender(
      <RautaRuntime mood="happy" label="Bot" onActivate={activate} />
    )
    expect(sdk.inputs.status.value).toBe(9)
  })

  it("turns without launching an action and cancels touch without activation", () => {
    const activate = vi.fn()
    render(<RautaRuntime label="Bot" onActivate={activate} />)
    const bot = screen.getByRole("button", { name: "Bot" })
    fireEvent.pointerDown(bot, { button: 0, pointerId: 1, clientX: 30 })
    fireEvent.pointerMove(bot, { pointerId: 1, clientX: 100 })
    fireEvent.pointerUp(bot, { pointerId: 1 })
    fireEvent.click(bot)
    expect(Number(sdk.inputs.facing.value)).toBeGreaterThan(0)
    expect(activate).not.toHaveBeenCalled()
    fireEvent.pointerDown(bot, { button: 0, pointerId: 2, clientX: 30 })
    fireEvent.pointerCancel(bot, { pointerId: 2 })
    fireEvent.click(bot)
    expect(activate).not.toHaveBeenCalled()
    expect(sdk.inputs.pressed.value).toBe(false)
  })

  it("routes explicit bot actions through existing workout and settings callbacks", () => {
    const create = vi.fn(),
      settings = vi.fn(),
      resume = vi.fn()
    render(
      <WorkoutCompanion
        onCreate={create}
        onSettings={settings}
        onResume={resume}
      />
    )
    fireEvent.click(
      screen.getByRole("button", { name: "Train with RAUTA" })
    )
    expect(create).not.toHaveBeenCalled()
    fireEvent.click(screen.getByRole("button", { name: "Resume workout" }))
    expect(resume).toHaveBeenCalledOnce()
    fireEvent.click(
      screen.getByRole("button", { name: "Train with RAUTA" })
    )
    fireEvent.click(screen.getByRole("button", { name: "Choose exercises" }))
    expect(create).toHaveBeenCalledOnce()
    fireEvent.click(
      screen.getByRole("button", { name: "Train with RAUTA" })
    )
    fireEvent.click(screen.getByRole("button", { name: "My preferences" }))
    expect(settings).toHaveBeenCalledOnce()
  })
})
