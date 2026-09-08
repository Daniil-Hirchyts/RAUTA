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
import {
  motion,
  useReducedMotion,
  useTransform,
  useMotionValue,
} from "motion/react"

import { usePageLayer } from "@/hooks/use-app-shell"
import {
  requestRautaOrientation,
  useRautaMotion,
  type RautaGestureEvent,
} from "@/hooks/use-rauta-motion"
import { triggerHaptic } from "@/lib/haptics"
import type { RautaMood, RautaReaction, RautaSource } from "@/lib/rauta"

import { RautaSpeech } from "./rauta-speech"

// The 512px artboard reserves space for jumps around the actual silhouette.
const RAUTA_BODY = { left: 0.2, top: 0.1, width: 0.6, height: 0.75 }

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
  speech?: string
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
  speech,
  inset,
  ...props
}: RautaProps) {
  const reduced = useReducedMotion()
  const { active } = usePageLayer()
  const [runtimeReady, setRuntimeReady] = useState(false)
  const [loadingPress, setLoadingPress] = useState(false)
  const [request, setRequest] = useState<RautaRequest | undefined>()
  const [pressed, setPressed] = useState(false)
  const [spoken, setSpoken] = useState<{ text: string; nonce: number } | null>(
    null
  )
  const [speechVisible, setSpeechVisible] = useState(false)
  const speechNonce = useRef(0)
  const say = useCallback((text: string) => {
    setSpoken({ text, nonce: ++speechNonce.current })
    setSpeechVisible(true)
  }, [])
  useEffect(() => {
    if (!active || !speech) return
    const timer = window.setTimeout(() => say(speech), 350)
    return () => window.clearTimeout(timer)
  }, [active, speech, say])
  useEffect(() => {
    if (!spoken) return
    const timer = window.setTimeout(() => setSpeechVisible(false), 4800)
    return () => window.clearTimeout(timer)
  }, [spoken])
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
    const surface = host.querySelector(".app-surface")
    if (surface) observer.observe(surface)
    observer.observe(node)
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
      if (event.type === "drag-start") {
        setPressed(true)
        setSpeechVisible(false)
      }
      if (event.type === "drag-end")
        say(event.speed > 900 ? "Here we go!" : "This spot works.")
      if (event.type === "rotate") say("A new perspective!")
      if (event.type === "collision")
        say(
          event.strength === "hard"
            ? "Whoa. Found the edge!"
            : "Just a little bounce."
        )
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
    [react, say]
  )

  const interactive = !reduced && active
  const { ref, x, y, rotate, scale, handlers, measure } = useRautaMotion({
    inset,
    body: RAUTA_BODY,
    onGesture,
    disabled: !interactive,
  })

  useLayoutEffect(() => {
    measure()
  }, [layer, measure])

  // Motion values keep the bubble in sync with both dragging and page layout.
  const originX = useMotionValue(0)
  const originY = useMotionValue(0)
  const shellWidth = useMotionValue(390)
  useLayoutEffect(() => {
    originX.set(layer?.left ?? 0)
    originY.set(layer?.top ?? 0)
    shellWidth.set(layer?.host.clientWidth ?? 390)
  }, [layer, originX, originY, shellWidth])
  const speechX = useTransform(() => {
    const left = originX.get() + x.get()
    if (left >= 234) return -234
    if (left + size + 234 <= shellWidth.get()) return size + 10
    return Math.max(
      10 - left,
      Math.min(size / 2 - 112, shellWidth.get() - 234 - left)
    )
  })
  const speechY = useTransform(() => {
    const left = originX.get() + x.get()
    if (left >= 234 || left + size + 234 <= shellWidth.get()) return 0
    return originY.get() + y.get() < 170 ? size + 8 : -112
  })

  const activate = () => {
    say(speech ?? "I'm here. Drag me, give me a twist, or let's train.")
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
      }}
      {...handlers}
    >
      <motion.div className="h-full w-full" style={{ rotate, scale }}>
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
      {active ? (
        <motion.div
          className="pointer-events-none absolute top-0 left-0 w-56"
          style={{ x: speechX, y: speechY }}
        >
          <RautaSpeech visible={speechVisible && !pressed}>
            <p
              role="status"
              className="text-[13px] leading-snug text-foreground"
            >
              {spoken?.text}
            </p>
          </RautaSpeech>
        </motion.div>
      ) : null}
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
