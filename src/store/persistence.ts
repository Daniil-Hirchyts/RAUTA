export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

export function validUniqueStrings(
  value: unknown,
  isValid: (item: string) => boolean
) {
  if (!Array.isArray(value)) return []

  return [
    ...new Set(
      value.filter(
        (item): item is string => typeof item === "string" && isValid(item)
      )
    ),
  ]
}

export function validString(value: unknown, fallback = "") {
  return typeof value === "string" ? value : fallback
}
