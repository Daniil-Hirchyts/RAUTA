export const DAY_MS = 86_400_000
export const compareIds = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0)
export const clamp = (n: number, min = 0, max = 1) =>
  Math.min(max, Math.max(min, n))
export const mean = (values: number[]) =>
  values.length ? values.reduce((a, b) => a + b, 0) / values.length : 0
export const median = (values: number[]) => {
  const s = [...values].sort((a, b) => a - b)
  return s.length
    ? (s[Math.floor(s.length / 2)] + s[Math.floor((s.length - 1) / 2)]) / 2
    : undefined
}
export const round = (n: number) => Math.round(n * 1e6) / 1e6
const CONFIDENCE_RANK = { none: 0, low: 1, medium: 2, high: 3 } as const
export function confidenceAtLeast(
  value: keyof typeof CONFIDENCE_RANK,
  minimum: keyof typeof CONFIDENCE_RANK
) {
  return CONFIDENCE_RANK[value] >= CONFIDENCE_RANK[minimum]
}
export const addDays = (iso: string, days: number) =>
  new Date(Date.parse(iso) + days * DAY_MS).toISOString()
export function canonical(value: unknown): string {
  if (Array.isArray(value)) return "[" + value.map(canonical).join(",") + "]"
  if (value !== null && typeof value === "object")
    return (
      "{" +
      Object.entries(value)
        .filter(([, v]) => v !== undefined)
        .sort(([a], [b]) => compareIds(a, b))
        .map(([k, v]) => JSON.stringify(k) + ":" + canonical(v))
        .join(",") +
      "}"
    )
  return JSON.stringify(value) ?? "null"
}
/** Non-cryptographic reproducibility identifier, not a security or privacy primitive. */
export function fingerprint(value: unknown): string {
  let hash = 2166136261
  for (const c of canonical(value)) {
    hash ^= c.charCodeAt(0)
    hash = Math.imul(hash, 16777619)
  }
  return (hash >>> 0).toString(16).padStart(8, "0")
}
export const isRecord = (v: unknown): v is Record<string, unknown> =>
  v !== null && typeof v === "object" && !Array.isArray(v)
export const finite = (v: unknown, min = 0, max = 1e6): v is number =>
  typeof v === "number" && Number.isFinite(v) && v >= min && v <= max
export function validIso(v: unknown): v is string {
  if (
    typeof v !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z$/.test(v)
  )
    return false
  const time = Date.parse(v)
  return (
    Number.isFinite(time) &&
    new Date(time).toISOString() ===
      (v.length === 20 ? v.replace("Z", ".000Z") : v)
  )
}

export function deepFreeze<T>(value: T): T {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value)
    Object.values(value).forEach(deepFreeze)
  }
  return value
}
