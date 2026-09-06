import { writeFileSync } from "node:fs"
import exercises from "../src/data/exercises.generated.json"
import mediaFingerprints from "../src/training/data/exercise-media-fingerprints.json"
import existingCommon from "../src/training/data/exercise-metadata.curated.common.json"
import recordsJson from "../src/training/data/exercise-metadata.curated.complete.json"
import existingLegacy from "../src/training/data/exercise-metadata.curated.json"
import {
  CORE_PROGRAMMING_FIELDS,
  sourceExerciseFingerprint,
  type CuratedExerciseReview,
} from "../src/training/data/curated-exercises"
import type { ExerciseMetadata, ExerciseSummary } from "../src/training"
import {
  duplicateCandidateGroups,
  hasTerminalConflictResolution,
  normalizeLegacyDuplicateCandidateName,
} from "./training-catalogue-review"
import {
  REVIEWED_ALTERNATING_LATERALITY_IDS,
  REVIEWED_CHINUP_VERTICAL_PULL_IDS,
  REVIEWED_CUBAN_PRESS_IDS,
  REVIEWED_GRIP_QUALIFIER_IDS,
  REVIEWED_GRIP_QUALIFIER_ISOLATION_IDS,
  REVIEWED_HIP_ROTATION_IDS,
  REVIEWED_LEG_CURL_IDS,
  REVIEWED_METADATA_DECISIONS,
  REVIEWED_POWER_CLEAN_IDS,
  REVIEWED_POWER_JERK_IDS,
  REVIEWED_POWER_PUSH_PRESS_IDS,
  REVIEWED_POWER_SNATCH_IDS,
  REVIEWED_POWER_THRUSTER_IDS,
  REVIEWED_POWER_UNILATERAL_CLEAN_IDS,
  REVIEWED_POWER_UPPER_BODY_PLYO_PUSH_IDS,
  REVIEWED_REAR_DELT_RAISE_IDS,
  REVIEWED_RELATIONSHIP_DECISIONS,
  REVIEWED_SHOULDER_ROTATION_IDS,
  REVIEWED_TRUNK_CURL_IDS,
  REVIEWED_UNILATERAL_SHOULDER_ROTATION_IDS,
  REVIEWED_TRICEPS_KICKBACK_FAMILY_IDS,
  REVIEWED_TRICEPS_KICKBACK_IDS,
  REVIEWED_UPRIGHT_ROW_IDS,
  REVIEWED_VERTICAL_PRESS_IDS,
  REVIEWED_WRIST_EXTENSION_IDS,
  REVIEWED_WRIST_FLEXION_IDS,
} from "./training-catalogue-reviewed-decisions"

const data = [...(exercises as ExerciseSummary[])].sort((a, b) =>
  a.id.localeCompare(b.id)
)
const fingerprints = mediaFingerprints as Record<string, string>
const records = structuredClone(recordsJson) as CuratedExerciseReview[]
const byId = new Map(records.map((record) => [record.exerciseId, record]))

function mergeReviewedMetadata(
  record: CuratedExerciseReview,
  metadata: CuratedExerciseReview["metadata"]
) {
  let tags = [
    ...new Set([...(record.metadata.tags ?? []), ...(metadata.tags ?? [])]),
  ].filter((tag) => !["manual_review_required", "duplicate_candidate"].includes(tag))
  if (metadata.movementPatterns && metadata.movementPatterns.length < 2)
    tags = tags.filter((tag) => tag !== "multi_pattern")
  if (metadata.skill && metadata.skill !== "complex")
    tags = tags.filter((tag) => tag !== "complex_movement")
  record.metadata = { ...record.metadata, ...structuredClone(metadata), tags }
}

for (const prior of [
  ...(existingLegacy as CuratedExerciseReview[]),
  ...(existingCommon as CuratedExerciseReview[]),
]) {
  const record = byId.get(prior.exerciseId)
  if (!record) throw new Error(`Prior reviewed metadata has no record: ${prior.exerciseId}`)
  mergeReviewedMetadata(record, prior.metadata)
}

for (const [exerciseId, metadata] of Object.entries(REVIEWED_METADATA_DECISIONS)) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed metadata decision has no record: ${exerciseId}`)
  mergeReviewedMetadata(record, metadata)
}

for (const exerciseId of REVIEWED_GRIP_QUALIFIER_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed grip qualifier decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = record.metadata.movementPatterns?.filter(
    (pattern) => pattern !== "grip"
  )
  record.metadata.setRoles = record.metadata.setRoles?.filter(
    (role) => !(role.muscleId === "forearm" && role.role === "direct")
  )
}

for (const exerciseId of REVIEWED_GRIP_QUALIFIER_ISOLATION_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed grip mechanics decision has no record: ${exerciseId}`)
  record.metadata.mechanics = "isolation"
}

