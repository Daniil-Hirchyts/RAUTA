import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  type KeyboardEvent,
  type PointerEvent,
  type ReactNode,
} from "react"
import { useReducedMotion } from "motion/react"

import { AnimatedCheck } from "@/components/animated-check"
import { triggerHaptic } from "@/lib/haptics"
import { cn } from "@/lib/utils"

/**
 * A deck of cards turned one at a time, where the card facing you is the
 * answer.
 *
 * A grid of choices asks you to read all of them before touching anything, and
 * shrinks every one to a thumbnail to make them fit. A deck asks for one card
 * at a time, at the size a picture is worth showing, with the next already
 * turning into view — so the choice is made by looking rather than by reading,
 * which is the only reason to spend a screen on it. Turning the deck is the
 * choosing: the card in the middle is what the caller is told about, and there
 * is nothing to confirm afterwards.
 *
 * The rake is one number followed through. Card width sets the spacing, how
 * far a card recedes and how wide the lens is, so a deck drawn at 180px and
 * one drawn at 280px are the same picture at two sizes.
 */

/** How far a press travels before the deck starts following it. The cards are
 *  buttons; a deck that moves under the first stray pixel eats their taps. */
const DRAG_SLOP = 6

/** Cards a flick is allowed to carry past the one it was thrown from. Further
 *  than this and the deck spins somewhere nobody aimed for. */
const MAX_THROW = 2

/** The settle is an exponential ease-out rather than a spring: a deck that
 *  overshoots reads as loose, and the card it overshoots onto is momentarily
 *  the answer. */
const SETTLE_RATE = 0.16
/** Close enough to the target that another frame would move nothing. */
const SETTLE_EPSILON = 0.0004

/** Past this the far cards turn their backs, which reads as a fold in the
 *  deck rather than a card. */
const MAX_TILT = 82

export type CoverflowSlide<Id extends string = string> = {
  id: Id
  /** Drawn on the card, and what the card is called to assistive tech. */
  title: string
  /** Said under the deck about the card facing you, and read out with that
   *  card. Long enough to be a sentence, short enough not to be a paragraph. */
  description?: string
  /** The card's face. A picture belongs here — which is what keeps stand-in
   *  art, image loading and everything else app-shaped out of this file. */
  media: ReactNode
}

