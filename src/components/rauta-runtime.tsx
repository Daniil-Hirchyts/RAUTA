/* eslint-disable react-hooks/immutability -- Rive state-machine inputs are imperative SDK handles, not React state. */
import { useCallback, useEffect, useRef, useState } from "react"
import {
  Alignment,
  Fit,
  Layout,
  RuntimeLoader,
  useRive,
  useStateMachineInput,
} from "@rive-app/react-canvas"
import wasmUrl from "@rive-app/canvas/rive.wasm?url"

import {
  createRautaActivity,
  RAUTA_MOOD_STATUS,
  RAUTA_REACTIONS,
  requestRautaReaction,
  scheduleRautaIdle,
  type RautaActivity,
  type RautaReaction,
} from "@/lib/rauta"
import { RautaStill, type RautaProps } from "./rauta"

// Bundle the runtime with the app: native/offline launches must not depend on a CDN.
RuntimeLoader.setWasmUrl(wasmUrl)
const MACHINE = "KettlebellBotMachine"

/** How often the character is offered the chance to have a thought of its own.
 *  The scheduler decides whether it takes it, so this is a poll rate and not an
 *  animation beat: most ticks do nothing at all. */
const IDLE_TICK_MS = 1100

export default function RautaRuntime({
  mood = "calm",
  label,
  onActivate,
  reactionKey,
  request,
  interactionRequest,
  pressed: isPressed = false,
  ambient = true,
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
  const gazeX = useStateMachineInput(rive, MACHINE, "gazeX")
  const gazeY = useStateMachineInput(rive, MACHINE, "gazeY")
  const pressedInput = useStateMachineInput(rive, MACHINE, "pressed")

  // Every one-shot the artwork exposes, bound once and addressed by name, so a
  // screen asks for "celebrate" rather than reaching for a rig handle.
  const triggers: Partial<Record<RautaReaction, { fire: () => void } | null>> =
    {
      acknowledge: useStateMachineInput(rive, MACHINE, "acknowledge"),
      surprise: useStateMachineInput(rive, MACHINE, "surprise"),
      celebrate: useStateMachineInput(rive, MACHINE, "celebrate"),
      frustrated: useStateMachineInput(rive, MACHINE, "frustrated"),
      relieved: useStateMachineInput(rive, MACHINE, "relieved"),
      wobble: useStateMachineInput(rive, MACHINE, "wobble"),
      gearUp: useStateMachineInput(rive, MACHINE, "gearUp"),
      laugh: useStateMachineInput(rive, MACHINE, "laugh"),
      tapped: useStateMachineInput(rive, MACHINE, "tapped"),
      recoil: useStateMachineInput(rive, MACHINE, "recoil"),
      peek: useStateMachineInput(rive, MACHINE, "peek"),
      blink: useStateMachineInput(rive, MACHINE, "blink"),
      blinkDouble: useStateMachineInput(rive, MACHINE, "blinkDouble"),
      wink: useStateMachineInput(rive, MACHINE, "wink"),
      spinLeft: useStateMachineInput(rive, MACHINE, "spinLeft"),
      spinRight: useStateMachineInput(rive, MACHINE, "spinRight"),
      turnaround: useStateMachineInput(rive, MACHINE, "turnaround"),
    }
  const rig = useRef(triggers)
  useEffect(() => {
    rig.current = triggers
  })

  const activity = useRef<RautaActivity>(createRautaActivity())
  const previousKey = useRef(reactionKey)
  const previousRequest = useRef<number | undefined>(undefined)
  const previousInteraction = useRef<number | undefined>(undefined)

  /** One place that decides whether a reaction is allowed to play, so priority
   *  and cooldown apply the same way to the engine, to a finger and to idle. */
  const play = useCallback(
    (
      source: Parameters<typeof requestRautaReaction>[1]["source"],
      reaction: RautaReaction
    ) => {
      const outcome = requestRautaReaction(activity.current, {
        source,
        reaction,
        now: Date.now(),
      })
      activity.current = outcome.activity
      if (outcome.play) rig.current[outcome.play]?.fire()
    },
    []
  )

  useEffect(() => {
    if (status) status.value = RAUTA_MOOD_STATUS[mood]
  }, [mood, status])
  useEffect(() => {
    if (intensity) intensity.value = 0.58
  }, [intensity])
  useEffect(() => {
    if (pressedInput) pressedInput.value = isPressed
  }, [isPressed, pressedInput])

  // Something the app or the engine did. It outranks everything else.
  useEffect(() => {
    if (previousKey.current === reactionKey) return
    previousKey.current = reactionKey
    const timer = window.setTimeout(() => play("explicit", "acknowledge"), 120)
    return () => window.clearTimeout(timer)
  }, [reactionKey, play])

  useEffect(() => {
    if (!request || previousRequest.current === request.nonce) return
    previousRequest.current = request.nonce
    if (RAUTA_REACTIONS.includes(request.reaction))
      play(request.source, request.reaction)
  }, [request, play])

  useEffect(() => {
    if (
      !interactionRequest ||
      previousInteraction.current === interactionRequest.nonce
    )
      return
    previousInteraction.current = interactionRequest.nonce
    play(interactionRequest.source, interactionRequest.reaction)
  }, [interactionRequest, play])

  // The character's own thoughts, while nothing else is going on. One timer,
  // and it stops with the component or whenever the tab is hidden.
  useEffect(() => {
    if (!ambient || !rive) return
    // The character's clock starts when it appears, not when the module loaded.
    activity.current.ambientDueAt = Date.now() + 5200
    const timer = window.setInterval(() => {
      if (document.hidden) return
      const outcome = scheduleRautaIdle(activity.current, Date.now())
      activity.current = outcome.activity
      if (outcome.play) rig.current[outcome.play]?.fire()
    }, IDLE_TICK_MS)
    return () => window.clearInterval(timer)
  }, [ambient, rive])

  useEffect(() => {
    const update = () => {
      if (document.hidden) rive?.pause()
      else rive?.play()
    }
    update()
    document.addEventListener("visibilitychange", update)
    return () => document.removeEventListener("visibilitychange", update)
  }, [rive])

  return (
    <button
      type="button"
      aria-label={label}
      data-swipe-ignore
      data-haptics="off"
      className="relative h-full w-full rounded-full outline-none focus-visible:ring-2 focus-visible:ring-primary"
      onClick={() => onActivate?.()}
      onPointerMove={(event) => {
        // Following the pointer with the eyes only, and only for a mouse: on a
        // phone the finger is already on the character.
        if (event.pointerType !== "mouse") return
        const box = event.currentTarget.getBoundingClientRect()
        if (gazeX)
          gazeX.value = ((event.clientX - box.left) / box.width) * 2 - 1
        if (gazeY)
          gazeY.value = ((event.clientY - box.top) / box.height) * 2 - 1
      }}
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
