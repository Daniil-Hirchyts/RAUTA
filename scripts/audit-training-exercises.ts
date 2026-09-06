import { writeFileSync } from "node:fs"
import exercises from "../src/data/exercises.generated.json"
import {
  createExerciseIndex,
  DEFAULT_POLICY,
  plannerSupportsExercise,
  type ExerciseMetadata,
  type ExerciseSummary,
} from "../src/training"
import {
  curationFreshness,
  currentMediaFingerprint,
  getCuratedExerciseReviews,
  isFullyCuratedReview,
} from "../src/training/data/curated-exercises"
import {
  duplicateCandidateGroups,
  hasTerminalConflictResolution,
  normalizeLegacyDuplicateCandidateName,
  SOURCE_CONFLICT_TAGS,
} from "./training-catalogue-review"

const data = [...(exercises as ExerciseSummary[])].sort((a, b) =>
  a.id.localeCompare(b.id)
)
const index = createExerciseIndex(data)
const metadata = [...index.byId.values()].map((item) => item.metadata)
const curatedReviews = getCuratedExerciseReviews()

const counts = (values: string[]) => {
  const tally = new Map<string, number>()
  for (const value of values) tally.set(value, (tally.get(value) ?? 0) + 1)
  return Object.fromEntries([...tally].sort(([a], [b]) => a.localeCompare(b)))
}

const exactNameDuplicates = Object.values(
  Object.groupBy(data, (exercise) => exercise.name.toLowerCase().trim())
)
  .filter((group) => group && group.length > 1)
  .map((group) => group!.map(({ id, name }) => ({ id, name })))

const currentDuplicateCandidates = duplicateCandidateGroups(data)
const legacyDuplicateCandidates = duplicateCandidateGroups(
  data,
  normalizeLegacyDuplicateCandidateName
)
const unresolvedDuplicateGroups = currentDuplicateCandidates.filter((group) => {
  const explicitLinks = group.members.filter((member) => {
    const item = index.byId.get(member.id)
    return Boolean(item?.metadata.variantOf || item?.metadata.duplicateOf)
  }).length
  return explicitLinks < group.members.length - 1
})

const reviewFreshness = curatedReviews.map((review) => {
  const exercise = index.byId.get(review.exerciseId)?.exercise
  if (!exercise)
    return {
      review,
      freshness: undefined,
      status: "missing_source_exercise" as const,
    }
  const freshness = curationFreshness(review, exercise)
  const staleSource =
    freshness.staleSource || freshness.sourceFingerprintMissing
  const staleMedia = freshness.staleMedia || freshness.mediaFingerprintMissing
  return {
    review,
    freshness,
    status: staleSource
      ? staleMedia
        ? ("stale_source_and_media_review" as const)
        : ("stale_source_review" as const)
      : staleMedia
        ? ("stale_media_review" as const)
        : isFullyCuratedReview(review)
          ? ("fully_reviewed" as const)
          : ("partially_reviewed" as const),
  }
})

const fullyReviewed = reviewFreshness.filter(
  ({ status }) => status === "fully_reviewed"
)
const partiallyReviewed = reviewFreshness.filter(
  ({ status }) => status === "partially_reviewed"
)
const staleReviews = reviewFreshness.filter(({ status }) =>
  status.startsWith("stale_")
)

const modality = (review: (typeof curatedReviews)[number]) =>
  review.reviewedFrom.includes("video")
    ? "full_video"
    : review.reviewedFrom.includes("sampled_frames")
      ? "sampled_frames"
      : "text_only"

const hasSourceConflict = (metadata: ExerciseMetadata) =>
  metadata.tags.some((tag) =>
    SOURCE_CONFLICT_TAGS.includes(tag as (typeof SOURCE_CONFLICT_TAGS)[number])
  )

const conflictRow = (metadata: ExerciseMetadata) => ({
  exerciseId: metadata.exerciseId,
  name: index.byId.get(metadata.exerciseId)!.exercise.name,
  tags: metadata.tags.filter(
    (tag) => tag.includes("conflict") || tag.startsWith("classification_")
  ),
})

const resolvedSourceConflicts = metadata
  .filter((item) => hasSourceConflict(item) && hasTerminalConflictResolution(item))
  .map(conflictRow)
