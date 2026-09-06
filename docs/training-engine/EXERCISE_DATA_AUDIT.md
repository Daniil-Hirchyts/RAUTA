# Exercise data audit

Generated with `bun scripts/audit-training-exercises.ts`. Full per-record review queues, capability exceptions, duplicate groups and coverage counts: [exercise-audit.json](exercise-audit.json). Source is unchanged.

- Records: 1324; fingerprint: 7c1b298b.
- Structural errors: 0; missing primary: 0; insufficient instructions: 0.
- Types: {"conditioning":16,"isometric":10,"power":42,"resistance":757,"stretch":56,"unknown":443}.
- Automatic programming: {"allowed":666,"manual_only":623,"specialized_only":35}.
- Planner capability: allowed but unsupported 0; specialized but unsupported 0; manual-only outside current planner capability 603.
- Provenance: {"curated":12,"curated_sampled_frames_and_text":72,"rule":1240}. Curated reviews: 84; current fully reviewed core metadata: 72; current partially reviewed: 12; stale: 0; rule-only fallback: 1240.
- Stale review detail: source 0; media 0; source and media 0. Missing source fingerprints: 0; missing required media fingerprints: 0.
- Review source modality: full-animation/video reviewed: 0; sampled-frame + contact-sheet reviewed: 84; text-only reviewed: 0. Current full/partial modality split: {"fullyReviewed":{"sampled_frames":72},"partiallyReviewed":{"sampled_frames":12}}.
- Unknown exercise type: 443; unresolved curated conflict records: 8.
- Structured duplicate relationships: 1; variant relationships: 38; curated families with review progress: 40.
- Exact-name duplicate groups: 6; normalized near-duplicate groups: 64. Uncurated groups remain review candidates, not proven duplicates.
- Suspicious primary/movement conflicts: 26.
- Unknown/low-confidence/conflict/stale review queue: 468.

## Findings

Curated metadata overrides deterministic inference only for fields explicitly stored in the curated record. A current fully reviewed record has all 11 core programming fields explicitly present and current source/media fingerprints. Missing or changed required fingerprints make the review stale, force manual-only programming, and keep it out of current full/partial totals. Review completeness is separate from media modality: sampled-frame review is reported as sampled-frame review, and only inspection of the full animation may use video provenance.

The automatic planner supports resistance exercises tracked by external load, assistance, bodyweight, or qualitative band resistance. Timed, distance, repetition-only, unknown, and non-resistance records can remain classified in the catalogue but cannot be ordinary automatic selections. Band prescriptions do not invent kilograms or equivalence between bands.

The source maps lats and rhomboids to upper-back, all deltoid heads together, and most trunk work to abs. Obliques, hip-flexors and tibialis have no primary records. Some squats are primarily gluteal; programming assigns quadriceps and gluteal direct roles by explicit movement policy, not their editorial ranking. Serratus, forearm and stabilizer involvement is not treated as validated hypertrophy credit.

Muscle weights are generated from source term order and damping constants in src/lib/muscles.ts (0.62 assist and 0.68 decay), not physiological measurements. They remain participation metadata only.

The source mixes stretches, mobility, conditioning, isometrics, complex power movements and dynamic resistance. Recognized non-resistance work is excluded. Unrecognized names remain unknown. Regex classification is deterministic and auditable, but is not expert curation. It supplies no invented systemic fatigue/stability coefficients.

The single equipment label omits benches, racks, pull-up bars, dip stations, boxes, anchors, partners and supports. Curated records correct required equipment only when supported by reviewed instructions/media. Complete technique accuracy still needs continued review; source instruction prose is not guaranteed correct. Bodyweight does not imply that supporting equipment such as a dip bar or bench is available.

No exercise IDs or generated source records were changed. Manual-only records remain available through the catalogue index while automatic generation filters them. Specialized records require explicit preference/specificity selection and the specialized confidence threshold.
