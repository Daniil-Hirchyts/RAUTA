# Exercise data audit

Generated with `bun scripts/audit-training-exercises.ts`. Full per-record review queues, duplicate groups and coverage counts: [exercise-audit.json](exercise-audit.json). Source is unchanged.

- Records: 1324; fingerprint: 9f113563.
- Structural errors: 0; missing primary: 0; insufficient instructions: 0.
- Types: {"conditioning":16,"resistance":687,"stretch":56,"unknown":565}.
- Exact-name duplicate groups: 6; normalized near-duplicate groups: 64. These are review candidates, not proven duplicate movements.
- Suspicious primary/movement conflicts: 35.
- Unknown/low-confidence review queue: 565.

## Findings

The source maps lats and rhomboids to upper-back, all deltoid heads together, and most trunk work to abs. Obliques, hip-flexors and tibialis have no primary records. Some squats are primarily gluteal; programming assigns quadriceps and gluteal direct roles by explicit movement policy, not their editorial ranking. Serratus, forearm and stabilizer involvement is not treated as validated hypertrophy credit.

Muscle weights are generated from source term order and damping constants in src/lib/muscles.ts (0.62 assist and 0.68 decay), not physiological measurements. They remain participation metadata only.

The source mixes stretches, mobility, conditioning, isometrics, complex power movements and dynamic resistance. Recognized non-resistance work is excluded. Unrecognized names remain unknown. Regex classification is deterministic and auditable, but is not expert curation. It supplies no invented systemic fatigue/stability coefficients. Each accepted rule has 0.75 classification confidence as an ordinal engineering signal.

The single equipment label omits benches, racks, pull-up bars, boxes, anchors, partners and supports. Instruction/name rules add detectable requirements. Complete equipment requirements and technique accuracy still need human review; source instruction prose is not guaranteed correct. Bodyweight always means no external resistance and does not imply availability of a bar or bench.

No exercise IDs or generated source records were changed. Enriched metadata overrides require validation and explicit provenance. Power, specialized partial ROM, complex skill variants and timed isometrics are excluded from V1 automatic selection.
