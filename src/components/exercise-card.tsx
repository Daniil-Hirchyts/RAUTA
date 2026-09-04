import { useEffect, useRef } from "react"

import { AnimatedCheck } from "@/components/animated-check"
import { AppImage } from "@/components/app-image"
import { LikeButton } from "@/components/like-button"
import { triggerHaptic } from "@/lib/haptics"
import { isNative } from "@/lib/native"
import { cn } from "@/lib/utils"
import {
  EXERCISE_ANIMATION_FILTER_LIGHT,
  exerciseAnimation,
} from "@/lib/visuals"
import { useFavorites } from "@/store/use-favorites"
import type { ExerciseSummary } from "@/types"

const LONG_PRESS_MS = 500
const MOVE_TOLERANCE_PX = 10

export function ExerciseCard({
  exercise,
  index = 0,
  onOpenDetail,
  onToggleSelect,
  selected = false,
  selectMode = false,
}: {
  exercise: ExerciseSummary
  index?: number
  onOpenDetail: (exercise: ExerciseSummary) => void
  onToggleSelect: (id: string) => void
  selected?: boolean
  selectMode?: boolean
}) {
  const native = isNative()
  const isFavorite = useFavorites((state) =>
    state.favoriteIds.includes(exercise.id)
  )
  const toggleFavorite = useFavorites((state) => state.toggleFavorite)

  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const isLongPressRef = useRef(false)
  const startCoordsRef = useRef<{ x: number; y: number } | null>(null)

  const clearTimer = () => {
    if (timerRef.current) {
      clearTimeout(timerRef.current)
      timerRef.current = null
    }
  }

  useEffect(() => {
    return () => clearTimer()
  }, [])

  const handlePointerDown = (event: React.PointerEvent<HTMLButtonElement>) => {
    if (!selectMode) return
    if (event.button !== 0 && event.pointerType === "mouse") return

    clearTimer()
    isLongPressRef.current = false
    startCoordsRef.current = { x: event.clientX, y: event.clientY }

    timerRef.current = setTimeout(() => {
      isLongPressRef.current = true
      timerRef.current = null
      triggerHaptic("light")
      onOpenDetail(exercise)
    }, LONG_PRESS_MS)
  }

  const handlePointerMove = (event: React.PointerEvent<HTMLButtonElement>) => {
    if (!timerRef.current || !startCoordsRef.current) return
    const dx = event.clientX - startCoordsRef.current.x
    const dy = event.clientY - startCoordsRef.current.y
    if (Math.hypot(dx, dy) > MOVE_TOLERANCE_PX) {
      clearTimer()
    }
  }

  const handlePointerUp = () => {
    clearTimer()
  }

  const handlePointerCancel = () => {
    clearTimer()
  }

  const activate = () =>
    selectMode ? onToggleSelect(exercise.id) : onOpenDetail(exercise)

  const handleClick = (event: React.MouseEvent<HTMLButtonElement>) => {
    if (isLongPressRef.current) {
      isLongPressRef.current = false
      event.preventDefault()
      return
    }
    activate()
  }

  const handleContextMenu = (event: React.MouseEvent<HTMLButtonElement>) => {
    if (selectMode && isLongPressRef.current) {
      event.preventDefault()
    }
  }

  return (
    <article
      className={cn(
        "exercise-card t-stagger-line relative overflow-hidden rounded-3xl border bg-card shadow-sm shadow-black/10 transition-[border-color,box-shadow] duration-300 ease-[var(--ease-smooth-out)]",
        selectMode && selected
          ? "border-primary/75 shadow-[0_0_0_1px_color-mix(in_oklch,var(--primary)_30%,transparent)]"
          : "border-border"
      )}
      style={{ animationDelay: `${Math.min(index, 6) * 40}ms` }}
    >
      <button
        aria-label={
          selectMode
            ? `Select ${exercise.name}`
            : `View ${exercise.name} details`
        }
        aria-pressed={selectMode ? selected : undefined}
        className="interactive-spring block w-full cursor-pointer text-left"
        onClick={handleClick}
        onContextMenu={handleContextMenu}
        onPointerCancel={handlePointerCancel}
        onPointerDown={handlePointerDown}
        onPointerLeave={handlePointerCancel}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        type="button"
      >
        <div className="isolate aspect-square overflow-hidden bg-card">
          <AppImage
            alt={`${exercise.name} demonstration`}
            className={cn(
              "h-full w-full object-contain",
              !native && "mix-blend-screen"
            )}
            decoding="async"
            draggable={false}
            fetchPriority={native && index < 4 ? "high" : "low"}
            loading={native && index < 4 ? "eager" : "lazy"}
            recycleOffscreen={native}
            src={exerciseAnimation(exercise)}
            style={{ filter: EXERCISE_ANIMATION_FILTER_LIGHT }}
          />
        </div>
        {/* Fixed height (not content-driven) so every card is identical
            regardless of grid row or 1- vs 2-line exercise names. */}
        <div className="flex h-[4.5rem] items-center justify-center px-3.5">
          <h3 className="line-clamp-2 text-center text-base leading-snug font-semibold tracking-[-0.01em] capitalize">
            {exercise.name}
          </h3>
        </div>
      </button>

      <LikeButton
        aria-label={
          isFavorite
            ? `Remove ${exercise.name} from favorites`
            : `Add ${exercise.name} to favorites`
        }
        className="interactive-spring hit-target absolute top-5 left-5 grid size-8 place-items-center rounded-full border border-border bg-background text-primary active:bg-card/90"
        iconClassName="size-4"
        liked={isFavorite}
        onClick={(event) => {
          event.stopPropagation()
          triggerHaptic("selection")
          toggleFavorite(exercise.id)
        }}
      />

      <AnimatedCheck
        checked={selected}
        className={cn(
          "pointer-events-none absolute top-5 right-5 size-8 transition-[opacity,transform] duration-250 ease-[var(--ease-smooth-out)]",
          selectMode
            ? "scale-100 opacity-100"
            : "pointer-events-none scale-75 opacity-0"
        )}
      />
    </article>
  )
}
