import { formatMonthShort, toISODate } from "@/lib/date"
import type { Workout } from "@/store/use-workouts"

/** 53 weeks is the smallest window that always covers a full year. */
export const HEATMAP_WEEKS = 53
export const HEATMAP_LEVELS = [0, 1, 2, 3, 4] as const

export type HeatmapLevel = (typeof HEATMAP_LEVELS)[number]

/**
 * Shade thresholds, in exercises logged across the day. A day that holds a
 * workout is never left at level 0 — showing up is the thing the matrix is
 * there to record, and the exercise count only decides how loud it looks.
 */
const LEVEL_MIN_EXERCISES = [1, 4, 7, 10]

export type HeatmapDay = {
  date: string
  workouts: number
  exercises: number
  level: HeatmapLevel
  /** Padding at the end of the current week: rendered as a gap, not a rest day. */
  isFuture: boolean
  isToday: boolean
}

export type HeatmapMonth = {
  label: string
  weekIndex: number
}

export type Heatmap = {
  /** `HEATMAP_WEEKS` columns of 7 days, Monday first, oldest week first. */
  weeks: HeatmapDay[][]
  months: HeatmapMonth[]
  totalWorkouts: number
  activeDays: number
  /** Consecutive weeks with at least one workout, counted back from now. */
  currentStreak: number
  longestStreak: number
}

function startOfWeek(date: Date) {
  const start = new Date(date.getFullYear(), date.getMonth(), date.getDate())
  // Monday-first, so the matrix reads the way a training week is planned.
  start.setDate(start.getDate() - ((start.getDay() + 6) % 7))
  return start
}

function addDays(date: Date, days: number) {
  const next = new Date(date)
  next.setDate(next.getDate() + days)
  return next
}

function levelFor(exercises: number, workouts: number): HeatmapLevel {
  if (workouts === 0) return 0
  const reached = LEVEL_MIN_EXERCISES.filter((min) => exercises >= min).length
  return Math.max(1, reached) as HeatmapLevel
}

function dailyTotals(workouts: Workout[]) {
  const totals = new Map<string, { workouts: number; exercises: number }>()
  for (const workout of workouts) {
    const day = totals.get(workout.date) ?? { workouts: 0, exercises: 0 }
    day.workouts += 1
    day.exercises += workout.exerciseIds.length
    totals.set(workout.date, day)
  }
  return totals
}

/**
 * Month labels sit above the week where the month first appears. The first
 * column is skipped (it is a partial month with no room to its left) and so
 * are the last two, where a label would run past the edge of the matrix.
 */
function monthLabels(weeks: HeatmapDay[][]): HeatmapMonth[] {
  const months: HeatmapMonth[] = []
  let previous = ""
  weeks.forEach((week, weekIndex) => {
    const label = formatMonthShort(week[0].date)
    const changed = label !== previous
    previous = label
    if (!changed || weekIndex === 0 || weekIndex > weeks.length - 3) return
    months.push({ label, weekIndex })
  })
  return months
}

function streaks(weeks: HeatmapDay[][]) {
  const active = weeks.map((week) => week.some((day) => day.workouts > 0))

  let longestStreak = 0
  let run = 0
  for (const isActive of active) {
    run = isActive ? run + 1 : 0
    longestStreak = Math.max(longestStreak, run)
  }

  // The last column is the week being lived in: empty so far, it hasn't
  // broken the streak yet — it just hasn't extended it.
  let index = active.length - 1
  if (!active[index]) index -= 1
  let currentStreak = 0
  while (index >= 0 && active[index]) {
    currentStreak += 1
    index -= 1
  }

  return { currentStreak, longestStreak }
}

export function buildHeatmap(workouts: Workout[], today = new Date()): Heatmap {
  const totals = dailyTotals(workouts)
  const todayISO = toISODate(today)
  const firstDay = addDays(startOfWeek(today), -(HEATMAP_WEEKS - 1) * 7)

  const weeks: HeatmapDay[][] = []
  let totalWorkouts = 0
  let activeDays = 0

  for (let week = 0; week < HEATMAP_WEEKS; week += 1) {
    const days: HeatmapDay[] = []
    for (let weekday = 0; weekday < 7; weekday += 1) {
      const date = toISODate(addDays(firstDay, week * 7 + weekday))
      const isFuture = date > todayISO
      const day = (!isFuture && totals.get(date)) || {
        workouts: 0,
        exercises: 0,
      }
      totalWorkouts += day.workouts
      if (day.workouts > 0) activeDays += 1
      days.push({
        date,
        exercises: day.exercises,
        isFuture,
        isToday: date === todayISO,
        level: levelFor(day.exercises, day.workouts),
        workouts: day.workouts,
      })
    }
    weeks.push(days)
  }

  return {
    activeDays,
    months: monthLabels(weeks),
    totalWorkouts,
    weeks,
    ...streaks(weeks),
  }
}