for (const exerciseId of REVIEWED_ALTERNATING_LATERALITY_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed alternating decision has no record: ${exerciseId}`)
  record.metadata.laterality = "alternating"
}

for (const exerciseId of REVIEWED_WRIST_FLEXION_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed wrist-flexion decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = ["wrist_flexion"]
  record.metadata.mechanics = "isolation"
  record.metadata.setRoles = [
    { muscleId: "forearm", role: "direct", provenance: "curated" },
  ]
  record.metadata.familyId = "forearm"
}

for (const exerciseId of REVIEWED_WRIST_EXTENSION_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed wrist-extension decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = ["wrist_extension"]
  record.metadata.mechanics = "isolation"
  record.metadata.setRoles = [
    { muscleId: "forearm", role: "direct", provenance: "curated" },
  ]
  record.metadata.familyId = "forearm"
}

for (const exerciseId of REVIEWED_LEG_CURL_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed leg-curl decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = ["knee_flexion"]
  record.metadata.mechanics = "isolation"
  record.metadata.setRoles = [
    { muscleId: "hamstring", role: "direct", provenance: "curated" },
  ]
  record.metadata.familyId = "leg_curl"
}

for (const exerciseId of REVIEWED_TRUNK_CURL_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed trunk-curl decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = ["trunk_extension"]
  record.metadata.mechanics = "isolation"
  record.metadata.setRoles = [
    { muscleId: "lower-back", role: "direct", provenance: "curated" },
    { muscleId: "gluteal", role: "indirect", provenance: "curated" },
    { muscleId: "hamstring", role: "indirect", provenance: "curated" },
  ]
  record.metadata.familyId = "back_extension"
}

for (const exerciseId of REVIEWED_HIP_ROTATION_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed hip-rotation decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = ["hip_rotation"]
  record.metadata.mechanics = "isolation"
  record.metadata.setRoles = [
    { muscleId: "gluteal", role: "direct", provenance: "curated" },
  ]
  record.metadata.familyId = "hip_rotation"
}

for (const exerciseId of REVIEWED_SHOULDER_ROTATION_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed shoulder-rotation decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = ["shoulder_rotation"]
  record.metadata.mechanics = "isolation"
  record.metadata.setRoles = [
    { muscleId: "deltoids", role: "direct", provenance: "curated" },
  ]
  record.metadata.familyId = "shoulder_rotation"
}

for (const exerciseId of REVIEWED_UNILATERAL_SHOULDER_ROTATION_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed unilateral shoulder-rotation decision has no record: ${exerciseId}`)
  record.metadata.laterality = "unilateral"
}

for (const exerciseId of REVIEWED_CHINUP_VERTICAL_PULL_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed chin-up decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = ["vertical_pull"]
  record.metadata.mechanics = "compound"
  record.metadata.setRoles = [
    { muscleId: "upper-back", role: "direct", provenance: "curated" },
    { muscleId: "biceps", role: "indirect", provenance: "curated" },
    { muscleId: "forearm", role: "incidental", provenance: "curated" },
  ]
  record.metadata.familyId = "pull_up"
}

for (const exerciseId of REVIEWED_UPRIGHT_ROW_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed upright-row decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = ["shoulder_abduction"]
  record.metadata.mechanics = "compound"
  record.metadata.setRoles = [
    { muscleId: "deltoids", role: "direct", provenance: "curated" },
    { muscleId: "trapezius", role: "direct", provenance: "curated" },
    { muscleId: "biceps", role: "incidental", provenance: "curated" },
  ]
  record.metadata.familyId = "upright_row"
}

for (const exerciseId of REVIEWED_VERTICAL_PRESS_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed vertical-press decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = ["vertical_push"]
  record.metadata.mechanics = "compound"
  record.metadata.setRoles = [
    { muscleId: "deltoids", role: "direct", provenance: "curated" },
    { muscleId: "triceps", role: "indirect", provenance: "curated" },
  ]
  record.metadata.familyId = "shoulder_press"
}

for (const exerciseId of REVIEWED_CUBAN_PRESS_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed Cuban-press decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = ["shoulder_rotation", "vertical_push"]
  record.metadata.mechanics = "compound"
  record.metadata.setRoles = [
    { muscleId: "deltoids", role: "direct", provenance: "curated" },
    { muscleId: "triceps", role: "indirect", provenance: "curated" },
    { muscleId: "upper-back", role: "indirect", provenance: "curated" },
  ]
  record.metadata.familyId = "cuban_press"
}

