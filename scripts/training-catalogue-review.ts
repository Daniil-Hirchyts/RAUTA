import type { ExerciseMetadata, ExerciseSummary } from "../src/training"

export const SOURCE_CONFLICT_TAGS = [
  "source_media_conflict",
  "source_equipment_conflict",
] as const

export const TERMINAL_CONFLICT_RESOLUTION_TAGS = [
  "classification_media_preferred",
  "classification_text_preferred",
  "unusable_source_record",
] as const

export function normalizeDuplicateCandidateName(name: string): string {
  return name
    .toLowerCase()
    .replace(/\b(?:version\s+\d+|v\.?\s*\d+)\b/g, " ")
    .replace(/\((?:male|female|back pov|side pov|front pov)\)/g, " ")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
}

export function normalizeLegacyDuplicateCandidateName(name: string): string {
  return name
    .toLowerCase()
    .replace(/\([^)]*\)|v\.\s*\d+|version \d+/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
}

export function duplicateCandidateGroups(
  data: ExerciseSummary[],
  normalizer = normalizeDuplicateCandidateName
) {
  const groups = new Map<string, ExerciseSummary[]>()
  for (const exercise of data) {
    const key = normalizer(exercise.name)
    groups.set(key, [...(groups.get(key) ?? []), exercise])
  }
  return [...groups]
    .filter(([, members]) => members.length > 1)
    .map(([key, members]) => ({
      key,
      members: [...members].sort((a, b) => a.id.localeCompare(b.id)),
    }))
    .sort((a, b) => a.key.localeCompare(b.key))
}

export function hasTerminalConflictResolution(metadata: ExerciseMetadata): boolean {
  const hasConflict = metadata.tags.some((tag) =>
    SOURCE_CONFLICT_TAGS.includes(tag as (typeof SOURCE_CONFLICT_TAGS)[number])
  )
  return (
    !hasConflict ||
    metadata.tags.some((tag) =>
      TERMINAL_CONFLICT_RESOLUTION_TAGS.includes(
        tag as (typeof TERMINAL_CONFLICT_RESOLUTION_TAGS)[number]
      )
    )
  )
}