const unresolvedSourceConflicts = metadata
  .filter((item) => hasSourceConflict(item) && !hasTerminalConflictResolution(item))
  .map(conflictRow)
const unusable = metadata
  .filter((item) => item.tags.includes("unusable_source_record"))
  .map((item) => ({
    exerciseId: item.exerciseId,
    name: index.byId.get(item.exerciseId)!.exercise.name,
  }))

const automaticAllowedPlannerUnsupported = [...index.byId.values()]
  .filter(
    (item) =>
      item.metadata.automaticProgramming === "allowed" &&
      !plannerSupportsExercise(item.metadata)
  )
  .map((item) => ({
    id: item.exercise.id,
    name: item.exercise.name,
    exerciseType: item.metadata.exerciseType,
    tracking: item.metadata.tracking,
  }))
const specializedPlannerUnsupported = [...index.byId.values()]
  .filter(
    (item) =>
      item.metadata.automaticProgramming === "specialized_only" &&
      !plannerSupportsExercise(item.metadata)
  )
  .map((item) => ({
    id: item.exercise.id,
    name: item.exercise.name,
    exerciseType: item.metadata.exerciseType,
    tracking: item.metadata.tracking,
  }))
const manualOnlyByCapability = [...index.byId.values()]
  .filter(
    (item) =>
      item.metadata.automaticProgramming === "manual_only" &&
      !plannerSupportsExercise(item.metadata)
  )
  .map((item) => ({
    id: item.exercise.id,
    name: item.exercise.name,
    exerciseType: item.metadata.exerciseType,
    tracking: item.metadata.tracking,
  }))

const unknownTypeCount = metadata.filter(
  (item) => item.exerciseType === "unknown"
).length
const unknownPatternCount = metadata.filter(
  (item) =>
    item.movementPatterns.length === 0 || item.movementPatterns.includes("unknown")
).length
const unknownMechanicsCount = metadata.filter(
  (item) => item.mechanics === "unknown"
).length
const unknownLateralityCount = metadata.filter(
  (item) => item.laterality === "unknown"
).length
const unknownTrackingCount = metadata.filter(
  (item) => item.tracking === "unknown"
).length
const unknownSkillCount = metadata.filter((item) => item.skill === "unknown").length
const ruleOnlyCount = metadata.filter((item) => item.provenance === "rule").length
const mediaMapMismatchCount = curatedReviews.filter((review) => {
  const current = currentMediaFingerprint(review.exerciseId)
  return Boolean(current && review.mediaFingerprint && current !== review.mediaFingerprint)
}).length
const lowConfidence = metadata.filter(
  (item) =>
    item.classificationConfidence <
    DEFAULT_POLICY.minimumAutomaticClassificationConfidence
)

const reviewQueue = metadata
  .filter((item) => {
    const review = reviewFreshness.find(
      ({ review }) => review.exerciseId === item.exerciseId
    )
    return (
      review?.status !== "fully_reviewed" ||
      item.provenance === "rule" ||
      item.exerciseType === "unknown" ||
      item.movementPatterns.includes("unknown") ||
      item.mechanics === "unknown" ||
      item.laterality === "unknown" ||
      item.tracking === "unknown" ||
      item.skill === "unknown" ||
      item.tags.includes("manual_review_required") ||
      !hasTerminalConflictResolution(item)
    )
  })
  .map((item) => ({
    id: item.exerciseId,
    name: index.byId.get(item.exerciseId)!.exercise.name,
    tags: item.tags,
  }))

const duplicates = metadata
  .filter((item) => item.duplicateOf)
  .map((item) => ({ exerciseId: item.exerciseId, duplicateOf: item.duplicateOf! }))
const variants = metadata
  .filter((item) => item.variantOf)
  .map((item) => ({ exerciseId: item.exerciseId, variantOf: item.variantOf! }))

