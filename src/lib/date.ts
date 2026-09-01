function parseISODate(iso: string) {
  const [year, month, day] = iso.split("-").map(Number)
  if (!year || !month || !day) return null
  return new Date(year, month - 1, day)
}

/** Local calendar date (no time-of-day/timezone shifting) as "YYYY-MM-DD". */
export function toISODate(date: Date) {
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60000)
  return local.toISOString().slice(0, 10)
}

export function formatDateShort(iso: string) {
  const date = parseISODate(iso)
  if (!date) return iso
  return date.toLocaleDateString(undefined, {
    weekday: "short",
    month: "short",
    day: "numeric",
  })
}

export function formatDateLong(iso: string) {
  const date = parseISODate(iso)
  if (!date) return iso
  return date.toLocaleDateString(undefined, {
    weekday: "long",
    month: "long",
    day: "numeric",
  })
}

export function formatMonthDay(iso: string) {
  const date = parseISODate(iso)
  if (!date) return iso
  return date.toLocaleDateString(undefined, {
    month: "long",
    day: "numeric",
  })
}

export function formatWeekdayShort(iso: string) {
  const date = parseISODate(iso)
  if (!date) return iso
  return date.toLocaleDateString(undefined, { weekday: "short" })
}

export function formatMonthShort(iso: string) {
  const date = parseISODate(iso)
  if (!date) return iso
  return date.toLocaleDateString(undefined, { month: "short" })
}
