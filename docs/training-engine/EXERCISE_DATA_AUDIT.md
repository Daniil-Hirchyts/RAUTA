# Exercise data audit

Generated with `bun scripts/audit-training-exercises.ts`. The 1,324-record catalogue is frozen from explicit reviewed decisions; candidate-name normalization is diagnostic only. Full details are in [exercise-audit.json](exercise-audit.json), with compact exceptional records in [exceptional-exercises.json](exceptional-exercises.json). Source IDs and media remain unchanged.

- Records: 1324; fingerprint: 60f861c1. Structural errors: 0.
- Types: {"conditioning":21,"isometric":19,"mobility":15,"power":50,"resistance":1158,"stretch":61}. Tracking: {"assistance":18,"band_resistance":61,"bodyweight":279,"distance":13,"external_load":850,"timed":103}.
- Automatic programming: {"allowed":956,"manual_only":173,"specialized_only":195}. Planner capability: allowed but unsupported 0.
- Review completeness: fully reviewed 1324; partial 0; rule-only 0; stale 0. Missing source fingerprints 0; missing media fingerprints 0; media-map mismatches 0.
- Review evidence: full-animation/video 1324; sampled-frame 0; text-only 0. Provenance: {"curated_video_and_text":1324}.
- Ordinary unknowns: type 0; pattern 0; mechanics 0; laterality 0; tracking 0; skill 0.
- Relationships: families 122; duplicates 10; variants 96. Conservative duplicate candidate groups 37; legacy groups explicitly reviewed 64; unresolved duplicate groups 0.
- Source/media conflicts: resolved 27; unresolved 0. Unusable source records: 0. Low-confidence records below 0.7: 0.
- Review queue: 0. Exceptional-record report: 454.

## Findings

Every accepted record stores all core programming fields explicitly and is tied to current source and media fingerprints. The runtime can still infer metadata for caller-supplied exercises outside the built-in catalogue, but the built-in 1,324-record catalogue no longer derives its accepted core classifications from name regexes.

Full-sequence visual review covered all catalogue animations. Source/media disagreements remain tagged as provenance, with a terminal reviewed resolution on each record. These tags therefore identify resolved evidence conflicts rather than pending review work.

Near-duplicate discovery preserves semantic parenthetical qualifiers such as apparatus, grip and setup descriptors. It removes only version markers and non-semantic sex/viewpoint annotations. Structured `duplicateOf` and `variantOf` links are explicit reviewed decisions; candidate grouping does not write relationships.

Automatic programming remains capability-gated. `specialized_only` is used for fully understood movements whose skill, apparatus, instability or setup warrants explicit selection; `manual_only` remains available for classified exercises outside ordinary automatic planner capability. Neither state substitutes for incomplete classification.

The source muscle taxonomy and participation weights remain editorial inputs rather than physiological measurements. Required-equipment metadata supplements the source's single equipment label where reviewed media or instructions demonstrate benches, supports, rings, attachments or other setup requirements.
