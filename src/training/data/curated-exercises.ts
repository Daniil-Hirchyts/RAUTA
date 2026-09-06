import records from "./exercise-metadata.curated.json"
import type { ExerciseMetadata } from "../domain/types"

export const CURATION_VERSION = "1.2.0"

export type ExerciseReviewSource =
  | "name"
  | "instructions"
  | "sampled_frames"
  | "video"
export type CuratedExerciseMetadataPatch = Partial<
  Omit<ExerciseMetadata, "exerciseId" | "provenance" | "ruleVersion">
>
export const CORE_PROGRAMMING_FIELDS = [
  "exerciseType",
  "movementPatterns",
  "mechanics",
  "laterality",
  "tracking",
  "requiredEquipment",
  "setRoles",
  "classificationConfidence",
  "skill",
  "setupSeconds",
  "automaticProgramming",
] as const
export type CoreProgrammingField = (typeof CORE_PROGRAMMING_FIELDS)[number]
export type CuratedExerciseReview = {
  exerciseId: string
  reviewedFrom: ExerciseReviewSource[]
  reviewedFields?: CoreProgrammingField[]
  metadata: CuratedExerciseMetadataPatch
}

const CURATED_REVIEWS = records as unknown as CuratedExerciseReview[]
const CURATED_BY_ID = new Map(
  CURATED_REVIEWS.map((record) => [record.exerciseId, record])
)

export function getCuratedExerciseReview(
  exerciseId: string
): CuratedExerciseReview | undefined {
  const review = CURATED_BY_ID.get(exerciseId)
  return review ? structuredClone(review) : undefined
}

export function getCuratedExerciseReviews(): CuratedExerciseReview[] {
  return structuredClone(CURATED_REVIEWS)
}

export function isFullyCuratedReview(review: CuratedExerciseReview): boolean {
  const fields = new Set(review.reviewedFields ?? [])
  return CORE_PROGRAMMING_FIELDS.every((field) => fields.has(field))
}
