import { writeFileSync } from "node:fs"
import exercises from "../src/data/exercises.generated.json"
import {
  createExerciseIndex,
  DEFAULT_POLICY,
  plannerSupportsExercise,
} from "../src/training"
import {
  curationFreshness,
  getCuratedExerciseReviews,
  isFullyCuratedReview,
} from "../src/training/data/curated-exercises"
import type { ExerciseSummary } from "../src/training"
const data = exercises as ExerciseSummary[]
const index = createExerciseIndex(data)
const counts = (values: string[]) =>
  Object.fromEntries(
    [...new Set(values)]
      .sort()
      .map((key) => [key, values.filter((v) => v === key).length])
  )
const groups = (key: (e: ExerciseSummary) => string) =>
  Object.values(Object.groupBy(data, key))
    .filter((g) => g && g.length > 1)
    .map((g) => g!.map((e) => ({ id: e.id, name: e.name })))
const metadata = [...index.byId.values()].map((e) => e.metadata)
const curatedReviews = getCuratedExerciseReviews()
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
const reviewModality = {
  fullyReviewed: counts(fullyReviewed.map(({ review }) => modality(review))),
  partiallyReviewed: counts(
    partiallyReviewed.map(({ review }) => modality(review))
  ),
}
const reviewProgressByFamily = [...index.byFamily.entries()]
  .map(([familyId, members]) => {
    const statuses = members.map(
      (member) => member.metadata.reviewStatus ?? "rule_only"
    )
    return {
      familyId,
      total: members.length,
      fullyReviewed: statuses.filter((status) => status === "fully_reviewed")
        .length,
      partiallyReviewed: statuses.filter(
        (status) => status === "partially_reviewed"
      ).length,
      stale: statuses.filter((status) => status.startsWith("stale_")).length,
      ruleOnly: statuses.filter((status) => status === "rule_only").length,
      allowed: members.filter(
        (member) => member.metadata.automaticProgramming === "allowed"
      ).length,
      members: members.map((member) => member.exercise.id),
    }
  })
  .filter((family) => family.fullyReviewed + family.partiallyReviewed > 0)
  .sort((a, b) => a.familyId.localeCompare(b.familyId))
const unresolvedConflictTags = [
  "source_media_conflict",
  "source_equipment_conflict",
]
const capabilityRow = (
  item: typeof index.byId extends Map<string, infer T> ? T : never
) => ({
  id: item.exercise.id,
  name: item.exercise.name,
  exerciseType: item.metadata.exerciseType,
  tracking: item.metadata.tracking,
})
const automaticAllowedPlannerUnsupported = [...index.byId.values()]
  .filter(
    (item) =>
      item.metadata.automaticProgramming === "allowed" &&
      !plannerSupportsExercise(item.metadata)
  )
  .map(capabilityRow)
const specializedPlannerUnsupported = [...index.byId.values()]
  .filter(
    (item) =>
      item.metadata.automaticProgramming === "specialized_only" &&
      !plannerSupportsExercise(item.metadata)
  )
  .map(capabilityRow)
const manualOnlyByCapability = [...index.byId.values()]
  .filter(
    (item) =>
      item.metadata.automaticProgramming === "manual_only" &&
      !plannerSupportsExercise(item.metadata)
  )
  .map(capabilityRow)
