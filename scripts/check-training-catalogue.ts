import exercises from "../src/data/exercises.generated.json"
import {
  createExerciseIndex,
  plannerSupportsExercise,
  type ExerciseSummary,
} from "../src/training"
import {
  CORE_PROGRAMMING_FIELDS,
  curationFreshness,
  getCuratedExerciseReviews,
  isFullyCuratedReview,
} from "../src/training/data/curated-exercises"

const data = exercises as ExerciseSummary[]
const sourceIds = new Set(data.map((exercise) => exercise.id))
const reviews = getCuratedExerciseReviews()
const reviewsById = Object.groupBy(reviews, (review) => review.exerciseId)
const index = createExerciseIndex(data)
const issues: string[] = []

for (const exercise of data) {
  const matching = reviewsById[exercise.id] ?? []
  if (matching.length !== 1) {
    issues.push(`${exercise.id}: expected one review, found ${matching.length}`)
    continue
  }
  const review = matching[0]
  const freshness = curationFreshness(review, exercise)
  if (!isFullyCuratedReview(review)) issues.push(`${exercise.id}: partial review`)
  if (
    freshness.sourceFingerprintMissing ||
    freshness.mediaFingerprintMissing ||
    freshness.staleSource ||
    freshness.staleMedia
  )
    issues.push(`${exercise.id}: stale or missing review fingerprint`)
  if (
    !review.reviewedFrom.includes("name") ||
    !review.reviewedFrom.includes("instructions") ||
    (!review.reviewedFrom.includes("sampled_frames") &&
      !review.reviewedFrom.includes("video"))
  )
    issues.push(`${exercise.id}: incomplete evidence provenance`)
  if (!review.reviewedFrameNumbers?.length)
    issues.push(`${exercise.id}: missing reviewed frame numbers`)
  for (const field of CORE_PROGRAMMING_FIELDS)
    if (!Object.prototype.hasOwnProperty.call(review.metadata, field))
      issues.push(`${exercise.id}: core field is not explicit: ${field}`)

  const metadata = index.byId.get(exercise.id)?.metadata
  if (!metadata) {
    issues.push(`${exercise.id}: missing or invalid indexed metadata`)
    continue
  }
  if (metadata.reviewStatus !== "fully_reviewed")
    issues.push(`${exercise.id}: review status is ${metadata.reviewStatus}`)
  if (metadata.exerciseType === "unknown")
    issues.push(`${exercise.id}: unknown exercise type`)
  if (metadata.mechanics === "unknown")
    issues.push(`${exercise.id}: unknown mechanics`)
  if (metadata.laterality === "unknown")
    issues.push(`${exercise.id}: unknown laterality`)
  if (metadata.tracking === "unknown")
    issues.push(`${exercise.id}: unknown tracking`)
  if (metadata.skill === "unknown") issues.push(`${exercise.id}: unknown skill`)
  if (
    metadata.movementPatterns.length === 0 ||
    metadata.movementPatterns.includes("unknown")
  )
    issues.push(`${exercise.id}: unknown movement pattern`)
  if (
    metadata.automaticProgramming === "allowed" &&
    !plannerSupportsExercise(metadata)
  )
    issues.push(`${exercise.id}: allowed despite unsupported planner capability`)
  for (const relationship of ["familyId", "variantOf", "duplicateOf"] as const) {
    const target = metadata[relationship]
    if ((relationship === "variantOf" || relationship === "duplicateOf") && target)
      if (!sourceIds.has(target) || target === exercise.id)
        issues.push(`${exercise.id}: invalid ${relationship} target ${target}`)
  }
  const conflict = metadata.tags.some((tag) =>
    ["source_media_conflict", "source_equipment_conflict"].includes(tag)
  )
  const resolved = metadata.tags.some((tag) =>
    [
      "classification_media_preferred",
      "classification_text_preferred",
      "unusable_source_record",
    ].includes(tag)
  )
  if (conflict && !resolved)
    issues.push(`${exercise.id}: source conflict lacks terminal resolution`)
}

for (const review of reviews)
  if (!sourceIds.has(review.exerciseId))
    issues.push(`${review.exerciseId}: review has no source record`)
for (const issue of index.issues)
  issues.push(`index: ${issue.code} ${issue.path ?? ""}`.trim())

const result = {
  sourceRecords: data.length,
  reviewRecords: reviews.length,
  fullyReviewed: data.filter(
    (exercise) =>
      index.byId.get(exercise.id)?.metadata.reviewStatus === "fully_reviewed"
  ).length,
  issues: issues.length,
}
console.log(JSON.stringify(result))
if (issues.length) {
  console.error(issues.slice(0, 200).join("\n"))
  if (issues.length > 200) console.error(`... ${issues.length - 200} more issues`)
  process.exitCode = 1
}
