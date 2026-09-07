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
      "surprise",
      "celebrate",
      "frustrated",
      "relieved",
      "wobble",
      "gearUp",
      "laugh",
      "recoil",
      "peek",
      "blink",
      "blinkDouble",
      "wink",
      "spinLeft",
      "spinRight",
      "turnaround",
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
    expect(activate).toHaveBeenCalledOnce()
    view.rerender(
      <RautaRuntime mood="happy" label="Bot" onActivate={activate} />
    )
    expect(sdk.inputs.status.value).toBe(9)
    // Every mood in the vocabulary is a state the artwork really has.
    view.rerender(
      <RautaRuntime mood="skeptical" label="Bot" onActivate={activate} />
    )
    expect(sdk.inputs.status.value).toBe(12)
  })

  it("plays a requested reaction through the rig trigger it names", () => {
    const view = render(<RautaRuntime label="Bot" ambient={false} />)
    view.rerender(
      <RautaRuntime
        label="Bot"
        ambient={false}
        request={{ reaction: "celebrate", source: "explicit", nonce: 1 }}
      />
    )
    expect(sdk.inputs.celebrate.fire).toHaveBeenCalledOnce()

    // An ambient thought cannot talk over what the engine just said.
    view.rerender(
      <RautaRuntime
        label="Bot"
        ambient={false}
        request={{ reaction: "blink", source: "ambient", nonce: 2 }}
      />
    )
    expect(sdk.inputs.blink.fire).not.toHaveBeenCalled()
  })

  it("does not turn the character because a finger moved across it", () => {
    const activate = vi.fn()
    render(<RautaRuntime label="Bot" onActivate={activate} />)
    const bot = screen.getByRole("button", { name: "Bot" })
    const facing = Number(sdk.inputs.facing.value)

    fireEvent.pointerDown(bot, { button: 0, pointerId: 1, clientX: 30 })
    fireEvent.pointerMove(bot, { pointerId: 1, clientX: 100 })
    fireEvent.pointerUp(bot, { pointerId: 1 })

    // Dragging moves RAUTA; turning it is a two-finger twist and nothing else.
    expect(Number(sdk.inputs.facing.value)).toBe(facing)
  })

  it("routes explicit bot actions through existing workout and settings callbacks", () => {
    const create = vi.fn(),
      plan = vi.fn(),
      settings = vi.fn(),
      resume = vi.fn()
    render(
      <WorkoutCompanion
        onCreate={create}
        onCreatePlan={plan}
        onSettings={settings}
        onResume={resume}
      />
    )
    fireEvent.click(screen.getByRole("button", { name: "Train with RAUTA" }))
    expect(create).not.toHaveBeenCalled()
    fireEvent.click(screen.getByRole("button", { name: "Resume workout" }))
    expect(resume).toHaveBeenCalledOnce()
    fireEvent.click(screen.getByRole("button", { name: "Train with RAUTA" }))
    fireEvent.click(screen.getByRole("button", { name: "Choose exercises" }))
    expect(create).toHaveBeenCalledOnce()
    fireEvent.click(screen.getByRole("button", { name: "Train with RAUTA" }))
    fireEvent.click(screen.getByRole("button", { name: "My preferences" }))
    expect(settings).toHaveBeenCalledOnce()
  })
})
