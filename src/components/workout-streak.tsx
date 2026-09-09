import { formatDateShort, formatWeekdayShort } from "@/lib/date"
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

function dayLabel(day: StreakDay) {
  if (day.isFuture) return `${formatDateShort(day.date)}: still ahead`
  if (day.workouts === 0) return `${formatDateShort(day.date)}: rest day`
  return `${formatDateShort(day.date)}: ${countLabel(day.workouts, "workout")}, ${countLabel(day.exercises, "exercise")}`
}

/**
 * The training week as a row of flames, one per day, lit by the days that were
 * trained — and under it, the run those days add up to. Today's flame is the
 * tall one, so the strip is read from the day being lived in outwards.
 */
export function WorkoutStreak({
  onSelectWorkout: _onSelectWorkout,
  workouts,
}: {
  /** @deprecated Streak panel is display-only and no longer clickable */
  onSelectWorkout?: (workout: Workout) => void
  workouts: Workout[]
}) {
  const { currentStreak, week } = buildStreak(workouts)

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

      <div className="flex flex-col items-center justify-center text-center">
        <p className="text-[32px] leading-none font-black tracking-[-0.02em]">
          <span className="font-readout">{currentStreak}</span>
          <span className="ml-1.5 text-sm font-semibold text-muted-foreground">
            day streak
          </span>
        </p>
      </div>

      <ul className="mt-5 grid grid-cols-7 gap-1">
        {week.map((day) => {
          const lit = day.workouts > 0
          return (
            <li
              aria-label={dayLabel(day)}
              className="flex min-w-0 flex-col items-center gap-1.5"
              key={day.date}
            >
              <span className="flex h-13 min-[380px]:h-14 items-end justify-center">
                <Flame
                  className={cn(
                    "max-w-full transition-[height,width,filter] duration-300 ease-spring",
                    day.isToday
                      ? "h-13 w-10 min-[380px]:h-14 min-[380px]:w-[2.8rem]"
                      : "h-10 w-8 min-[380px]:h-11 min-[380px]:w-[2.2rem]",
                    lit &&
                      "[filter:drop-shadow(0_3px_10px_color-mix(in_oklch,var(--primary),transparent_50%))]",
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
                    : "text-muted-foreground"
                )}
              >
                {formatWeekdayShort(day.date)}
              </span>
            </li>
          )
        })}
      </ul>
    </section>
  )
}