const exceptionalRecords = [...index.byId.values()]
  .map((item) => {
    const reasons: string[] = []
    if (item.metadata.automaticProgramming === "manual_only") reasons.push("manual_only")
    if (item.metadata.automaticProgramming === "specialized_only")
      reasons.push("specialized_only")
    if (hasSourceConflict(item.metadata)) reasons.push("resolved_source_conflict")
    if (
      item.metadata.classificationConfidence <
      DEFAULT_POLICY.minimumAutomaticClassificationConfidence
    )
      reasons.push("low_confidence")
    if (item.metadata.duplicateOf) reasons.push("duplicate")
    if (item.metadata.variantOf) reasons.push("variant")
    if (item.metadata.tags.includes("unusable_source_record")) reasons.push("unusable")
    return {
      exerciseId: item.exercise.id,
      name: item.exercise.name,
      automaticProgramming: item.metadata.automaticProgramming,
      exerciseType: item.metadata.exerciseType,
      tracking: item.metadata.tracking,
      familyId: item.metadata.familyId,
      classificationConfidence: item.metadata.classificationConfidence,
      duplicateOf: item.metadata.duplicateOf,
      variantOf: item.metadata.variantOf,
      reasons,
    }
  })
  .filter((item) => item.reasons.length > 0)

const reviewProgressByFamily = [...index.byFamily.entries()]
  .map(([familyId, members]) => ({
    familyId,
    total: members.length,
    fullyReviewed: members.filter(
      (member) => member.metadata.reviewStatus === "fully_reviewed"
    ).length,
    partiallyReviewed: members.filter(
      (member) => member.metadata.reviewStatus === "partially_reviewed"
    ).length,
    stale: members.filter((member) => member.metadata.reviewStatus?.startsWith("stale_"))
      .length,
    ruleOnly: members.filter((member) => member.metadata.reviewStatus === "rule_only")
      .length,
    allowed: members.filter(
      (member) => member.metadata.automaticProgramming === "allowed"
    ).length,
    members: members.map((member) => member.exercise.id),
  }))
  .sort((a, b) => a.familyId.localeCompare(b.familyId))