const report = {
  datasetFingerprint: index.fingerprint,
  total: data.length,
  errors: index.issues,
  equipment: counts(data.map((e) => e.equipment)),
  primaryMuscle: counts(data.map((e) => e.primaryMuscle ?? "missing")),
  participationCoverage: counts(data.flatMap((e) => e.muscles)),
  programmingDirectCoverage: counts(
    metadata.flatMap((m) =>
      m.setRoles.filter((r) => r.role === "direct").map((r) => r.muscleId)
    )
  ),
  types: counts(metadata.map((m) => m.exerciseType)),
  automaticProgramming: counts(metadata.map((m) => m.automaticProgramming)),
  provenance: counts(metadata.map((m) => m.provenance)),
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
      (review.reviewedFrom.includes("name") ||
        review.reviewedFrom.includes("instructions"))
  ).length,
  reviewModality,
  ruleOnlyCount: metadata.filter((m) => m.provenance === "rule").length,
  unknownTypeCount: metadata.filter((m) => m.exerciseType === "unknown").length,
  automaticAllowedPlannerUnsupported,
  specializedPlannerUnsupported,
  manualOnlyByCapability,
  duplicates: metadata
    .filter((m) => m.duplicateOf)
    .map((m) => ({ exerciseId: m.exerciseId, duplicateOf: m.duplicateOf! })),
  variants: metadata
    .filter((m) => m.variantOf)
    .map((m) => ({ exerciseId: m.exerciseId, variantOf: m.variantOf! })),
  conflicts: metadata
    .filter((m) => m.tags.some((tag) => unresolvedConflictTags.includes(tag)))
    .map((m) => ({
      exerciseId: m.exerciseId,
      tags: m.tags.filter((tag) => tag.includes("conflict")),
    })),
  reviewProgressByFamily,
  missingPrimary: data.filter((e) => !e.primaryMuscle).map((e) => e.id),
  missingInstructions: data
    .filter((e) => e.instructions.length < 2)
    .map((e) => e.id),
  exactNameDuplicates: groups((e) => e.name.toLowerCase().trim()),
  nearDuplicates: groups((e) =>
    e.name
      .toLowerCase()
      .replace(/\([^)]*\)|v\.\s*\d+|version \d+/g, "")
      .replace(/[^a-z0-9]+/g, " ")
      .trim()
  ),
  suspiciousPrimary: metadata
    .filter((m) => m.tags.includes("primary_mismatch"))
    .map((m) => ({
      id: m.exerciseId,
      name: index.byId.get(m.exerciseId)!.exercise.name,
    })),
  ancillaryEquipment: counts(
    metadata.flatMap((m) =>
      m.requiredEquipment.filter(
        (eq) => eq !== index.byId.get(m.exerciseId)!.exercise.equipment
      )
    )
  ),
  reviewQueue: metadata
    .filter(
      (m) =>
        m.exerciseType === "unknown" ||
        (m.provenance === "rule" &&
          m.classificationConfidence <
            (m.automaticProgramming === "specialized_only"
              ? DEFAULT_POLICY.minimumSpecializedClassificationConfidence
              : DEFAULT_POLICY.minimumAutomaticClassificationConfidence)) ||
        m.tags.includes("manual_review_required") ||
        m.reviewStatus?.startsWith("stale_")
    )
    .map((m) => ({
      id: m.exerciseId,
      name: index.byId.get(m.exerciseId)!.exercise.name,
      tags: m.tags,
    })),
}
writeFileSync(
  "docs/training-engine/exercise-audit.json",
  JSON.stringify(report, null, 2) + "\n"
)
writeFileSync(
  "docs/training-engine/EXERCISE_DATA_AUDIT.md",
  `# Exercise data audit\n\nGenerated with \`bun scripts/audit-training-exercises.ts\`. Full per-record review queues, capability exceptions, duplicate groups and coverage counts: [exercise-audit.json](exercise-audit.json). Source is unchanged.\n\n- Records: ${report.total}; fingerprint: ${report.datasetFingerprint}.\n- Structural errors: ${report.errors.length}; missing primary: ${report.missingPrimary.length}; insufficient instructions: ${report.missingInstructions.length}.\n- Types: ${JSON.stringify(report.types)}.\n- Automatic programming: ${JSON.stringify(report.automaticProgramming)}.\n- Planner capability: allowed but unsupported ${report.automaticAllowedPlannerUnsupported.length}; specialized but unsupported ${report.specializedPlannerUnsupported.length}; manual-only outside current planner capability ${report.manualOnlyByCapability.length}.\n- Provenance: ${JSON.stringify(report.provenance)}. Curated reviews: ${report.curatedReviewCount}; current fully reviewed core metadata: ${report.fullyReviewedCount}; current partially reviewed: ${report.partiallyReviewedCount}; stale: ${report.staleReviewCount}; rule-only fallback: ${report.ruleOnlyCount}.\n- Stale review detail: source ${report.staleSourceReviewCount}; media ${report.staleMediaReviewCount}; source and media ${report.staleSourceAndMediaReviewCount}. Missing source fingerprints: ${report.missingSourceFingerprintCount}; missing required media fingerprints: ${report.missingMediaFingerprintCount}.\n- Review source modality: full-animation/video reviewed: ${report.fullVideoReviewedCount}; sampled-frame + contact-sheet reviewed: ${report.sampledFramesReviewedCount}; text-only reviewed: ${report.textOnlyReviewedCount}. Current full/partial modality split: ${JSON.stringify(report.reviewModality)}.\n- Unknown exercise type: ${report.unknownTypeCount}; unresolved curated conflict records: ${report.conflicts.length}.\n- Structured duplicate relationships: ${report.duplicates.length}; variant relationships: ${report.variants.length}; curated families with review progress: ${report.reviewProgressByFamily.length}.\n- Exact-name duplicate groups: ${report.exactNameDuplicates.length}; normalized near-duplicate groups: ${report.nearDuplicates.length}. Uncurated groups remain review candidates, not proven duplicates.\n- Suspicious primary/movement conflicts: ${report.suspiciousPrimary.length}.\n- Unknown/low-confidence/conflict/stale review queue: ${report.reviewQueue.length}.\n\n## Findings\n\nCurated metadata overrides deterministic inference only for fields explicitly stored in the curated record. A current fully reviewed record has all 11 core programming fields explicitly present and current source/media fingerprints. Missing or changed required fingerprints make the review stale, force manual-only programming, and keep it out of current full/partial totals. Review completeness is separate from media modality: sampled-frame review is reported as sampled-frame review, and only inspection of the full animation may use video provenance.\n\nThe automatic planner supports resistance exercises tracked by external load, assistance, bodyweight, or qualitative band resistance. Timed, distance, repetition-only, unknown, and non-resistance records can remain classified in the catalogue but cannot be ordinary automatic selections. Band prescriptions do not invent kilograms or equivalence between bands.\n\nThe source maps lats and rhomboids to upper-back, all deltoid heads together, and most trunk work to abs. Obliques, hip-flexors and tibialis have no primary records. Some squats are primarily gluteal; programming assigns quadriceps and gluteal direct roles by explicit movement policy, not their editorial ranking. Serratus, forearm and stabilizer involvement is not treated as validated hypertrophy credit.\n\nMuscle weights are generated from source term order and damping constants in src/lib/muscles.ts (0.62 assist and 0.68 decay), not physiological measurements. They remain participation metadata only.\n\nThe source mixes stretches, mobility, conditioning, isometrics, complex power movements and dynamic resistance. Recognized non-resistance work is excluded. Unrecognized names remain unknown. Regex classification is deterministic and auditable, but is not expert curation. It supplies no invented systemic fatigue/stability coefficients.\n\nThe single equipment label omits benches, racks, pull-up bars, dip stations, boxes, anchors, partners and supports. Curated records correct required equipment only when supported by reviewed instructions/media. Complete technique accuracy still needs continued review; source instruction prose is not guaranteed correct. Bodyweight does not imply that supporting equipment such as a dip bar or bench is available.\n\nNo exercise IDs or generated source records were changed. Manual-only records remain available through the catalogue index while automatic generation filters them. Specialized records require explicit preference/specificity selection and the specialized confidence threshold.\n`
)
console.log(
  JSON.stringify({
    total: report.total,
    types: report.types,
    automaticProgramming: report.automaticProgramming,
    provenance: report.provenance,
    fullyReviewed: report.fullyReviewedCount,
    partiallyReviewed: report.partiallyReviewedCount,
    staleReviews: report.staleReviewCount,
    fullVideoReviewed: report.fullVideoReviewedCount,
    sampledFramesReviewed: report.sampledFramesReviewedCount,
    automaticAllowedPlannerUnsupported:
      report.automaticAllowedPlannerUnsupported.length,
    specializedPlannerUnsupported: report.specializedPlannerUnsupported.length,
    reviewQueue: report.reviewQueue.length,
    suspicious: report.suspiciousPrimary.length,
  })
)
