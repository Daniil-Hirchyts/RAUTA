import { writeFileSync } from "node:fs"
import exercises from "../src/data/exercises.generated.json"
import { createExerciseIndex, DEFAULT_POLICY } from "../src/training"
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
          DEFAULT_POLICY.minimumClassificationConfidence
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
  `# Exercise data audit\n\nGenerated with \`bun scripts/audit-training-exercises.ts\`. Full per-record review queues, duplicate groups and coverage counts: [exercise-audit.json](exercise-audit.json). Source is unchanged.\n\n- Records: ${report.total}; fingerprint: ${report.datasetFingerprint}.\n- Structural errors: ${report.errors.length}; missing primary: ${report.missingPrimary.length}; insufficient instructions: ${report.missingInstructions.length}.\n- Types: ${JSON.stringify(report.types)}.\n- Exact-name duplicate groups: ${report.exactNameDuplicates.length}; normalized near-duplicate groups: ${report.nearDuplicates.length}. These are review candidates, not proven duplicate movements.\n- Suspicious primary/movement conflicts: ${report.suspiciousPrimary.length}.\n- Unknown/low-confidence review queue: ${report.reviewQueue.length}.\n\n## Findings\n\nThe source maps lats and rhomboids to upper-back, all deltoid heads together, and most trunk work to abs. Obliques, hip-flexors and tibialis have no primary records. Some squats are primarily gluteal; programming assigns quadriceps and gluteal direct roles by explicit movement policy, not their editorial ranking. Serratus, forearm and stabilizer involvement is not treated as validated hypertrophy credit.\n\nMuscle weights are generated from source term order and damping constants in src/lib/muscles.ts (0.62 assist and 0.68 decay), not physiological measurements. They remain participation metadata only.\n\nThe source mixes stretches, mobility, conditioning, isometrics, complex power movements and dynamic resistance. Recognized non-resistance work is excluded. Unrecognized names remain unknown. Regex classification is deterministic and auditable, but is not expert curation. It supplies no invented systemic fatigue/stability coefficients. Each accepted rule has 0.75 classification confidence as an ordinal engineering signal.\n\nThe single equipment label omits benches, racks, pull-up bars, boxes, anchors, partners and supports. Instruction/name rules add detectable requirements. Complete equipment requirements and technique accuracy still need human review; source instruction prose is not guaranteed correct. Bodyweight always means no external resistance and does not imply availability of a bar or bench.\n\nNo exercise IDs or generated source records were changed. Enriched metadata overrides require validation and explicit provenance. Power, specialized partial ROM, complex skill variants and timed isometrics are excluded from V1 automatic selection.\n`
)
console.log(
  JSON.stringify({
    total: report.total,
    types: report.types,
    reviewQueue: report.reviewQueue.length,
    suspicious: report.suspiciousPrimary.length,
  })
)
