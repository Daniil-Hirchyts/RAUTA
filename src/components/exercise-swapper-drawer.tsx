import { useMemo, useState } from "react"

import { Drawer, DrawerContent, DrawerTitle } from "@/components/ui/drawer"
import { FULL_HEIGHT_DRAWER_STYLE } from "@/components/ui/drawer-style"
import { findExerciseAlternatives } from "@/lib/exercises"
import { titleCase } from "@/lib/text"
import {
  EXERCISE_ANIMATION_FILTER_LIGHT,
  exerciseAnimation,
} from "@/lib/visuals"
import type { ExerciseSummary } from "@/types"

// Past this many alternatives the sheet is mostly a scrolling list, and a
// swap is a comparison — so it takes the whole screen instead of asking for
// the choice through a letterbox. A handful still reads better as a sheet
// with the workout visible behind it.
const FULL_SCREEN_FROM = 5

export function ExerciseSwapperDrawer({
  excludedExerciseIds,
  exercise,
  onOpenChange,
  onSwap,
  open,
}: {
  excludedExerciseIds: string[]
  exercise: ExerciseSummary | null
  onOpenChange: (open: boolean) => void
  onSwap: (replacement: ExerciseSummary) => void
  open: boolean
}) {
  const [equipment, setEquipment] = useState<string | null>(null)
  const alternatives = useMemo(
    () =>
      exercise ? findExerciseAlternatives(exercise, excludedExerciseIds) : [],
    [excludedExerciseIds, exercise]
  )
  const equipmentOptions = useMemo(
    () => [...new Set(alternatives.map((item) => item.equipment))],
    [alternatives]
  )
  const visibleAlternatives = equipment
    ? alternatives.filter((item) => item.equipment === equipment)
    : alternatives

  if (!exercise) return null

  // Measured on everything available rather than what the equipment filter
  // leaves, so narrowing the list does not make the sheet jump.
  const fullScreen = alternatives.length >= FULL_SCREEN_FROM

  return (
    <Drawer
      onOpenChange={(nextOpen) => {
        if (!nextOpen) setEquipment(null)
        onOpenChange(nextOpen)
      }}
      open={open}
      swipeDirection="down"
    >
      <DrawerContent
        className="mx-auto max-w-[430px] [--drawer-height:min(82vh,44rem)] [--drawer-inset:0px]"
        style={fullScreen ? FULL_HEIGHT_DRAWER_STYLE : undefined}
      >
        <div className="flex min-h-0 flex-1 flex-col pt-16">
          <div className="shrink-0 px-5">
            <DrawerTitle className="text-2xl font-black tracking-[-0.025em]">
              Find alternative
            </DrawerTitle>
            <p className="mt-1 text-sm text-muted-foreground">
              Same muscles, different equipment.
            </p>

            <div className="mt-4 flex items-center gap-3 rounded-2xl border border-border bg-card p-3">
              <div className="isolate size-16 shrink-0 overflow-hidden rounded-2xl bg-[#111113]">
                <img
                  alt=""
                  className="h-full w-full object-contain mix-blend-screen"
                  draggable={false}
                  src={exerciseAnimation(exercise)}
                  style={{ filter: EXERCISE_ANIMATION_FILTER_LIGHT }}
                />
              </div>
              <div className="min-w-0 flex-1">
                <p className="line-clamp-2 font-semibold capitalize">
                  {exercise.name}
                </p>
                <div className="mt-1 flex items-center gap-2 text-xs">
                  <span className="text-muted-foreground">
                    {titleCase(exercise.equipment)}
                  </span>
                  <span className="rounded-full bg-primary/15 px-2 py-0.5 font-bold text-primary">
                    Busy
                  </span>
                </div>
              </div>
            </div>

            {equipmentOptions.length > 1 && (
              <div className="-mx-5 mt-4 flex gap-2 overflow-x-auto px-5 pb-1">
                <button
                  aria-pressed={equipment === null}
                  className={`shrink-0 rounded-full border px-3.5 py-2 text-sm font-semibold ${
                    equipment === null
                      ? "border-primary bg-primary text-primary-foreground"
                      : "border-border bg-card text-muted-foreground"
                  }`}
                  onClick={() => setEquipment(null)}
                  type="button"
                >
                  All available
                </button>
                {equipmentOptions.map((option) => (
                  <button
                    aria-pressed={equipment === option}
                    className={`shrink-0 rounded-full border px-3.5 py-2 text-sm font-semibold ${
                      equipment === option
                        ? "border-primary bg-primary text-primary-foreground"
                        : "border-border bg-card text-muted-foreground"
                    }`}
                    key={option}
                    onClick={() => setEquipment(option)}
                    type="button"
                  >
                    {titleCase(option)}
                  </button>
                ))}
              </div>
            )}
          </div>

          <div className="mt-4 min-h-0 flex-1 overflow-y-auto px-5 pb-[calc(1.25rem+env(safe-area-inset-bottom))]">
            {visibleAlternatives.length === 0 ? (
              <p className="rounded-2xl border border-border bg-card px-5 py-8 text-center text-sm leading-relaxed text-muted-foreground">
                No exact muscle match is available on different equipment.
              </p>
            ) : (
              <div className="space-y-2.5">
                {visibleAlternatives.map((alternative) => (
                  <button
                    aria-label={`Swap to ${alternative.name}`}
                    className="interactive-spring flex w-full items-center gap-3 overflow-hidden rounded-2xl border border-border bg-card p-2.5 text-left active:bg-card/90"
                    key={alternative.id}
                    onClick={() => onSwap(alternative)}
                    type="button"
                  >
                    <span className="isolate size-20 shrink-0 overflow-hidden rounded-2xl bg-[#111113]">
                      <img
                        alt=""
                        className="h-full w-full object-contain mix-blend-screen"
                        draggable={false}
                        loading="lazy"
                        src={exerciseAnimation(alternative)}
                        style={{ filter: EXERCISE_ANIMATION_FILTER_LIGHT }}
                      />
                    </span>
                    <span className="min-w-0 flex-1 py-1">
                      <span className="line-clamp-2 text-sm leading-snug font-semibold capitalize">
                        {alternative.name}
                      </span>
                      <span className="mt-1 block text-xs font-medium text-primary">
                        Use {titleCase(alternative.equipment)}
                      </span>
                    </span>
                    <span className="shrink-0 rounded-full border border-primary/35 px-3 py-1.5 text-xs font-bold text-primary">
                      Swap
                    </span>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
      </DrawerContent>
    </Drawer>
  )
}
