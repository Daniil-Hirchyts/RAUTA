# Exercise data audit

Generated with `bun scripts/audit-training-exercises.ts`. Full per-record review queues, duplicate groups and coverage counts: [exercise-audit.json](exercise-audit.json). Source is unchanged.

- Records: 1324; fingerprint: 104ecfee.
- Structural errors: 0; missing primary: 0; insufficient instructions: 0.
- Types: {"conditioning":16,"resistance":747,"stretch":56,"unknown":505}.
- Automatic programming: {"allowed":612,"manual_only":677,"specialized_only":35}.
- Provenance: {"curated_video_and_text":12,"rule":1312}. Curated records: 12; actually video-reviewed: 12; text-only reviewed: 0; rule-only fallback: 1312.
- Structured duplicate relationships: 1; variant relationships: 4; curated conflict records: 5.
- Exact-name duplicate groups: 6; normalized near-duplicate groups: 64. Uncurated groups remain review candidates, not proven duplicates.
- Suspicious primary/movement conflicts: 26.
- Unknown/low-confidence/conflict review queue: 564.

## Findings

Curated metadata now overrides deterministic inference when a reviewed record exists. The current curated set is deliberately small: it contains only records whose name, instructions and animated WebP frames were actually inspected. All other records remain rule-derived fallback and retain explicit provenance; no unreviewed record is presented as video-curated.

The source maps lats and rhomboids to upper-back, all deltoid heads together, and most trunk work to abs. Obliques, hip-flexors and tibialis have no primary records. Some squats are primarily gluteal; programming assigns quadriceps and gluteal direct roles by explicit movement policy, not their editorial ranking. Serratus, forearm and stabilizer involvement is not treated as validated hypertrophy credit.

Muscle weights are generated from source term order and damping constants in src/lib/muscles.ts (0.62 assist and 0.68 decay), not physiological measurements. They remain participation metadata only.

The source mixes stretches, mobility, conditioning, isometrics, complex power movements and dynamic resistance. Recognized non-resistance work is excluded. Unrecognized names remain unknown. Regex classification is deterministic and auditable, but is not expert curation. It supplies no invented systemic fatigue/stability coefficients.

The single equipment label omits benches, racks, pull-up bars, boxes, anchors, partners and supports. Instruction/name rules add detectable requirements. Complete equipment requirements and technique accuracy still need human review; source instruction prose is not guaranteed correct. Bodyweight always means no external resistance and does not imply availability of a bar or bench.

No exercise IDs or generated source records were changed. Manual-only records remain available through the catalogue index while automatic generation filters them. Specialized records require explicit preference/specificity selection.
