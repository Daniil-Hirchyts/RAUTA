import records from "./exercise-metadata.curated.json"
import type { ExerciseMetadata } from "../domain/types"

export const CURATION_VERSION = "1.0.0"

export type ExerciseReviewSource = "name" | "instructions" | "video"
export type CuratedExerciseMetadataPatch = Partial<
  Omit<ExerciseMetadata, "exerciseId" | "provenance" | "ruleVersion">
>
export type CuratedExerciseReview = {
  exerciseId: string
  reviewedFrom: ExerciseReviewSource[]
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
