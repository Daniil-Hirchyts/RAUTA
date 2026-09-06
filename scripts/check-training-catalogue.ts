import exercises from "../src/data/exercises.generated.json"
import {
  createExerciseIndex,
  plannerSupportsExercise,
  type ExerciseSummary,
} from "../src/training"
import {
  CORE_PROGRAMMING_FIELDS,
  curationFreshness,
  currentMediaFingerprint,
  getCuratedExerciseReviews,
  isFullyCuratedReview,
} from "../src/training/data/curated-exercises"
import {
  duplicateCandidateGroups,
  hasTerminalConflictResolution,
} from "./training-catalogue-review"

const EXPECTED_SOURCE_RECORDS = 1324
const data = [...(exercises as ExerciseSummary[])].sort((a, b) =>
  a.id.localeCompare(b.id)
)
const sourceIds = new Set(data.map((exercise) => exercise.id))
const reviews = getCuratedExerciseReviews()
const reviewsById = Object.groupBy(reviews, (review) => review.exerciseId)
const index = createExerciseIndex(data)
const issues: string[] = []

let partiallyReviewed = 0
let stale = 0
let missingSourceFingerprints = 0
let missingMediaFingerprints = 0
let mediaMapMismatches = 0
let unknownType = 0
let unknownPattern = 0
let unknownMechanics = 0
let unknownLaterality = 0
let unknownTracking = 0
let unknownSkill = 0
let unresolvedSourceConflicts = 0
let allowedPlannerMismatch = 0
let relationshipErrors = 0
let reviewQueue = 0

if (data.length !== EXPECTED_SOURCE_RECORDS)
  issues.push(
    `source catalogue has ${data.length} records; expected ${EXPECTED_SOURCE_RECORDS}`
  )

for (const exercise of data) {
  const matching = reviewsById[exercise.id] ?? []
  if (matching.length !== 1) {
    issues.push(`${exercise.id}: expected one review, found ${matching.length}`)
    reviewQueue++
    continue
  }

  const review = matching[0]
  const freshness = curationFreshness(review, exercise)
  let queued = false
  const queue = () => {
    queued = true
  }

  if (!isFullyCuratedReview(review)) {
    partiallyReviewed++
    issues.push(`${exercise.id}: partial review`)
    queue()
  }
  if (freshness.sourceFingerprintMissing) {
    missingSourceFingerprints++
    issues.push(`${exercise.id}: missing source fingerprint`)
    queue()
  }
  if (freshness.mediaFingerprintMissing) {
    missingMediaFingerprints++
    issues.push(`${exercise.id}: missing media fingerprint`)
    queue()
  }
  if (freshness.staleSource || freshness.staleMedia) {
    stale++
    issues.push(`${exercise.id}: stale review fingerprint`)
    queue()
  }
  const currentMedia = currentMediaFingerprint(exercise.id)
  if (
    review.mediaFingerprint &&
    currentMedia &&
    review.mediaFingerprint !== currentMedia
  ) {
    mediaMapMismatches++
    queue()
  }
  if (
    !review.reviewedFrom.includes("name") ||
    !review.reviewedFrom.includes("instructions") ||
    (!review.reviewedFrom.includes("sampled_frames") &&
      !review.reviewedFrom.includes("video"))
  ) {
    issues.push(`${exercise.id}: incomplete evidence provenance`)
    queue()
  }
  if (!review.reviewedFrameNumbers?.length) {
    issues.push(`${exercise.id}: missing reviewed frame numbers`)
    queue()
  }
  for (const field of CORE_PROGRAMMING_FIELDS)
    if (!Object.prototype.hasOwnProperty.call(review.metadata, field)) {
      issues.push(`${exercise.id}: core field is not explicit: ${field}`)
      queue()
    }

  const metadata = index.byId.get(exercise.id)?.metadata
  if (!metadata) {
    issues.push(`${exercise.id}: missing or invalid indexed metadata`)
    queue()
    if (queued) reviewQueue++
    continue
  }
  if (metadata.reviewStatus !== "fully_reviewed") {
    issues.push(`${exercise.id}: review status is ${metadata.reviewStatus}`)
    queue()
  }
  if (metadata.provenance === "rule") {
    issues.push(`${exercise.id}: rule-only metadata remains`)
    queue()
  }
  if (metadata.exerciseType === "unknown") {
    unknownType++
    issues.push(`${exercise.id}: unknown exercise type`)
    queue()
  }
  if (
    metadata.movementPatterns.length === 0 ||
    metadata.movementPatterns.includes("unknown")
  ) {
    unknownPattern++
    issues.push(`${exercise.id}: unknown movement pattern`)
    queue()
  }
  if (metadata.mechanics === "unknown") {
    unknownMechanics++
    issues.push(`${exercise.id}: unknown mechanics`)
    queue()
  }
  if (metadata.laterality === "unknown") {
    unknownLaterality++
    issues.push(`${exercise.id}: unknown laterality`)
    queue()
  }
  if (metadata.tracking === "unknown") {
    unknownTracking++
    issues.push(`${exercise.id}: unknown tracking`)
    queue()
  }
  if (metadata.skill === "unknown") {
    unknownSkill++
    issues.push(`${exercise.id}: unknown skill`)
    queue()
  }
  if (
    metadata.automaticProgramming === "allowed" &&
    !plannerSupportsExercise(metadata)
  ) {
    allowedPlannerMismatch++
    issues.push(`${exercise.id}: allowed despite unsupported planner capability`)
  }
  for (const relationship of ["variantOf", "duplicateOf"] as const) {
    const target = metadata[relationship]
    if (target && (!sourceIds.has(target) || target === exercise.id)) {
      relationshipErrors++
      issues.push(`${exercise.id}: invalid ${relationship} target ${target}`)
    }
  }
  if (!hasTerminalConflictResolution(metadata)) {
    unresolvedSourceConflicts++
    issues.push(`${exercise.id}: source conflict lacks terminal resolution`)
    queue()
  }
  if (metadata.tags.includes("manual_review_required")) {
    issues.push(`${exercise.id}: manual review tag remains`)
    queue()
  }
  if (queued) reviewQueue++
}

