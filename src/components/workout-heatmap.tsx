import { useEffect, useMemo, useRef, useState } from "react"
import { ChevronRight, Flame } from "lucide-react"

import { formatDateShort, formatWeekdayShort } from "@/lib/date"
import { triggerHaptic } from "@/lib/haptics"
import { buildHeatmap, HEATMAP_LEVELS, type HeatmapLevel } from "@/lib/heatmap"
import type { Workout } from "@/store/use-workouts"

/** Cell pitch. The square inside is smaller, so taps land on the gaps too. */
const CELL = 14

const LEVEL_FILL: Record<HeatmapLevel, string> = {
  0: "bg-white/[0.055]",
  1: "bg-[color-mix(in_oklch,var(--primary),var(--card)_72%)]",
  2: "bg-[color-mix(in_oklch,var(--primary),var(--card)_50%)]",
  3: "bg-[color-mix(in_oklch,var(--primary),var(--card)_26%)]",
  4: "bg-primary",
}

/** Mon/Wed/Fri only — three labels is enough to read the rows by. */
const LABELLED_WEEKDAYS = [0, 2, 4]

function countLabel(count: number, noun: string) {
  return `${count} ${noun}${count === 1 ? "" : "s"}`
}

/**
 * A year of training as a contribution matrix: one column per week, one cell
 * per day, shaded by how much work the day held. Tapping a cell reports it in
 * the caption underneath — the phone-sized stand-in for a hover tooltip.
 */
export function WorkoutHeatmap({
  onSelectWorkout,
  workouts,
}: {
  onSelectWorkout?: (workout: Workout) => void
  workouts: Workout[]
}) {
  const scrollerRef = useRef<HTMLDivElement>(null)
  const [selectedDate, setSelectedDate] = useState<string | null>(null)

  const {
    activeDays,
    currentStreak,
    longestStreak,
    months,
    totalWorkouts,
    weeks,
  } = useMemo(() => buildHeatmap(workouts), [workouts])

  // A year is wider than the screen and the interesting end is the recent
  // one, so the matrix opens parked on this week.
  useEffect(() => {
    const scroller = scrollerRef.current
    if (scroller) scroller.scrollLeft = scroller.scrollWidth
  }, [])

  const selectedWorkouts = selectedDate
    ? workouts.filter((workout) => workout.date === selectedDate)
    : []
  const selectedExercises = selectedWorkouts.reduce(
    (total, workout) => total + workout.exerciseIds.length,
    0
  )

  const selectDay = (date: string) => {
    triggerHaptic("selection")
    setSelectedDate((current) => (current === date ? null : date))
  }

  return (
    <section
      aria-label="Training consistency"
      className="mx-4 rounded-3xl border border-border bg-card/60 p-4"
      style={{ "--cell": `${CELL}px` } as React.CSSProperties}
    >
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-[11px] font-bold tracking-[0.14em] text-muted-foreground uppercase">
            Last 12 months
          </p>
          <p className="mt-1 text-[22px] leading-none font-black tracking-[-0.02em]">
            {totalWorkouts}
            <span className="ml-1.5 text-sm font-semibold text-muted-foreground">
              {totalWorkouts === 1 ? "workout" : "workouts"}
            </span>
          </p>
        </div>
        <div className="flex shrink-0 flex-col items-end gap-1">
          {currentStreak > 0 && (
            <p className="flex items-center gap-1 rounded-full border border-primary/25 bg-[color-mix(in_oklch,var(--card),var(--primary)_12%)] px-2.5 py-1 text-[13px] font-semibold text-primary tabular-nums">
              <Flame className="size-3.5" />
              {currentStreak} wk
            </p>
          )}
          {longestStreak > 0 && (
            <p className="text-[11px] font-medium text-muted-foreground tabular-nums">
              best {longestStreak} wk
            </p>
          )}
        </div>
      </div>

      <div className="mt-3.5 flex">
        {/* Outside the scroller: the day rows stay labelled at any scroll
            position. The top padding clears the month row beside it. */}
        <div
          aria-hidden="true"
          className="grid w-7 shrink-0 pt-4"
          style={{ gridTemplateRows: `repeat(7, var(--cell))` }}
        >
          {weeks[0].map((day, weekday) => (
            <span
              className="self-center pr-1.5 text-right text-[9px] leading-none text-muted-foreground"
              key={day.date}
            >
              {LABELLED_WEEKDAYS.includes(weekday)
                ? formatWeekdayShort(day.date)
                : ""}
            </span>
          ))}
        </div>

        <div
          className="-mr-4 min-w-0 [scrollbar-width:none] overflow-x-auto pr-4 [&::-webkit-scrollbar]:hidden"
          ref={scrollerRef}
        >
          <div className="w-max">
            <div
              className="mb-1 grid h-3"
              style={{
                gridTemplateColumns: `repeat(${weeks.length}, var(--cell))`,
              }}
            >
              {months.map((month) => (
                <span
                  className="text-[10px] leading-3 font-medium whitespace-nowrap text-muted-foreground"
                  key={`${month.label}-${month.weekIndex}`}
                  style={{ gridColumnStart: month.weekIndex + 1 }}
                >
                  {month.label}
                </span>
              ))}
            </div>

            <div
              className="grid grid-flow-col"
              data-testid="heatmap-grid"
              style={{
                gridAutoColumns: "var(--cell)",
                gridTemplateRows: `repeat(7, var(--cell))`,
              }}
            >
              {weeks.flat().map((day) =>
                day.isFuture ? (
                  <span aria-hidden="true" key={day.date} />
                ) : (
                  <button
                    aria-label={`${formatDateShort(day.date)}: ${
                      day.workouts === 0
                        ? "rest day"
                        : `${countLabel(day.workouts, "workout")}, ${countLabel(day.exercises, "exercise")}`
                    }`}
                    className="grid place-items-center p-[2px]"
                    key={day.date}
                    onClick={() => selectDay(day.date)}
                    type="button"
                  >
                    <span
                      className={`size-full rounded-xs transition-[box-shadow,transform] duration-150 ${LEVEL_FILL[day.level]} ${
                        selectedDate === day.date
                          ? "scale-110 ring-2 ring-foreground/70"
                          : day.isToday
                            ? "ring-1 ring-white/30"
                            : ""
                      }`}
                    />
                  </button>
                )
              )}
            </div>
          </div>
        </div>
      </div>

      <div className="mt-3 flex min-h-6 items-center justify-between gap-3">
        <output
          aria-live="polite"
          className="min-w-0 text-[13px] font-medium text-muted-foreground"
        >
          {!selectedDate ? (
            countLabel(activeDays, "active day")
          ) : selectedWorkouts.length === 0 ? (
            <span className="truncate">
              {formatDateShort(selectedDate)} · Rest day
            </span>
          ) : (
            <button
              className="flex items-center gap-0.5 text-foreground"
              disabled={!onSelectWorkout}
              onClick={() => onSelectWorkout?.(selectedWorkouts[0])}
              type="button"
            >
              <span className="truncate">
                {formatDateShort(selectedDate)} ·{" "}
                {countLabel(selectedExercises, "exercise")}
              </span>
              {onSelectWorkout && <ChevronRight className="size-4 shrink-0" />}
            </button>
          )}
        </output>

        <div
          aria-hidden="true"
          className="flex shrink-0 items-center gap-1 text-[10px] text-muted-foreground"
        >
          Less
          {HEATMAP_LEVELS.map((level) => (
            <span
              className={`size-2.5 rounded-xs ${LEVEL_FILL[level]}`}
              key={level}
            />
          ))}
          More
        </div>
      </div>
    </section>
  )
}
