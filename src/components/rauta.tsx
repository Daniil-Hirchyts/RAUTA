import {
  lazy,
  Suspense,
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from "react"
import { createPortal } from "react-dom"
import { motion, useReducedMotion } from "motion/react"

import { usePageLayer } from "@/hooks/use-app-shell"
import {
  requestRautaOrientation,
  useRautaMotion,
  type RautaGestureEvent,
} from "@/hooks/use-rauta-motion"
import { triggerHaptic } from "@/lib/haptics"
import type { RautaMood, RautaReaction, RautaSource } from "@/lib/rauta"

const AnimatedRauta = lazy(() => import("./rauta-runtime"))

export type { RautaMood } from "@/lib/rauta"

/** A reaction the character has been asked to play. The nonce is what makes a
 *  repeat of the same reaction a new request rather than a no-op. */
export type RautaRequest = {
  reaction: RautaReaction
  source: RautaSource
  nonce: number
}

export type RautaProps = {
  mood?: RautaMood
  size?: number
  onActivate?: () => void
  label?: string
  reactionKey?: string
  request?: RautaRequest
  interactionRequest?: RautaRequest
  pressed?: boolean
  ambient?: boolean
  /** Room to keep clear at each screen edge so the character cannot come to
   *  rest on top of a control the person needs. */
  inset?: { top?: number; right?: number; bottom?: number; left?: number }
}

function ReadyRauta({
  onReady,
  ...props
}: RautaProps & { onReady: () => void }) {
  useEffect(() => onReady(), [onReady])
  return <AnimatedRauta {...props} />
}

export function RautaStill() {
  return (
    <img
      src="/rauta/rauta.svg"
      alt=""
      className="h-full w-full object-contain"
    />
  )
}

/**
 * How the character answers being handled.
 *
 * Deliberately sparse. A gentle drag is not an event worth an animation, and
 * reacting to every pointer sample would make the character twitch rather than
 * respond — so only the things that genuinely happened to it get a reaction,
 * and the scheduler underneath still applies its own cooldowns on top.
 */
function reactionFor(event: RautaGestureEvent): RautaReaction | null {
  switch (event.type) {
    case "tap":
      return "tapped"
    case "drag-start":
      return null
    case "throw":
      // Being flung is startling; being nudged is not.
      return event.speed > 900 ? "surprise" : null
    case "collision":
      return event.strength === "hard" ? "recoil" : "wobble"
    case "rotate":
      return "surprise"
    default:
      return null
  }
}

/**
 * RAUTA, wherever it appears.
 *
 * The character is draggable, throwable and twistable inside whatever screen it
 * is on, and it reacts to all three. Everything physical about that lives in
 * `useRautaMotion`, everything expressive in `@/lib/rauta`; this component is
 * the join, plus the plain button that has to keep working when the character
 * cannot be rendered at all.
 *
 * Position and rotation are motion values written straight to the element, so
 * dragging the character never re-renders the screen behind it.
 */
export function Rauta({
  size = 104,
  label = "Interact with RAUTA",
  onActivate,
  inset,
  ...props
}: RautaProps) {
  const reduced = useReducedMotion()
  const { active } = usePageLayer()
  const [runtimeReady, setRuntimeReady] = useState(false)
  const [loadingPress, setLoadingPress] = useState(false)
  const [request, setRequest] = useState<RautaRequest | undefined>()
  const [pressed, setPressed] = useState(false)
  const nonce = useRef(0)
  const anchor = useRef<HTMLDivElement | null>(null)
  const [layer, setLayer] = useState<{
    host: HTMLElement
    left: number
    top: number
  } | null>(null)
  useLayoutEffect(() => {
    const node = anchor.current
    const host = node?.closest<HTMLElement>(".app-shell-frame")
    if (!node || !host || !active) return
    const update = () => {
      const box = node.getBoundingClientRect()
      const frame = host.getBoundingClientRect()
      const left = box.left - frame.left
      const top = box.top - frame.top
      setLayer((previous) =>
        previous?.host === host &&
        previous.left === left &&
        previous.top === top
          ? previous
          : { host, left, top }
      )
    }
    update()
    const observer = new ResizeObserver(update)
    observer.observe(host)
    window.addEventListener("scroll", update, true)
    window.addEventListener("resize", update)
    return () => {
      observer.disconnect()
      window.removeEventListener("scroll", update, true)
      window.removeEventListener("resize", update)
    }
  }, [active, size])
  const markRuntimeReady = useCallback(() => setRuntimeReady(true), [])

  const react = useCallback((source: RautaSource, reaction: RautaReaction) => {
    nonce.current += 1
    setRequest({ reaction, source, nonce: nonce.current })
  }, [])

  const onGesture = useCallback(
    (event: RautaGestureEvent) => {
      if (event.type === "drag-start") setPressed(true)
      if (
        event.type === "drag-end" ||
        event.type === "tap" ||
        event.type === "gesture-end"
      )
        setPressed(false)
      if (event.type === "collision" && event.strength === "hard")
        triggerHaptic("warning")
      const reaction = reactionFor(event)
      if (reaction) react("interaction", reaction)
    },
    [react]
  )

  const interactive = !reduced && active
  const { ref, x, y, rotate, scale, handlers } = useRautaMotion({
    inset,
    onGesture,
    disabled: !interactive,
  })

  const activate = () => {
    triggerHaptic("selection")
    // The only place motion access is ever asked for: a deliberate touch on the
    // character itself, never on launch. A refusal changes nothing else.
    void requestRautaOrientation()
    onActivate?.()
  }

  const loadingGate = !runtimeReady || loadingPress
  const character = (
    <motion.div
      ref={ref}
      data-rauta-character
      data-swipe-ignore
      className="z-50 shrink-0 touch-none"
      style={{
        position: layer && active ? "absolute" : "relative",
        left: layer && active ? layer.left : undefined,
        top: layer && active ? layer.top : undefined,
        width: size,
        height: size,
        x,
        y,
        rotate,
        scale,
      }}
      {...handlers}
    >
      {reduced || !active ? (
        <button
          type="button"
          data-haptics="off"
          aria-label={label}
          className="h-full w-full rounded-full focus-visible:ring-2 focus-visible:ring-primary"
          onClick={activate}
        >
          <RautaStill />
        </button>
      ) : (
        <div className="relative h-full w-full">
          <Suspense
            fallback={
              <span aria-hidden="true" className="absolute inset-0">
                <RautaStill />
              </span>
            }
          >
            <ReadyRauta
              {...props}
              // Reduced motion keeps the expressions and drops the fidgeting.
              ambient={props.ambient ?? !reduced}
              label={loadingGate ? undefined : label}
              onActivate={loadingGate ? undefined : activate}
              onReady={markRuntimeReady}
              pressed={pressed}
              interactionRequest={request}
            />
          </Suspense>
          {loadingGate ? (
            <button
              type="button"
              data-haptics="off"
              aria-label={label}
              className="absolute inset-0 z-20 h-full w-full rounded-full outline-none focus-visible:ring-2 focus-visible:ring-primary"
              onPointerDown={() => setLoadingPress(true)}
              onPointerCancel={() => setLoadingPress(false)}
              onClick={() => {
                activate()
                setLoadingPress(false)
              }}
            >
              <span className="sr-only">{label}</span>
            </button>
          ) : null}
        </div>
      )}
    </motion.div>
  )
  return (
    <div
      ref={anchor}
      className="shrink-0"
      style={{ width: size, height: size }}
    >
      {layer && active ? createPortal(character, layer.host) : character}
    </div>
  )
}
