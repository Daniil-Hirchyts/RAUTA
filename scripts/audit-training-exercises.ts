import { writeFileSync } from "node:fs"
import exercises from "../src/data/exercises.generated.json"
import { createExerciseIndex, DEFAULT_POLICY } from "../src/training"
import { getCuratedExerciseReviews } from "../src/training/data/curated-exercises"
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
  videoReviewedCount: curatedReviews.filter((review) =>
    review.reviewedFrom.includes("video")
  ).length,
  textOnlyReviewedCount: curatedReviews.filter(
    (review) =>
      !review.reviewedFrom.includes("video") &&
      (review.reviewedFrom.includes("name") ||
        review.reviewedFrom.includes("instructions"))
  ).length,
  ruleOnlyCount: metadata.filter((m) => m.provenance === "rule").length,
  duplicates: metadata
    .filter((m) => m.duplicateOf)
    .map((m) => ({ exerciseId: m.exerciseId, duplicateOf: m.duplicateOf! })),
  variants: metadata
    .filter((m) => m.variantOf)
    .map((m) => ({ exerciseId: m.exerciseId, variantOf: m.variantOf! })),
  conflicts: metadata
    .filter((m) =>
      m.tags.some((tag) =>
        ["source_media_conflict", "source_equipment_conflict"].includes(tag)
      )
    )
    .map((m) => ({
      exerciseId: m.exerciseId,
      tags: m.tags.filter((tag) => tag.includes("conflict")),
    })),
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
        m.classificationConfidence <
          DEFAULT_POLICY.minimumClassificationConfidence ||
        m.tags.includes("manual_review_required")
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
  `# Exercise data audit\n\nGenerated with \`bun scripts/audit-training-exercises.ts\`. Full per-record review queues, duplicate groups and coverage counts: [exercise-audit.json](exercise-audit.json). Source is unchanged.\n\n- Records: ${report.total}; fingerprint: ${report.datasetFingerprint}.\n- Structural errors: ${report.errors.length}; missing primary: ${report.missingPrimary.length}; insufficient instructions: ${report.missingInstructions.length}.\n- Types: ${JSON.stringify(report.types)}.\n- Automatic programming: ${JSON.stringify(report.automaticProgramming)}.\n- Provenance: ${JSON.stringify(report.provenance)}. Curated records: ${report.curatedReviewCount}; actually video-reviewed: ${report.videoReviewedCount}; text-only reviewed: ${report.textOnlyReviewedCount}; rule-only fallback: ${report.ruleOnlyCount}.\n- Structured duplicate relationships: ${report.duplicates.length}; variant relationships: ${report.variants.length}; curated conflict records: ${report.conflicts.length}.\n- Exact-name duplicate groups: ${report.exactNameDuplicates.length}; normalized near-duplicate groups: ${report.nearDuplicates.length}. Uncurated groups remain review candidates, not proven duplicates.\n- Suspicious primary/movement conflicts: ${report.suspiciousPrimary.length}.\n- Unknown/low-confidence/conflict review queue: ${report.reviewQueue.length}.\n\n## Findings\n\nCurated metadata now overrides deterministic inference when a reviewed record exists. The current curated set is deliberately small: it contains only records whose name, instructions and animated WebP frames were actually inspected. All other records remain rule-derived fallback and retain explicit provenance; no unreviewed record is presented as video-curated.\n\nThe source maps lats and rhomboids to upper-back, all deltoid heads together, and most trunk work to abs. Obliques, hip-flexors and tibialis have no primary records. Some squats are primarily gluteal; programming assigns quadriceps and gluteal direct roles by explicit movement policy, not their editorial ranking. Serratus, forearm and stabilizer involvement is not treated as validated hypertrophy credit.\n\nMuscle weights are generated from source term order and damping constants in src/lib/muscles.ts (0.62 assist and 0.68 decay), not physiological measurements. They remain participation metadata only.\n\nThe source mixes stretches, mobility, conditioning, isometrics, complex power movements and dynamic resistance. Recognized non-resistance work is excluded. Unrecognized names remain unknown. Regex classification is deterministic and auditable, but is not expert curation. It supplies no invented systemic fatigue/stability coefficients.\n\nThe single equipment label omits benches, racks, pull-up bars, boxes, anchors, partners and supports. Instruction/name rules add detectable requirements. Complete equipment requirements and technique accuracy still need human review; source instruction prose is not guaranteed correct. Bodyweight always means no external resistance and does not imply availability of a bar or bench.\n\nNo exercise IDs or generated source records were changed. Manual-only records remain available through the catalogue index while automatic generation filters them. Specialized records require explicit preference/specificity selection.\n`
)
console.log(
  JSON.stringify({
    total: report.total,
    types: report.types,
    automaticProgramming: report.automaticProgramming,
    provenance: report.provenance,
    videoReviewed: report.videoReviewedCount,
    reviewQueue: report.reviewQueue.length,
    suspicious: report.suspiciousPrimary.length,
  })
)