export function CoverflowCarousel<Id extends string>({
  cardWidth = "clamp(190px, 58vw, 264px)",
  className,
  depth = 0.6,
  fade = 0.1,
  falloff = 0.56,
  gap = 0.05,
  label,
  loop = true,
  onChange,
  perspective = 3,
  rotate = 44,
  slides,
  value,
}: {
  /** Any CSS length. Everything else is derived from it, so the rake scales. */
  cardWidth?: string
  className?: string
  /** How far the first neighbour recedes, as a fraction of card width. */
  depth?: number
  /** Opacity lost per step from the centre. */
  fade?: number
  /** Exponent on distance. Below 1 the rake eases off as cards travel out. */
  falloff?: number
  /** Space between cards, as a fraction of card width. */
  gap?: number
  /** Names the deck for assistive tech. */
  label: string
  loop?: boolean
  onChange: (id: Id) => void
  /** Viewer distance as a multiple of card width — smaller is a wider lens. */
  perspective?: number
  /** Degrees the first neighbour tilts. */
  rotate?: number
  slides: CoverflowSlide<Id>[]
  value: Id
}) {
  const count = slides.length
  const reduced = useReducedMotion()
  // Two cards cannot be a ring: the fold that carries a card round the back
  // would put it half a turn away, which is the card next to it.
  const cycle = loop && count > 2

  /** Which card the deck opens on. Read on the first render and never again:
   *  where it has been turned to since is the deck's own business. */
  const opening = Math.max(
    0,
    slides.findIndex((slide) => slide.id === value)
  )

  const frameRef = useRef<HTMLDivElement>(null)
  const cardsRef = useRef<(HTMLButtonElement | null)[]>([])
  /** Fractional card index at the centre, and the whole state of the deck.
   *  Nothing renders off it — the cards are painted straight to the DOM. */
  const posRef = useRef(opening)
  /** Where the current settle is headed. Stepping off `pos` instead would
   *  swallow a keypress that lands mid-flight, before the round-off moves. */
  const targetRef = useRef(opening)
  const widthRef = useRef(0)
  const rafRef = useRef<number | null>(null)
  const dragRef = useRef<{
    dragging: boolean
    pointerId: number
    pos: number
    time: number
    velocity: number
    x: number
  } | null>(null)
  /** Set while a press is turning the deck, so the release does not also
   *  count as a tap on whichever card ended up under the finger. */
  const draggedRef = useRef(false)
  /** The answer this deck last gave. Anything else arriving in `value` was
   *  set somewhere else, and the deck travels to meet it. */
  const answeredRef = useRef<Id>(value)

  /** Nearest whole card, folded back into 0..count-1. */
  const indexAt = useCallback(
    (pos: number) => ((Math.round(pos) % count) + count) % count,
    [count]
  )

  const clampPos = useCallback(
    (pos: number) => (cycle ? pos : Math.max(0, Math.min(count - 1, pos))),
    [count, cycle]
  )

  // Painted straight to the DOM. Sixty state updates a second would re-render
  // every card for numbers React never needs to see.
  const paint = useCallback(() => {
    const width = widthRef.current
    if (!width) return
    const pitch = width * (1 + gap)
    const pos = posRef.current

    cardsRef.current.forEach((card, index) => {
      if (!card) return

      // Fold the distance into the shorter way round the ring. This is the
      // whole looping mechanism — no cloned nodes, no shuffling the DOM.
      let offset = index - pos
      if (cycle) {
        offset = ((offset % count) + count) % count
        if (offset > count / 2) offset -= count
      }

      const distance = Math.abs(offset)
      // Tilt and recession both ease off as cards travel out: doubling the
      // distance adds only about half again as much of each. A linear ramp
      // folds the second card shut; this keeps it readable.
      const ramp = Math.pow(distance, falloff)
      const tilt = Math.min(rotate * ramp, MAX_TILT) * Math.sign(offset)

      card.style.transform =
        `translateX(calc(-50% + ${offset * pitch}px)) ` +
        `translateZ(${-depth * width * ramp}px) rotateY(${-tilt}deg)`

      // A card is carried across the ring at exactly half a turn out, so it
      // has to be gone by then or the jump is visible.
      const edge = cycle ? Math.min(1, Math.max(0, count / 2 - distance)) : 1
      card.style.opacity = String(Math.max(0, 1 - fade * distance) * edge)
      card.style.zIndex = String(100 - Math.round(distance))
    })
  }, [count, cycle, depth, fade, falloff, gap, rotate])

  const glide = useCallback(
    (target: number) => {
      if (rafRef.current !== null) cancelAnimationFrame(rafRef.current)
      targetRef.current = target

      // Somebody who has asked for less motion has not asked for less deck:
      // the rake stays, the travel between cards goes.
      if (reduced) {
        posRef.current = target
        paint()
        rafRef.current = null
        return
      }

      const step = () => {
        const remaining = target - posRef.current
        if (Math.abs(remaining) < SETTLE_EPSILON) {
          posRef.current = target
          paint()
          rafRef.current = null
          return
        }
        posRef.current += remaining * SETTLE_RATE
        paint()
        rafRef.current = requestAnimationFrame(step)
      }
      rafRef.current = requestAnimationFrame(step)
    },
    [paint, reduced]
  )

  /** One tick per card the deck passes over, the way the dial ticks per notch,
   *  and the answer changes with it rather than at the end of the gesture. */
  const answer = (index: number) => {
    const slide = slides[index]
    if (!slide || slide.id === answeredRef.current) return
    answeredRef.current = slide.id
    triggerHaptic("selection")
    onChange(slide.id)
  }

  /** Settle on a whole card, and answer with the one that lands. */
  const land = (target: number) => {
    const settled = clampPos(target)
    glide(settled)
    answer(indexAt(settled))
  }

  /** The shorter way round to a card, rather than unwinding the whole ring. */
  const targetFor = (index: number) =>
    cycle
      ? index + Math.round((targetRef.current - index) / count) * count
      : index

  const onPointerDown = (event: PointerEvent<HTMLDivElement>) => {
    if (event.button > 0) return
    if (rafRef.current !== null) {
      cancelAnimationFrame(rafRef.current)
      rafRef.current = null
    }
    targetRef.current = posRef.current
    draggedRef.current = false
    dragRef.current = {
      dragging: false,
      pointerId: event.pointerId,
      pos: posRef.current,
      // The event's own clock, the same one the shell's edge swipe reads a
      // throw off.
      time: event.timeStamp,
      velocity: 0,
      x: event.clientX,
    }
  }

  const onPointerMove = (event: PointerEvent<HTMLDivElement>) => {
    const drag = dragRef.current
    if (!drag || drag.pointerId !== event.pointerId) return

    const pitch = widthRef.current * (1 + gap)
    if (!pitch) return

    const travelled = event.clientX - drag.x
    if (!drag.dragging) {
      if (Math.abs(travelled) < DRAG_SLOP) return
      drag.dragging = true
      draggedRef.current = true
      // The deck owns the gesture from here, so it keeps tracking once the
      // finger wanders off the cards.
      try {
        event.currentTarget.setPointerCapture(event.pointerId)
      } catch {
        // Capture is an enhancement; the drag still works without it.
      }
      // Measured from here on, so the deck does not jump by the slop it spent
      // deciding this was a drag.
      drag.x = event.clientX
      return
    }

    const now = event.timeStamp
    const previous = posRef.current
    posRef.current = clampPos(drag.pos - travelled / pitch)
    // Cards per second, for the throw.
    drag.velocity =
      ((posRef.current - previous) / Math.max(now - drag.time, 1)) * 1000
    drag.time = now

    answer(indexAt(posRef.current))
    paint()
  }

  const endDrag = (event: PointerEvent<HTMLDivElement>) => {
    const drag = dragRef.current
    if (!drag || drag.pointerId !== event.pointerId) return
    dragRef.current = null
    // A press that never travelled is a tap, and the card under it answers.
    if (!drag.dragging) return
    const carried = Math.max(
      -MAX_THROW,
      Math.min(MAX_THROW, drag.velocity * 0.18)
    )
    land(Math.round(posRef.current + carried))
  }

  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    const by = {
      ArrowDown: 1,
      ArrowLeft: -1,
      ArrowRight: 1,
      ArrowUp: -1,
    }[event.key]
    if (by === undefined) return
    event.preventDefault()
    const target = clampPos(Math.round(targetRef.current) + by)
    land(target)
    // The checked card is the one with the tab stop, so focus rides along with
    // it rather than being left on a card that is no longer the answer.
    cardsRef.current[indexAt(target)]?.focus()
  }

  // Card width drives pitch, depth and perspective, so it is the only thing
  // worth measuring — and only when the box actually changes.
  useLayoutEffect(() => {
    const frame = frameRef.current
    if (!frame) return

    const measure = () => {
      const card = cardsRef.current.find((node) => node)
      if (!card) return
      widthRef.current = card.offsetWidth
      paint()
    }

    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(frame)
    return () => observer.disconnect()
  }, [paint])

  // A value set anywhere but here — a profile restored, an answer changed on
  // another screen — is a card the deck has to turn to.
  useEffect(() => {
    if (value === answeredRef.current) return
    answeredRef.current = value
    const index = slides.findIndex((slide) => slide.id === value)
    if (index < 0) return
    glide(
      clampPos(
        cycle
          ? index + Math.round((targetRef.current - index) / count) * count
          : index
      )
    )
  }, [clampPos, count, cycle, glide, slides, value])

  useEffect(
    () => () => {
      if (rafRef.current !== null) cancelAnimationFrame(rafRef.current)
    },
    []
  )

  const facing = slides.find((slide) => slide.id === value)

  return (
    // Width is left alone rather than set to 100%: a caller that wants the
    // deck to run past the content column widens it with a negative margin,
    // and `w-full` would slide the box sideways instead of stretching it.
    <div className={className}>
      <div
        aria-label={label}
        className="cursor-grab overflow-hidden py-9 outline-none active:cursor-grabbing"
        // The deck reads a drag of its own; the shell's edge-swipe navigation
        // and the direct-touch haptic overlay both stay out of it.
        data-swipe-ignore
        onKeyDown={onKeyDown}
        onLostPointerCapture={endDrag}
        onPointerCancel={endDrag}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={endDrag}
        ref={frameRef}
        role="radiogroup"
        style={{
          ["--cf-card" as string]: cardWidth,
          perspective: `calc(var(--cf-card) * ${perspective})`,
          // The horizontal drag is ours; the page keeps vertical scrolling.
          touchAction: "pan-y",
        }}
      >
        {/* The plane the cards stand on takes no taps of its own. Every card
            but the middle one is pushed back in Z, which puts it behind this
            box — and a box that answers to the pointer would then swallow
            every tap that was not aimed at the centre. */}
        <div
          className="relative select-none"
          style={{
            height: "var(--cf-card)",
            pointerEvents: "none",
            transformStyle: "preserve-3d",
          }}
        >
          {slides.map((slide, index) => {
            const checked = slide.id === value
            return (
              <button
                aria-checked={checked}
                className={cn(
                  "absolute top-0 left-1/2 aspect-square cursor-[inherit] overflow-hidden rounded-[1.75rem] border bg-card text-left shadow-xl shadow-black/40 will-change-transform outline-none",
                  checked ? "border-primary/60" : "border-border"
                )}
                data-haptics="off"
                key={slide.id}
                onClick={() => {
                  if (draggedRef.current) return
                  land(targetFor(index))
                }}
                ref={(node) => {
                  cardsRef.current[index] = node
                  return () => {
                    cardsRef.current[index] = null
                  }
                }}
                role="radio"
                // Only the answer is a tab stop; the arrow keys turn the deck
                // from there, which is how a radio group is walked.
                style={{
                  // Taps come back to the cards themselves — see the plane.
                  pointerEvents: "auto",
                  transform: "translateX(-50%)",
                  width: "var(--cf-card)",
                }}
                tabIndex={checked ? 0 : -1}
                type="button"
              >
                <span aria-hidden="true" className="absolute inset-0">
                  {slide.media}
                </span>
                {/* The name sits on the card, over its own art, so the card
                    facing you says what it is without the caption. */}
                <span
                  aria-hidden="true"
                  className={cn(
                    "pointer-events-none absolute inset-x-0 bottom-0 h-2/5 bg-gradient-to-t from-black/80 via-black/45 to-transparent",
                    checked && "glass-media-scrim"
                  )}
                />
                <span className="absolute inset-x-4 bottom-3.5 text-[15px] leading-tight font-bold text-white">
                  {slide.title}
                </span>
                {slide.description ? (
                  <span className="sr-only">{slide.description}</span>
                ) : null}
                <span className="absolute top-3 right-3">
                  <AnimatedCheck checked={checked} className="size-6" />
                </span>
              </button>
            )
          })}
        </div>
      </div>

      {facing?.description ? (
        // Keyed on the card so the line fades rather than swapping words in
        // place while the deck is still turning.
        <p
          className="mx-auto min-h-10 max-w-[22rem] animate-in px-6 text-center text-sm leading-relaxed text-muted-foreground duration-300 fade-in"
          key={facing.id}
        >
          {facing.description}
        </p>
      ) : null}
    </div>
  )
}