for (const exerciseId of REVIEWED_TRICEPS_KICKBACK_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed triceps-kickback decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = ["elbow_extension"]
  record.metadata.mechanics = "isolation"
  record.metadata.setRoles = [
    { muscleId: "triceps", role: "direct", provenance: "curated" },
  ]
  record.metadata.familyId = "triceps_kickback"
}

for (const exerciseId of REVIEWED_TRICEPS_KICKBACK_FAMILY_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed triceps-kickback family decision has no record: ${exerciseId}`)
  record.metadata.familyId = "triceps_kickback"
}

for (const exerciseId of REVIEWED_REAR_DELT_RAISE_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed rear-delt raise decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = ["shoulder_abduction"]
  record.metadata.mechanics = "isolation"
  record.metadata.setRoles = [
    { muscleId: "deltoids", role: "direct", provenance: "curated" },
    { muscleId: "upper-back", role: "indirect", provenance: "curated" },
    { muscleId: "trapezius", role: "indirect", provenance: "curated" },
  ]
  record.metadata.familyId = "rear_delt_fly"
}

for (const exerciseId of REVIEWED_POWER_UPPER_BODY_PLYO_PUSH_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed plyometric push decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = ["horizontal_push"]
  record.metadata.mechanics = "compound"
  record.metadata.setRoles = [
    { muscleId: "chest", role: "direct", provenance: "curated" },
    { muscleId: "deltoids", role: "indirect", provenance: "curated" },
    { muscleId: "triceps", role: "indirect", provenance: "curated" },
  ]
  record.metadata.familyId = "push_up"
}

for (const exerciseId of REVIEWED_POWER_CLEAN_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed clean decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = ["hinge", "whole_body"]
  record.metadata.mechanics = "compound"
  record.metadata.setRoles = [
    { muscleId: "gluteal", role: "direct", provenance: "curated" },
    { muscleId: "hamstring", role: "direct", provenance: "curated" },
    { muscleId: "quadriceps", role: "direct", provenance: "curated" },
    { muscleId: "upper-back", role: "indirect", provenance: "curated" },
    { muscleId: "forearm", role: "incidental", provenance: "curated" },
  ]
  record.metadata.familyId = "clean"
}

for (const exerciseId of REVIEWED_POWER_UNILATERAL_CLEAN_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed unilateral clean decision has no record: ${exerciseId}`)
  record.metadata.laterality = "unilateral"
}

for (const exerciseId of REVIEWED_POWER_SNATCH_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed snatch decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = ["hinge", "whole_body"]
  record.metadata.mechanics = "compound"
  record.metadata.setRoles = [
    { muscleId: "deltoids", role: "direct", provenance: "curated" },
    { muscleId: "gluteal", role: "direct", provenance: "curated" },
    { muscleId: "hamstring", role: "direct", provenance: "curated" },
    { muscleId: "quadriceps", role: "direct", provenance: "curated" },
    { muscleId: "upper-back", role: "indirect", provenance: "curated" },
    { muscleId: "forearm", role: "incidental", provenance: "curated" },
  ]
  record.metadata.familyId = "snatch"
}

for (const exerciseId of REVIEWED_POWER_JERK_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed jerk decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = ["vertical_push", "whole_body"]
  record.metadata.mechanics = "compound"
  record.metadata.setRoles = [
    { muscleId: "deltoids", role: "direct", provenance: "curated" },
    { muscleId: "gluteal", role: "direct", provenance: "curated" },
    { muscleId: "quadriceps", role: "direct", provenance: "curated" },
    { muscleId: "triceps", role: "direct", provenance: "curated" },
    { muscleId: "abs", role: "incidental", provenance: "curated" },
  ]
  record.metadata.familyId = "jerk"
}

for (const exerciseId of REVIEWED_POWER_PUSH_PRESS_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed push-press decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = ["vertical_push", "whole_body"]
  record.metadata.mechanics = "compound"
  record.metadata.setRoles = [
    { muscleId: "deltoids", role: "direct", provenance: "curated" },
    { muscleId: "gluteal", role: "direct", provenance: "curated" },
    { muscleId: "quadriceps", role: "direct", provenance: "curated" },
    { muscleId: "triceps", role: "direct", provenance: "curated" },
    { muscleId: "abs", role: "incidental", provenance: "curated" },
  ]
  record.metadata.familyId = "push_press"
}