for (const review of reviews)
  if (!sourceIds.has(review.exerciseId))
    issues.push(`${review.exerciseId}: review has no source record`)

for (const issue of index.issues) {
  relationshipErrors++
  issues.push(`index: ${issue.code} ${issue.path ?? ""}`.trim())
}

const unresolvedDuplicateGroups = duplicateCandidateGroups(data).filter((group) => {
  const explicitLinks = group.members.filter((member) => {
    const metadata = index.byId.get(member.id)?.metadata
    return Boolean(metadata?.variantOf || metadata?.duplicateOf)
  }).length
  return explicitLinks < group.members.length - 1
})
for (const group of unresolvedDuplicateGroups)
  issues.push(
    `unresolved duplicate candidate group ${group.key}: ${group.members
      .map((member) => member.id)
      .join(",")}`
  )

const fullyReviewed = data.filter(
  (exercise) =>
    index.byId.get(exercise.id)?.metadata.reviewStatus === "fully_reviewed"
).length
const ruleOnly = [...index.byId.values()].filter(
  (item) => item.metadata.provenance === "rule"
).length

const result = {
  sourceRecords: data.length,
  reviewRecords: reviews.length,
  fullyReviewed,
  partiallyReviewed,
  ruleOnly,
  stale,
  missingSourceFingerprints,
  missingMediaFingerprints,
  mediaMapMismatches,
  ordinaryUnknownType: unknownType,
  ordinaryUnknownPattern: unknownPattern,
  ordinaryUnknownMechanics: unknownMechanics,
  ordinaryUnknownLaterality: unknownLaterality,
  ordinaryUnknownTracking: unknownTracking,
  ordinaryUnknownSkill: unknownSkill,
  unresolvedSourceConflicts,
  unresolvedDuplicateGroups: unresolvedDuplicateGroups.length,
  reviewQueue,
  relationshipErrors,
  allowedPlannerMismatch,
  issues: issues.length,
}

const targetFailures = [
  data.length !== EXPECTED_SOURCE_RECORDS,
  reviews.length !== EXPECTED_SOURCE_RECORDS,
  fullyReviewed !== EXPECTED_SOURCE_RECORDS,
  partiallyReviewed !== 0,
  ruleOnly !== 0,
  stale !== 0,
  missingSourceFingerprints !== 0,
  missingMediaFingerprints !== 0,
  mediaMapMismatches !== 0,
  unknownType !== 0,
  unknownPattern !== 0,
  unknownMechanics !== 0,
  unknownLaterality !== 0,
  unknownTracking !== 0,
  unknownSkill !== 0,
  unresolvedSourceConflicts !== 0,
  unresolvedDuplicateGroups.length !== 0,
  reviewQueue !== 0,
  relationshipErrors !== 0,
  allowedPlannerMismatch !== 0,
]

console.log(JSON.stringify(result))
if (issues.length || targetFailures.some(Boolean)) {
  console.error(issues.slice(0, 200).join("\n"))
  if (issues.length > 200) console.error(`... ${issues.length - 200} more issues`)
  process.exitCode = 1
}