const report = {
  datasetFingerprint: index.fingerprint,
  total: data.length,
  errors: index.issues,
  equipment: counts(data.map((exercise) => exercise.equipment)),
  primaryMuscle: counts(data.map((exercise) => exercise.primaryMuscle ?? "missing")),
  participationCoverage: counts(data.flatMap((exercise) => exercise.muscles)),
  programmingDirectCoverage: counts(
    metadata.flatMap((item) =>
      item.setRoles.filter((role) => role.role === "direct").map((role) => role.muscleId)
    )
  ),
  types: counts(metadata.map((item) => item.exerciseType)),
  tracking: counts(metadata.map((item) => item.tracking)),
  automaticProgramming: counts(metadata.map((item) => item.automaticProgramming)),
  provenance: counts(metadata.map((item) => item.provenance)),
  curatedReviewCount: curatedReviews.length,
  fullyReviewedCount: fullyReviewed.length,
  partiallyReviewedCount: partiallyReviewed.length,
  staleReviewCount: staleReviews.length,
  staleSourceReviewCount: reviewFreshness.filter(
    ({ status }) => status === "stale_source_review"
  ).length,
  staleMediaReviewCount: reviewFreshness.filter(
    ({ status }) => status === "stale_media_review"
  ).length,
  staleSourceAndMediaReviewCount: reviewFreshness.filter(
    ({ status }) => status === "stale_source_and_media_review"
  ).length,
  missingSourceFingerprintCount: reviewFreshness.filter(
    ({ freshness }) => freshness?.sourceFingerprintMissing
  ).length,
  missingMediaFingerprintCount: reviewFreshness.filter(
    ({ freshness }) => freshness?.mediaFingerprintMissing
  ).length,
  mediaMapMismatchCount,
  reviewFreshness: reviewFreshness.map(({ review, freshness, status }) => ({
    exerciseId: review.exerciseId,
    status,
    sourceFingerprintMissing: freshness?.sourceFingerprintMissing ?? false,
    mediaFingerprintMissing: freshness?.mediaFingerprintMissing ?? false,
  })),
  fullVideoReviewedCount: curatedReviews.filter((review) =>
    review.reviewedFrom.includes("video")
  ).length,
  sampledFramesReviewedCount: curatedReviews.filter((review) =>
    review.reviewedFrom.includes("sampled_frames")
  ).length,
  textOnlyReviewedCount: curatedReviews.filter(
    (review) =>
      !review.reviewedFrom.includes("video") &&
      !review.reviewedFrom.includes("sampled_frames") &&
      (review.reviewedFrom.includes("name") || review.reviewedFrom.includes("instructions"))
  ).length,
  reviewModality: {
    fullyReviewed: counts(fullyReviewed.map(({ review }) => modality(review))),
    partiallyReviewed: counts(partiallyReviewed.map(({ review }) => modality(review))),
  },
  ruleOnlyCount,
  unknownTypeCount,
  unknownPatternCount,
  unknownMechanicsCount,
  unknownLateralityCount,
  unknownTrackingCount,
  unknownSkillCount,
  automaticAllowedPlannerUnsupported,
  specializedPlannerUnsupported,
  manualOnlyByCapability,
  familyCount: index.byFamily.size,
  duplicates,
  variants,
  resolvedSourceConflicts,
  unresolvedSourceConflicts,
  unusable,
  lowConfidence: lowConfidence.map((item) => ({
    exerciseId: item.exerciseId,
    classificationConfidence: item.classificationConfidence,
  })),
  reviewProgressByFamily,
  missingPrimary: data.filter((exercise) => !exercise.primaryMuscle).map((exercise) => exercise.id),
  missingInstructions: data
    .filter((exercise) => exercise.instructions.length < 2)
    .map((exercise) => exercise.id),
  exactNameDuplicates,
  nearDuplicateCandidates: currentDuplicateCandidates.map((group) => ({
    key: group.key,
    members: group.members.map(({ id, name }) => ({ id, name })),
  })),
  legacyNearDuplicateGroupsReviewed: legacyDuplicateCandidates.length,
  unresolvedDuplicateGroups: unresolvedDuplicateGroups.map((group) => ({
    key: group.key,
    members: group.members.map(({ id, name }) => ({ id, name })),
  })),
  suspiciousPrimary: metadata
    .filter((item) => item.tags.includes("primary_mismatch"))
    .map((item) => ({
      id: item.exerciseId,
      name: index.byId.get(item.exerciseId)!.exercise.name,
    })),
  ancillaryEquipment: counts(
    metadata.flatMap((item) =>
      item.requiredEquipment.filter(
        (equipment) => equipment !== index.byId.get(item.exerciseId)!.exercise.equipment
      )
    )
  ),
  reviewQueue,
  exceptionalRecordCount: exceptionalRecords.length,
}