for (const exerciseId of REVIEWED_POWER_THRUSTER_IDS) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed thruster decision has no record: ${exerciseId}`)
  record.metadata.movementPatterns = ["squat", "vertical_push", "whole_body"]
  record.metadata.mechanics = "compound"
  record.metadata.setRoles = [
    { muscleId: "deltoids", role: "direct", provenance: "curated" },
    { muscleId: "gluteal", role: "direct", provenance: "curated" },
    { muscleId: "hamstring", role: "indirect", provenance: "curated" },
    { muscleId: "quadriceps", role: "direct", provenance: "curated" },
    { muscleId: "triceps", role: "direct", provenance: "curated" },
  ]
  record.metadata.familyId = "thruster"
}

for (const record of records) {
  let tags = record.metadata.tags ?? []
  if ((record.metadata.movementPatterns?.length ?? 0) < 2)
    tags = tags.filter((tag) => tag !== "multi_pattern")
  if (record.metadata.skill !== "complex")
    tags = tags.filter((tag) => tag !== "complex_movement")
  record.metadata.tags = [...new Set(tags)].sort()
}

for (const [exerciseId, decision] of Object.entries(REVIEWED_RELATIONSHIP_DECISIONS)) {
  const record = byId.get(exerciseId)
  if (!record) throw new Error(`Reviewed relationship decision has no record: ${exerciseId}`)
  if (decision.clearVariantOf) delete record.metadata.variantOf
  if (decision.clearDuplicateOf) delete record.metadata.duplicateOf
  if (decision.variantOf) record.metadata.variantOf = decision.variantOf
  if (decision.duplicateOf) record.metadata.duplicateOf = decision.duplicateOf
}

const sourceIds = new Set(data.map((exercise) => exercise.id))
if (records.length !== data.length)
  throw new Error(`Expected ${data.length} explicit reviews, found ${records.length}`)
if (byId.size !== records.length) throw new Error("Duplicate curated review IDs")

for (const exercise of data) {
  const review = byId.get(exercise.id)
  if (!review) throw new Error(`Missing explicit curated review: ${exercise.id}`)
  if (review.sourceExerciseFingerprint !== sourceExerciseFingerprint(exercise))
    throw new Error(`Stale source fingerprint: ${exercise.id}`)
  if (review.mediaFingerprint !== fingerprints[exercise.id])
    throw new Error(`Stale or missing media fingerprint: ${exercise.id}`)
  if (!review.reviewedFrom.includes("name") || !review.reviewedFrom.includes("instructions"))
    throw new Error(`Incomplete text review provenance: ${exercise.id}`)
  if (!review.reviewedFrom.includes("video") && !review.reviewedFrom.includes("sampled_frames"))
    throw new Error(`Incomplete visual review provenance: ${exercise.id}`)
  if (!review.reviewedFrameNumbers?.length)
    throw new Error(`Missing reviewed frame numbers: ${exercise.id}`)
  for (const field of CORE_PROGRAMMING_FIELDS)
    if (!Object.prototype.hasOwnProperty.call(review.metadata, field))
      throw new Error(`${exercise.id}: core field is not explicit: ${field}`)
  if (!hasTerminalConflictResolution(review.metadata as ExerciseMetadata))
    throw new Error(`${exercise.id}: source conflict lacks terminal resolution`)
  for (const relationship of [review.metadata.variantOf, review.metadata.duplicateOf])
    if (relationship && (!sourceIds.has(relationship) || relationship === exercise.id))
      throw new Error(`${exercise.id}: invalid relationship target ${relationship}`)
}

const currentGroups = duplicateCandidateGroups(data)
for (const group of currentGroups) {
  const explicitLinks = group.members.filter((member) => {
    const metadata = byId.get(member.id)!.metadata
    return Boolean(metadata.variantOf || metadata.duplicateOf)
  }).length
  if (explicitLinks < group.members.length - 1)
    throw new Error(
      `Unresolved duplicate candidate group ${group.key}: ${group.members
        .map((member) => member.id)
        .join(",")}`
    )
}

const legacyGroups = duplicateCandidateGroups(
  data,
  normalizeLegacyDuplicateCandidateName
)
for (const group of legacyGroups)
  for (const member of group.members)
    if (!byId.get(member.id)!.metadata.tags?.includes("near_duplicate_group_reviewed"))
      throw new Error(`Legacy duplicate group review is not encoded: ${member.id}`)

const sorted = [...records].sort((a, b) => a.exerciseId.localeCompare(b.exerciseId))
writeFileSync(
  "src/training/data/exercise-metadata.curated.complete.json",
  JSON.stringify(sorted, null, 2) + "\n"
)
console.log(
  JSON.stringify({
    records: sorted.length,
    currentDuplicateCandidateGroups: currentGroups.length,
    legacyDuplicateGroupsReviewed: legacyGroups.length,
    unresolvedDuplicateGroups: 0,
  })
)
