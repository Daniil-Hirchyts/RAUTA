import {
  lazy,
  Suspense,
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
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
import {
  pickRautaResponse,
  RAUTA_CUE_EVENT,
  type RautaCue,
} from "@/lib/rauta-cues"

import { RautaPanel, type RautaAction } from "./rauta-panel"

// The 512px artboard reserves space for jumps around the actual silhouette.
const RAUTA_BODY = { left: 0.2, top: 0.1, width: 0.6, height: 0.75 }

/** Air between the panel and the edges of the screen it sits in. */
const GUTTER = 12

/** The shortest a panel may be, whatever it is holding and however small the
 *  character standing against it. */
const PANEL_MIN_HEIGHT = 96
const FLOATING_LIFT = 8

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
   *  rest on top of a control the person needs. A page that keeps a band at
   *  its own foot can instead mark that element `data-rauta-floor`, and the
   *  character stands on top of it. */
  inset?: { top?: number; right?: number; bottom?: number; left?: number }
  /** A quieter second line under what the character says: what the screen is
   *  set to, rather than something RAUTA is saying about it. */
  meta?: ReactNode
  /** What it is saying went wrong, rather than what it is going to do. */
  alert?: boolean
  /** The line is a passing remark, not the state of the screen: it is said
   *  when it changes and then the panel goes away again. For a screen being
   *  worked on — a set being logged, a timer running — where a standing panel
   *  would be a slab over the top of the work. */
  transient?: boolean
  /** What tapping the character offers to do. With actions, a tap opens the
   *  panel and the choices grow into it; without them a tap is `onActivate`. */
  actions?: RautaAction[]
  /** The screen's own instrument, shown inside the panel: one panel at the
   *  foot of the screen rather than a character's bar and a fixed bar under
   *  it. A screen with one keeps its panel whether or not there is a line. */
  footer?: ReactNode
  /** Which edge the character stands against, and which way its panel opens.
   *  Bottom by default; a screen that keeps its own controls down there puts
   *  the character in the top corner instead. */
  place?: "bottom" | "top"
  /** Whether the choices are showing. Left alone, the character keeps track of
   *  that itself; a screen that has to close the panel — because the thing it
   *  offered has now been done — passes both of these and owns it. */
  open?: boolean
  onOpenChange?: (open: boolean) => void
}

/** Where the character is rendered, and the area its bubble may use. Both are
 *  in the coordinates of the surface it is portalled into. Its own resting
 *  place is not here: that is a motion value, because a drag writes to it at
 *  pointer rate. */
type RautaLayer = {
  host: HTMLElement
  /** The page's own layer. The panel goes in here rather than on the surface,
   *  so the page's title and its back button paint over the top of it: the
   *  navigation sits inside the panel rather than being covered by it. */
  page: HTMLElement | null
  stage: { left: number; top: number; width: number; height: number }
}

