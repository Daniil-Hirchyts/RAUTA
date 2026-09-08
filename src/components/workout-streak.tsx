import { useState } from "react"

import { formatDateShort, formatWeekdayShort } from "@/lib/date"
import { triggerHaptic } from "@/lib/haptics"
import { buildStreak, type StreakDay } from "@/lib/streak"
import { countLabel } from "@/lib/text"
import { cn } from "@/lib/utils"
import type { Workout } from "@/store/use-workouts"

/** The gradient every lit flame paints with, defined once for the strip. */
const FLAME_FILL = "workout-streak-flame"

/**
 * One flame: tip, notch and bulb in a single outline. The paler inner lobe and
 * the highlight across it are what stop the shape from reading as a flat
 * sticker, and they only appear on a day that was actually trained.
 */
function Flame({ className, lit }: { className?: string; lit: boolean }) {
  return (
    <svg
      aria-hidden="true"
      className={className}
      fill="none"
      focusable="false"
      viewBox="0 0 32 40"
    >
      <path
        className={lit ? undefined : "fill-white/[0.09]"}
        d="M16.6 1.6c.6 6.4 9.9 10.4 9.9 22.1a10.5 10.5 0 0 1-21 0c0-5.4 2.1-9 4.9-11.9.1 3.1 1.3 5.3 3.1 6.4 1.8-1.7 3-8.6 3.1-16.6Z"
        fill={lit ? `url(#${FLAME_FILL})` : undefined}
      />
      {lit && (
        <>
          <path
            d="M16.2 15.8c0 4 6.1 6.1 6.1 11a6.2 6.2 0 0 1-12.4 0c0-4.9 6.3-7 6.3-11Z"
            fill="white"
            fillOpacity="0.26"
          />
          <path
            d="M13.2 21.6c-1.2 1.6-1.8 3-1.9 4.6"
            stroke="white"
            strokeLinecap="round"
            strokeOpacity="0.55"
            strokeWidth="1.8"
          />
        </>
      )}
    </svg>
  )
}

/** What a day holds, in the caption's words. */
function dayDetail(day: StreakDay) {
  if (day.workouts === 0) return day.isFuture ? "Still ahead" : "Rest day"
  return countLabel(day.exercises, "exercise")
}

function dayLabel(day: StreakDay) {
  if (day.isFuture) return `${formatDateShort(day.date)}: still ahead`
  if (day.workouts === 0) return `${formatDateShort(day.date)}: rest day`
  return `${formatDateShort(day.date)}: ${countLabel(day.workouts, "workout")}, ${countLabel(day.exercises, "exercise")}`
}

/**
 * The training week as a row of flames, one per day, lit by the days that were
 * trained — and under it, the run those days add up to. Today's flame is the
 * tall one, so the strip is read from the day being lived in outwards.
 *
 * Tapping a lit day opens what was logged on it; the caption underneath names
 * whatever day is being pointed at, which is the phone-sized stand-in for a
 * hover tooltip.
 */
export function WorkoutStreak({
  onSelectWorkout,
  workouts,
}: {
  onSelectWorkout?: (workout: Workout) => void
  workouts: Workout[]
}) {
  const [selectedDate, setSelectedDate] = useState<string | null>(null)
  const { currentStreak, longestStreak, week, weekWorkouts } =
    buildStreak(workouts)

  const selectDay = (date: string) => {
    triggerHaptic("selection")
    setSelectedDate((current) => (current === date ? null : date))
  }

  const selected = week.find((day) => day.date === selectedDate) ?? null
  const selectedWorkout = selected
    ? workouts.find((workout) => workout.date === selected.date)
    : undefined

  return (
    <section
      aria-label="Training streak"
      className="content-glow content-glow--subtle mx-(--app-content-inset) rounded-3xl border border-border bg-card/60 px-4 py-4"
    >
      {/* The gradient the lit flames paint with, ahead of the first one
          that references it. */}
      <svg aria-hidden="true" className="absolute h-0 w-0" focusable="false">
        <defs>
          <linearGradient id={FLAME_FILL} x1="0" x2="0" y1="0" y2="1">
            <stop
              offset="0"
              style={{ stopColor: "var(--primary-gradient-start)" }}
            />
            <stop
              offset="1"
              style={{ stopColor: "var(--primary-gradient-end)" }}
            />
          </linearGradient>
        </defs>
      </svg>

      <div className="flex items-baseline justify-between gap-3">
        <p className="text-[11px] font-bold tracking-[0.14em] text-muted-foreground uppercase">
          This week
        </p>
        <p className="text-[11px] font-medium text-muted-foreground tabular-nums">
          {longestStreak > 0
            ? `best ${countLabel(longestStreak, "day")}`
            : countLabel(weekWorkouts, "workout")}
        </p>
      </div>

      <ul className="mt-4 grid grid-cols-7 gap-1">
        {week.map((day) => {
          const lit = day.workouts > 0
          const isSelected = day.date === selectedDate
          return (
            <li className="min-w-0" key={day.date}>
              <button
                aria-label={dayLabel(day)}
                aria-pressed={isSelected}
                className="flex w-full flex-col items-center gap-1.5"
                onClick={() => selectDay(day.date)}
                type="button"
              >
                <span className="flex h-11 items-end justify-center">
                  <Flame
                    className={cn(
                      "transition-[height,width,filter] duration-300 ease-spring",
                      day.isToday ? "h-11 w-[2.2rem]" : "h-9 w-7",
                      lit &&
                        "[filter:drop-shadow(0_2px_7px_color-mix(in_oklch,var(--primary),transparent_58%))]",
                      day.isFuture && "opacity-60"
                    )}
                    lit={lit}
                  />
                </span>
                <span
                  className={cn(
                    "rounded-full px-1.5 py-0.5 text-[10px] leading-4 font-semibold transition-colors",
                    day.isToday
                      ? "bg-primary text-primary-foreground"
                      : isSelected
                        ? "bg-white/12 text-foreground"
                        : "text-muted-foreground"
                  )}
                >
                  {formatWeekdayShort(day.date)}
                </span>
              </button>
            </li>
          )
        })}
      </ul>

      <output
        aria-live="polite"
        className="mt-4 flex min-h-9 flex-col items-center justify-center text-center"
      >
        {selected ? (
          <button
            // The two lines are separate elements with no whitespace between
            // them, so the name they would compute runs together: spell it.
            aria-label={`${formatDateShort(selected.date)}, ${dayDetail(selected)}`}
            className="flex flex-col items-center"
            disabled={!selectedWorkout || !onSelectWorkout}
            onClick={() =>
              selectedWorkout && onSelectWorkout?.(selectedWorkout)
            }
            type="button"
          >
            <span className="text-[17px] leading-tight font-bold tracking-[-0.01em]">
              {formatDateShort(selected.date)}
            </span>
            <span className="text-[13px] font-medium text-muted-foreground">
              {dayDetail(selected)}
            </span>
          </button>
        ) : (
          <>
            <p className="text-[30px] leading-none font-black tracking-[-0.02em]">
              <span className="font-readout">{currentStreak}</span>
              <span className="ml-1.5 text-sm font-semibold text-muted-foreground">
                day streak
              </span>
            </p>
            <p className="mt-1.5 text-[13px] font-medium text-muted-foreground">
              {currentStreak === 0
                ? "Train today to start one"
                : week.some((day) => day.isToday && day.workouts > 0)
                  ? "Kept alive today"
                  : "Train today to keep it"}
            </p>
          </>
        )}
      </output>
    </section>
  )
}
