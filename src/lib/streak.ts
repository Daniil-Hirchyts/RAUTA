import { toISODate } from "@/lib/date"
import type { Workout } from "@/store/use-workouts"

/** The strip is the week being lived in: Monday first, Sunday last. */
export const STREAK_DAYS = 7

export type StreakDay = {
  date: string
  workouts: number
  exercises: number
  /** Still ahead this week: drawn cold, and never counted as a day missed. */
  isFuture: boolean
  isToday: boolean
}

export type Streak = {
  week: StreakDay[]
  /** Consecutive trained days, counted back from today. */
  currentStreak: number
  longestStreak: number
  weekWorkouts: number
}

function startOfWeek(date: Date) {
  const start = new Date(date.getFullYear(), date.getMonth(), date.getDate())
  // Monday-first, so the strip reads the way a training week is planned.
  start.setDate(start.getDate() - ((start.getDay() + 6) % 7))
  return start
}

function shiftDays(iso: string, days: number) {
  const [year, month, day] = iso.split("-").map(Number)
  return toISODate(new Date(year, month - 1, day + days))
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
 * The run ending now. A day still being lived in has not broken anything yet:
 * with nothing logged today the count picks up from yesterday, so the streak
 * only lapses once a whole day has passed untrained.
 */
function currentRun(dates: Set<string>, todayISO: string) {
  let date = dates.has(todayISO) ? todayISO : shiftDays(todayISO, -1)
  let streak = 0
  while (dates.has(date)) {
    streak += 1
    date = shiftDays(date, -1)
  }
  return streak
}

function longestRun(dates: Set<string>) {
  let longest = 0
  let run = 0
  let previous: string | null = null
  for (const date of [...dates].sort()) {
    run = previous && shiftDays(previous, 1) === date ? run + 1 : 1
    previous = date
    longest = Math.max(longest, run)
  }
  return longest
}

export function buildStreak(workouts: Workout[], today = new Date()): Streak {
  const totals = dailyTotals(workouts)
  const trained = new Set(totals.keys())
  const todayISO = toISODate(today)
  const monday = toISODate(startOfWeek(today))

  const week = Array.from({ length: STREAK_DAYS }, (_, index): StreakDay => {
    const date = shiftDays(monday, index)
    const day = totals.get(date) ?? { workouts: 0, exercises: 0 }
    return {
      date,
      exercises: day.exercises,
      isFuture: date > todayISO,
      isToday: date === todayISO,
      workouts: day.workouts,
    }
  })

  return {
    currentStreak: currentRun(trained, todayISO),
    longestStreak: longestRun(trained),
    week,
    weekWorkouts: week.reduce((total, day) => total + day.workouts, 0),
  }
}