function sameLayer(a: RautaLayer | null, b: RautaLayer) {
  return (
    a !== null &&
    a.host === b.host &&
    a.page === b.page &&
    a.stage.left === b.stage.left &&
    a.stage.top === b.stage.top &&
    a.stage.width === b.stage.width &&
    a.stage.height === b.stage.height
  )
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
function reactionFor(
  event: RautaGestureEvent,
  variation: number
): RautaReaction | null {
  switch (event.type) {
    case "tap":
      return ["tapped", "wink", "laugh", "acknowledge"][
        variation % 4
      ] as RautaReaction
    case "drag-start":
      return null
    case "drag-end":
      return event.speed < 180
        ? (["relieved", "wink", "acknowledge"][variation % 3] as RautaReaction)
        : null
    case "throw":
      if (event.speed < 900) return "wobble"
      if (event.speed > 1450)
        return event.velocityX < 0 ? "spinLeft" : "spinRight"
      return "surprise"
    case "collision":
      return event.strength === "hard" ? "recoil" : "wobble"
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
  actions,
  alert,
  footer,
  transient = false,
  size: requestedSize,
  label = "Interact with RAUTA",
  meta,
  onActivate,
  onOpenChange,
  open: shown,
  place = "bottom",
  speech,
  inset,
  ...props
}: RautaProps) {
  const reduced = useReducedMotion()
  const size = requestedSize ?? (place === "top" ? 72 : 104)
  const { active } = usePageLayer()
  const [runtimeReady, setRuntimeReady] = useState(false)
  const [loadingPress, setLoadingPress] = useState(false)
  const [request, setRequest] = useState<RautaRequest | undefined>()
  const [pressed, setPressed] = useState(false)
  /** Whether the panel is showing what tapping the character offers. Owned
   *  here unless the screen passed its own answer. */
  const [opened, setOpened] = useState(false)
  const open = active && (shown ?? opened)
  const show = useCallback(
    (next: boolean) => {
      if (shown === undefined) setOpened(next)
      onOpenChange?.(next)
    },
    [onOpenChange, shown]
  )
  /**
   * What the character has just said, over the top of what the screen has it
   * saying. The `speech` prop is a standing line — the state of the plan, the
   * step you are on — and stays up as long as it is true; a remark about being
   * thrown into a wall is worth a few seconds and then the standing line is
   * back. With neither, there is nothing to say and no panel to say it in.
   */
  const [remark, setRemark] = useState<{ text: string; nonce: number } | null>(
    null
  )
  const remarkNonce = useRef(0)
  const say = useCallback((text: string) => {
    setRemark({ text, nonce: ++remarkNonce.current })
  }, [])
  useEffect(() => {
    if (!remark) return
    const timer = window.setTimeout(() => setRemark(null), 2600)
    return () => window.clearTimeout(timer)
  }, [remark])
  // A passing line is said once, when it changes, and then it is over.
  const said = useRef<string | undefined>(undefined)
  useEffect(() => {
    if (!transient || !active || !speech || said.current === speech) return
    said.current = speech
    say(speech)
  }, [active, say, speech, transient])
  // A page that is not the one in view says nothing and offers nothing: read
  // that off the layer rather than syncing state to it.
  const line = active
    ? (remark?.text ?? (transient ? null : (speech ?? null)))
    : null
  const nonce = useRef(0)
  const gestureVariation = useRef(0)
  const anchor = useRef<HTMLDivElement | null>(null)
  const [layer, setLayer] = useState<RautaLayer | null>(null)
  /** Where the character rests, in the surface's coordinates: the foot of the
   *  screen, whatever the page underneath it is doing. Kept as motion values
   *  because the drag transform is added to them on the same frame. */
  const originX = useMotionValue(0)
  const originY = useMotionValue(0)
  useLayoutEffect(() => {
    const node = anchor.current
    const frame = node?.closest<HTMLElement>(".app-shell-frame")
    // The visible surface, not the shell around it: the character travels out
    // of sight with the page rather than over the shell's own edges.
    const host = frame?.querySelector<HTMLElement>(".app-surface") ?? frame
    if (!node || !host || !active) {
      // Rendered in its own slot; the transform is then the drag alone.
      originX.set(0)
      originY.set(0)
      return
    }
    const update = () => {
      const page =
        node.closest<HTMLElement>(".app-page-layer") ??
        host.querySelector<HTMLElement>('.app-page-layer[data-active="true"]')
      const screen =
        node.closest<HTMLElement>(".app-screen") ??
        page?.querySelector<HTMLElement>(".app-screen") ??
        page
      const floor = screen?.querySelector<HTMLElement>("[data-rauta-floor]")
      const surface = host.getBoundingClientRect()
      // An absolutely positioned child starts inside the host's border, so
      // every reading below is taken from that padding edge.
      const baseLeft = surface.left + host.clientLeft
      const baseTop = surface.top + host.clientTop
      // The character stands at the foot of the screen rather than in the slot
      // it was written in. The page scrolls behind it, the companion row it
      // belongs to can scroll away entirely, and the character is still in the
      // same corner — which is also where the magnet brings it back to.
      // The artboard carries its own transparent margin, so the box sits flush
      // in the corner and the silhouette lands a comfortable way inside it.
      // A screen that keeps something at its own foot — a timer, a row of
      // presets — marks that as the floor, and the character stands on top of
      // it rather than in front of it.
      const floorTop =
        floor?.isConnected === true
          ? floor.getBoundingClientRect().top - baseTop
          : host.clientHeight
      // The band the page's title occupies, taken from its height rather than
      // from where it currently is: the title slides away as the page scrolls,
      // and the panel under it must not jump up and down with it.
      const header =
        screen?.querySelector<HTMLElement>(".app-shell-header") ?? null
      const ceiling = header ? header.offsetHeight : 0
      if (place === "top") {
        // The corner a screen keeps for its home button, standing at the
        // height of the title rather than under it — a screen that keeps its
        // own controls along the bottom gets its character up here, and the
        // panel opens downwards from it. Where that corner is already taken
        // by a control, the character stands beside it rather than over it.
        const corner = screen?.querySelector(
          ".app-shell-header-row .app-shell-header-action:last-child button"
        )
        const taken = corner ? corner.getBoundingClientRect().width + GUTTER : 0
        // Half a gutter of air on both axes, so the silhouette clears the
        // surface's own corner curve rather than being shaved by it.
        originX.set(
          host.clientWidth - size - GUTTER / 2 - (inset?.right ?? 0) - taken
        )
        originY.set(Math.max(0, GUTTER / 2 + (inset?.top ?? 0) - FLOATING_LIFT))
      } else {
        originX.set(inset?.left ?? 0)
        originY.set(
          Math.min(floorTop, host.clientHeight) -
            size -
            (inset?.bottom ?? 0) -
            FLOATING_LIFT
        )
      }
      // The panel gets the visible surface, minus the page's own title: it may
      // pass in front of the content it is talking about, never in front of the
      // heading that says where you are.
      const stageTop = ceiling
      const next: RautaLayer = {
        host,
        page,
        stage: {
          left: surface.left - baseLeft,
          top: stageTop,
          width: surface.width,
          height: surface.bottom - baseTop - stageTop,
        },
      }
      setLayer((previous) => (sameLayer(previous, next) ? previous : next))
    }
    update()
    // A page that is still sliding in measures a surface mid-flight, so the
    // reading is taken again once it has landed.
    const painted = requestAnimationFrame(update)
    const landed = window.setTimeout(update, 420)
    // A character that outlives the page it is standing on — one flow, several
    // pages — has to hand its panel to whichever page is in view now.
    const stack = host.querySelector(".app-page-stack") ?? host
    const pages = new MutationObserver(update)
    pages.observe(stack, {
      attributeFilter: ["data-active"],
      attributes: true,
      subtree: true,
    })
    const observer = new ResizeObserver(update)
    observer.observe(host)
    if (frame && frame !== host) observer.observe(frame)
    observer.observe(node)
    window.addEventListener("resize", update)
    // Scrolling is deliberately not listened for. Where the character stands
    // is a property of the screen, not of the page moving underneath it, so a
    // scroll has nothing to re-measure.
    return () => {
      cancelAnimationFrame(painted)
      window.clearTimeout(landed)
      observer.disconnect()
      pages.disconnect()
      window.removeEventListener("resize", update)
    }
  }, [
    active,
    inset?.bottom,
    inset?.left,
    inset?.right,
    inset?.top,
    originX,
    originY,
    place,
    size,
  ])
  const markRuntimeReady = useCallback(() => setRuntimeReady(true), [])

  const react = useCallback((source: RautaSource, reaction: RautaReaction) => {
    nonce.current += 1
    setRequest({ reaction, source, nonce: nonce.current })
  }, [])

  // Screens announce meaningful workout actions in product language. The
  // active RAUTA alone translates them into a varied line and a rig trigger.
  useEffect(() => {
    if (!active) return
    const answer = (event: Event) => {
      const cue = (event as CustomEvent<RautaCue>).detail
      const response = pickRautaResponse(cue)
      say(response.line)
      react("explicit", response.reaction)
    }
    window.addEventListener(RAUTA_CUE_EVENT, answer)
    return () => window.removeEventListener(RAUTA_CUE_EVENT, answer)
  }, [active, react, say])

  const onGesture = useCallback(
    (event: RautaGestureEvent) => {
      const variation = gestureVariation.current
      if (event.type === "drag-start") setPressed(true)
      if (event.type === "drag-end")
        say(
          event.speed > 900
            ? ["Here we go!", "Airborne!", "Easy with the iron!"][variation % 3]
            : ["Back to my post.", "Settled.", "Right where I belong."][
                variation % 3
              ]
        )
      if (event.type === "return") triggerHaptic("selection")
      if (event.type === "collision")
        say(
          event.strength === "hard"
            ? [
                "Whoa. Found the edge!",
                "That's one solid wall.",
                "Impact registered. I'm fine.",
              ][variation % 3]
            : ["Just a little bounce.", "Soft landing.", "A tiny detour."][
                variation % 3
              ]
        )
      if (
        event.type === "drag-end" ||
        event.type === "tap" ||
        event.type === "gesture-end"
      )
        setPressed(false)
      if (event.type === "collision" && event.strength === "hard")
        triggerHaptic("warning")
      const reaction = reactionFor(event, variation)
      if (
        event.type === "tap" ||
        event.type === "drag-end" ||
        event.type === "throw" ||
        event.type === "collision"
      )
        gestureVariation.current += 1
      if (reaction) react("interaction", reaction)
    },
    [react, say]
  )

  const interactive = !reduced && active
  const { ref, x, y, scale, handlers, measure, settle } = useRautaMotion({
    inset,
    body: RAUTA_BODY,
    onGesture,
    disabled: !interactive,
  })

  useLayoutEffect(() => {
    measure()
    // The place has moved — a different screen, a different corner, a resize.
    // Whatever the character was doing about the old one is finished with.
    settle()
  }, [layer, measure, place, settle, size])

  // The slot and the drag are one transform, so following a scroll costs the
  // same as a drag frame: two motion values and no render.
  const renderX = useTransform(() => originX.get() + x.get())
  const renderY = useTransform(() => originY.get() + y.get())

  const offers = Boolean(actions && actions.length > 0)
  const toggle = useCallback(() => {
    triggerHaptic("selection")
    show(!open)
  }, [open, show])
  const activate = () => {
    triggerHaptic("selection")
    // The only place motion access is ever asked for: a deliberate touch on the
    // character itself, never on launch. A refusal changes nothing else.
    void requestRautaOrientation()
    if (offers) show(!open)
    else if (!line) say("I'm here. Drag me, throw me, or let's train.")
    onActivate?.()
  }

  /**
   * Where the panel sits, and how much of its own edge it gives up to the
   * character standing against it.
   *
   * The artboard is mostly transparent margin, so the room to leave is the
   * silhouette's width, not the box's — and the character overlaps the panel
   * rather than sitting beside it, which is what makes the two read as one
   * thing rather than as an icon next to a bar.
   */
  const reserve = Math.max(0, size * RAUTA_BODY.width + size * RAUTA_BODY.left)
  const stage = layer?.stage
  // Part of the shell rather than a card floating on it: the panel meets the
  // sides and the edge it sits against, and only the edge facing the page is
  // drawn. Its outer corners are the shell's own curve, so the two are
  // concentric; the inner ones are a card's.
  // Positioned inline rather than through classes: the panel's glow treatment
  // is unlayered CSS and would otherwise win over a utility.
  const panelStyle: React.CSSProperties = {
    position: "absolute",
    zIndex: 25,
    left: 0,
    right: 0,
    // Never shorter than the character standing against it, and never thinner
    // than a band worth reading: a panel the silhouette overhangs on both
    // sides reads as a bar RAUTA is falling out of, whatever it is holding.
    minHeight: Math.max(PANEL_MIN_HEIGHT, Math.round(size * 0.92)),
    borderLeftWidth: 0,
    borderRightWidth: 0,
    // The shell's own curve on every corner, open or closed: two of them are
    // the shell's, and the other two have to answer them.
    borderRadius: "var(--app-surface-radius)",
    ...(place === "bottom"
      ? {
          bottom: 0,
          borderBottomWidth: 0,
        }
      : {
          top: 0,
          borderTopWidth: 0,
          // The page's title and its buttons live in this band, so the panel
          // starts its own content below them.
          paddingTop: stage?.top ?? 0,
        }),
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
        left: layer && active ? 0 : undefined,
        top: layer && active ? 0 : undefined,
        width: size,
        height: size,
        x: renderX,
        y: renderY,
      }}
      {...handlers}
    >
      <motion.div className="h-full w-full" style={{ scale }}>
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
    </motion.div>
  )
  const floating = Boolean(layer) && active
  const panel = (
    <RautaPanel
      actions={actions}
      alert={alert}
      footer={footer}
      // Pinned to the surface when there is one to pin it to, and simply the
      // next thing in the layout when there is not.
      className={floating ? undefined : "w-full"}
      line={line}
      meta={meta}
      onToggle={offers ? toggle : undefined}
      open={open}
      place={place}
      reserve={floating ? reserve : 0}
      style={floating ? panelStyle : undefined}
      // Nothing to say, nothing to choose and nothing to show is no panel at
      // all: it is not an empty bar waiting for a line, it is the line.
      visible={Boolean(line) || Boolean(footer) || (offers && open)}
    />
  )
  return (
    // Floating, the character takes no room in the page at all: the row it was
    // written into closes up, and the character stands over the screen instead.
    // Without a surface to stand on — an inactive page, or a screen with no
    // shell around it — it falls back to being an ordinary part of the layout.
    <div className={floating ? "contents" : "flex w-full flex-col gap-2"}>
      <div
        data-rauta-slot
        ref={anchor}
        className={floating ? "hidden" : "shrink-0"}
        style={floating ? undefined : { width: size, height: size }}
      >
        {floating && layer ? createPortal(character, layer.host) : character}
      </div>
      {floating && layer
        ? createPortal(panel, layer.page ?? layer.host)
        : panel}
    </div>
  )
}