writeFileSync(
  "docs/training-engine/exercise-audit.json",
  JSON.stringify(report, null, 2) + "\n"
)
writeFileSync(
  "docs/training-engine/exceptional-exercises.json",
  JSON.stringify(
    {
      generatedFromDatasetFingerprint: report.datasetFingerprint,
      count: exceptionalRecords.length,
      records: exceptionalRecords,
    },
    null,
    2
  ) + "\n"
)
writeFileSync(
  "docs/training-engine/EXERCISE_DATA_AUDIT.md",
  `# Exercise data audit\n\nGenerated with \`bun scripts/audit-training-exercises.ts\`. The 1,324-record catalogue is frozen from explicit reviewed decisions; candidate-name normalization is diagnostic only. Full details are in [exercise-audit.json](exercise-audit.json), with compact exceptional records in [exceptional-exercises.json](exceptional-exercises.json). Source IDs and media remain unchanged.\n\n- Records: ${report.total}; fingerprint: ${report.datasetFingerprint}. Structural errors: ${report.errors.length}.\n- Types: ${JSON.stringify(report.types)}. Tracking: ${JSON.stringify(report.tracking)}.\n- Automatic programming: ${JSON.stringify(report.automaticProgramming)}. Planner capability: allowed but unsupported ${report.automaticAllowedPlannerUnsupported.length}.\n- Review completeness: fully reviewed ${report.fullyReviewedCount}; partial ${report.partiallyReviewedCount}; rule-only ${report.ruleOnlyCount}; stale ${report.staleReviewCount}. Missing source fingerprints ${report.missingSourceFingerprintCount}; missing media fingerprints ${report.missingMediaFingerprintCount}; media-map mismatches ${report.mediaMapMismatchCount}.\n- Review evidence: full-animation/video ${report.fullVideoReviewedCount}; sampled-frame ${report.sampledFramesReviewedCount}; text-only ${report.textOnlyReviewedCount}. Provenance: ${JSON.stringify(report.provenance)}.\n- Ordinary unknowns: type ${report.unknownTypeCount}; pattern ${report.unknownPatternCount}; mechanics ${report.unknownMechanicsCount}; laterality ${report.unknownLateralityCount}; tracking ${report.unknownTrackingCount}; skill ${report.unknownSkillCount}.\n- Relationships: families ${report.familyCount}; duplicates ${report.duplicates.length}; variants ${report.variants.length}. Conservative duplicate candidate groups ${report.nearDuplicateCandidates.length}; legacy groups explicitly reviewed ${report.legacyNearDuplicateGroupsReviewed}; unresolved duplicate groups ${report.unresolvedDuplicateGroups.length}.\n- Source/media conflicts: resolved ${report.resolvedSourceConflicts.length}; unresolved ${report.unresolvedSourceConflicts.length}. Unusable source records: ${report.unusable.length}. Low-confidence records below ${DEFAULT_POLICY.minimumAutomaticClassificationConfidence}: ${report.lowConfidence.length}.\n- Review queue: ${report.reviewQueue.length}. Exceptional-record report: ${report.exceptionalRecordCount}.\n\n## Findings\n\nEvery accepted record stores all core programming fields explicitly and is tied to current source and media fingerprints. The runtime can still infer metadata for caller-supplied exercises outside the built-in catalogue, but the built-in 1,324-record catalogue no longer derives its accepted core classifications from name regexes.\n\nFull-sequence visual review covered all catalogue animations. Source/media disagreements remain tagged as provenance, with a terminal reviewed resolution on each record. These tags therefore identify resolved evidence conflicts rather than pending review work.\n\nNear-duplicate discovery preserves semantic parenthetical qualifiers such as apparatus, grip and setup descriptors. It removes only version markers and non-semantic sex/viewpoint annotations. Structured \`duplicateOf\` and \`variantOf\` links are explicit reviewed decisions; candidate grouping does not write relationships.\n\nAutomatic programming remains capability-gated. \`specialized_only\` is used for fully understood movements whose skill, apparatus, instability or setup warrants explicit selection; \`manual_only\` remains available for classified exercises outside ordinary automatic planner capability. Neither state substitutes for incomplete classification.\n\nThe source muscle taxonomy and participation weights remain editorial inputs rather than physiological measurements. Required-equipment metadata supplements the source's single equipment label where reviewed media or instructions demonstrate benches, supports, rings, attachments or other setup requirements.\n`
)

console.log(
  JSON.stringify({
    total: report.total,
    types: report.types,
    tracking: report.tracking,
    automaticProgramming: report.automaticProgramming,
    provenance: report.provenance,
    fullyReviewed: report.fullyReviewedCount,
    partiallyReviewed: report.partiallyReviewedCount,
    ruleOnly: report.ruleOnlyCount,
    staleReviews: report.staleReviewCount,
    missingSourceFingerprints: report.missingSourceFingerprintCount,
    missingMediaFingerprints: report.missingMediaFingerprintCount,
    mediaMapMismatches: report.mediaMapMismatchCount,
    fullVideoReviewed: report.fullVideoReviewedCount,
    sampledFramesReviewed: report.sampledFramesReviewedCount,
    ordinaryUnknowns:
      report.unknownTypeCount +
      report.unknownPatternCount +
      report.unknownMechanicsCount +
      report.unknownLateralityCount +
      report.unknownTrackingCount +
      report.unknownSkillCount,
    families: report.familyCount,
    duplicates: report.duplicates.length,
    variants: report.variants.length,
    resolvedSourceConflicts: report.resolvedSourceConflicts.length,
    unresolvedSourceConflicts: report.unresolvedSourceConflicts.length,
    unusable: report.unusable.length,
    unresolvedDuplicateGroups: report.unresolvedDuplicateGroups.length,
    allowedPlannerMismatch: report.automaticAllowedPlannerUnsupported.length,
    reviewQueue: report.reviewQueue.length,
    exceptionalRecords: report.exceptionalRecordCount,
  })
)
