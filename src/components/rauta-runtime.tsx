/* eslint-disable react-hooks/immutability -- Rive state-machine inputs are imperative SDK handles, not React state. */
import { useEffect, useRef, useState } from "react"
import {
  Alignment,
  Fit,
  Layout,
  RuntimeLoader,
  useRive,
  useStateMachineInput,
} from "@rive-app/react-canvas"
import wasmUrl from "@rive-app/canvas/rive.wasm?url"
import { RautaStill, type RautaProps } from "./rauta"

// Bundle the runtime with the app: native/offline launches must not depend on a CDN.
RuntimeLoader.setWasmUrl(wasmUrl)
const MACHINE = "KettlebellBotMachine"
const MOOD = {
  calm: 0,
  curious: 1,
  listening: 15,
  focused: 7,
  happy: 9,
  proud: 10,
  working: 3,
  blocked: 5,
}

export default function RautaRuntime({
  mood = "calm",
  label,
  onActivate,
  reactionKey,
}: RautaProps) {
  const [failed, setFailed] = useState(false)
  const { rive, RiveComponent } = useRive({
    src: "/rauta/rauta.riv",
    artboard: "KettlebellBot",
    stateMachine: MACHINE,
    autoplay: true,
    layout: new Layout({ fit: Fit.Contain, alignment: Alignment.Center }),
    onLoadError: () => setFailed(true),
  })
  const status = useStateMachineInput(rive, MACHINE, "status")
  const intensity = useStateMachineInput(rive, MACHINE, "intensity")
  const facing = useStateMachineInput(rive, MACHINE, "facing")
  const gazeX = useStateMachineInput(rive, MACHINE, "gazeX")
  const gazeY = useStateMachineInput(rive, MACHINE, "gazeY")
  const pressed = useStateMachineInput(rive, MACHINE, "pressed")
  const tapped = useStateMachineInput(rive, MACHINE, "tapped")
  const acknowledge = useStateMachineInput(rive, MACHINE, "acknowledge")
  const previous = useRef(reactionKey)
  const drag = useRef<{
    id: number
    x: number
    y: number
    from: number
    moved: boolean
  } | null>(null)
  const suppressClick = useRef(false)

  useEffect(() => {
    if (status) status.value = MOOD[mood]
  }, [mood, status])
  useEffect(() => {
    if (intensity) intensity.value = 0.58
  }, [intensity])
  useEffect(() => {
    if (previous.current === reactionKey) return
    previous.current = reactionKey
    const timer = window.setTimeout(() => acknowledge?.fire(), 120)
    return () => window.clearTimeout(timer)
  }, [reactionKey, acknowledge])
  useEffect(() => {
    const update = () => {
      if (document.hidden) rive?.pause()
      else rive?.play()
    }
    update()
    document.addEventListener("visibilitychange", update)
    return () => document.removeEventListener("visibilitychange", update)
  }, [rive])

  const release = () => {
    drag.current = null
    if (pressed) pressed.value = false
  }
  return (
    <button
      type="button"
      aria-label={label}
      data-swipe-ignore
      data-haptics="off"
      className="relative h-full w-full touch-pan-y rounded-full outline-none focus-visible:ring-2 focus-visible:ring-primary"
      onClick={() => {
        if (suppressClick.current) {
          suppressClick.current = false
          return
        }
        tapped?.fire()
        onActivate?.()
      }}
      onPointerDown={(event) => {
        if (event.button !== 0) return
        suppressClick.current = false
        drag.current = {
          id: event.pointerId,
          x: event.clientX,
          y: event.clientY,
          from: Number(facing?.value ?? 0),
          moved: false,
        }
        event.currentTarget.setPointerCapture?.(event.pointerId)
        if (pressed) pressed.value = true
      }}
      onPointerMove={(event) => {
        const gesture = drag.current
        if (gesture && gesture.id === event.pointerId) {
          const dx = event.clientX - gesture.x
          const dy = event.clientY - gesture.y
          if (Math.hypot(dx, dy) > 6) gesture.moved = true
          if (gesture.moved && facing) {
            // Calm releases the rig's scripted turn so a drag owns the facing.
            if (status) status.value = MOOD.calm
            facing.value = (((gesture.from + dx * 1.3) % 360) + 360) % 360
          }
          if (gazeX) gazeX.value = Math.max(-1, Math.min(1, dx / 54))
          if (gazeY) gazeY.value = Math.max(-1, Math.min(1, dy / 54))
        } else if (event.pointerType === "mouse") {
          const box = event.currentTarget.getBoundingClientRect()
          if (gazeX)
            gazeX.value = ((event.clientX - box.left) / box.width) * 2 - 1
          if (gazeY)
            gazeY.value = ((event.clientY - box.top) / box.height) * 2 - 1
        }
      }}
      onPointerUp={() => {
        suppressClick.current = drag.current?.moved ?? false
        release()
        if (gazeX) gazeX.value = 0
        if (gazeY) gazeY.value = 0
      }}
      onPointerCancel={() => {
        suppressClick.current = true
        release()
        if (gazeX) gazeX.value = 0
        if (gazeY) gazeY.value = 0
      }}
      onLostPointerCapture={release}
      onPointerLeave={() => {
        if (gazeX) gazeX.value = 0
        if (gazeY) gazeY.value = 0
      }}
    >
      <span
        aria-hidden="true"
        className="pointer-events-none absolute inset-0 brightness-125"
      >
        {failed || !rive ? <RautaStill /> : null}
        {!failed ? (
          <RiveComponent className="absolute inset-0 h-full w-full" />
        ) : null}
      </span>
    </button>
  )
}
