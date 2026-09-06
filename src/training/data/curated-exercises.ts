import records from "./exercise-metadata.curated.complete.json"
import mediaFingerprints from "./exercise-media-fingerprints.json"
import type { ExerciseSummary } from "../../types"
import type { ExerciseMetadata } from "../domain/types"
import { fingerprint } from "../numeric"

export const CURATION_VERSION = "2.0.0"

export type ExerciseReviewSource =
  "name" | "instructions" | "sampled_frames" | "video"
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
  sourceExerciseFingerprint: string
  mediaFingerprint?: string
  reviewedFrameNumbers?: number[]
  metadata: CuratedExerciseMetadataPatch
}

export type CurationFreshness = {
  sourceCurrent: boolean
  mediaCurrent: boolean | undefined
  sourceFingerprintMissing: boolean
  mediaFingerprintMissing: boolean
  staleSource: boolean
  staleMedia: boolean
}

const MEDIA_FINGERPRINTS = mediaFingerprints as Record<string, string>

export function sourceExerciseFingerprint(exercise: ExerciseSummary): string {
  return fingerprint({
    id: exercise.id,
    name: exercise.name,
    instructions: exercise.instructions,
    equipment: exercise.equipment,
    primaryMuscle: exercise.primaryMuscle,
    muscles: exercise.muscles,
    muscleWeights: exercise.muscleWeights,
  })
}

export function currentMediaFingerprint(
  exerciseId: string
): string | undefined {
  return MEDIA_FINGERPRINTS[exerciseId]
}

export function curationFreshness(
  review: CuratedExerciseReview,
  exercise: ExerciseSummary,
  mediaFingerprint = currentMediaFingerprint(exercise.id)
): CurationFreshness {
  const needsMedia =
    review.reviewedFrom.includes("sampled_frames") ||
    review.reviewedFrom.includes("video")
  const currentSource = sourceExerciseFingerprint(exercise)
  const sourceFingerprintMissing = !review.sourceExerciseFingerprint
  const mediaFingerprintMissing = needsMedia && !review.mediaFingerprint
  const sourceCurrent =
    !sourceFingerprintMissing &&
    review.sourceExerciseFingerprint === currentSource
  const mediaCurrent = needsMedia
    ? !mediaFingerprintMissing &&
      !!mediaFingerprint &&
      review.mediaFingerprint === mediaFingerprint
    : undefined
  return {
    sourceCurrent,
    mediaCurrent,
    sourceFingerprintMissing,
    mediaFingerprintMissing,
    staleSource: !sourceFingerprintMissing && !sourceCurrent,
    staleMedia:
      needsMedia && !mediaFingerprintMissing && mediaCurrent === false,
  }
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
