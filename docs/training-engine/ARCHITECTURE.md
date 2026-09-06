# Training engine architecture

The engine is an offline, pure TypeScript library under `src/training`. Inputs carry an explicit clock, UTC microcycle start, healthy-adult eligibility, equipment inventory, preferences, and actual set history. No app store or device service is imported. The existing `ExerciseSummary` and muscle vocabulary are reused through a data adapter; persistence is untouched.

## Investigation and design decisions

The app's exercise browser has ID and presentation indexes, editorial muscle weights, and ID-based substitutions. These are useful for browsing but cannot establish effective sets or specific load progression. Workouts and active sessions record completion of exercise IDs, elapsed milliseconds, and estimated calories. Settings expose HealthKit body weight; there is no age, readiness, set/RIR, or performance ledger. Calories are MET estimates and are deliberately excluded from programming. No repository AGENTS files were found. Strict TypeScript, Vitest, ESLint, Bun and Vite already exist.

Missing concepts added to the specification: explicit healthy-adult declaration; station identity and per-implement load semantics; ancillary equipment requirements; history completeness (absence is not proof of rest); observed versus planned set identity; per-side set accounting; history staleness; explicit UTC timestamps; stable content fingerprints; policy snapshots; bounded request sizes; metadata provenance; hard weekly volume budgets independent of soft evidence guidelines.

## Data flow

1. Runtime input validation and eligibility/capability gate.
2. Dataset validation, curated metadata overrides, deterministic inference fallback and reusable indexes. Curated reviews carry source-record and WebP content fingerprints; missing or changed required fingerprints make a review stale and force manual-only programming. The full source catalogue remains accessible.
3. Single derived state: actual volume, exercise-specific performance, adherence and confidence.
4. Goal/experience starting targets, priority, conservative history adjustment.
5. Evaluate full body, upper/lower and push/pull/legs candidate allocations. Templates are candidates, never selected solely from days per week.
6. Indexed hard filtering, including the reusable planner-capability invariant; bounded beam construction and whole-week scoring; bounded local set removal/substitution improvement. Skill suitability softly favors basic movements for beginners while explicit preference and strength specificity remain strong overrides.
7. Prescribe reps, effort, rest and calibration or history-based load. Automatic prescriptions support external load, assistance, bodyweight, and qualitative band resistance. Band resistance has no fabricated kilograms or cross-band equivalence. Timed, distance, repetition-only, and unknown tracking remain outside automatic planning. Future weeks preserve exercise selection; unobserved future progress is not fabricated.
8. Independent semantic validation reconstructs deterministic targets, prescriptions, ordering, duration, scores, policy/version/fingerprint invariants and adaptation lineage before returning structured success/partial/infeasible/unsupported results. Adaptation and stored-program evaluation compare complete policy fingerprints rather than trusting version labels alone.
9. Adaptation preserves past sessions and continuity, then replans future slots from residual muscle volume, residual muscle frequency and remaining explicit strength-exercise exposures without stacking missed sessions.

## Boundaries

Domain models, policy, metadata/index, analytics, targets, scoring, optimization, progression and validation have separate modules. `ProgramOptimizer`, `ProgressionStrategy` and `StrengthEstimator` are replaceable interfaces. Default policy constants are engineering choices guided by evidence, not individualized biological laws. Public entry points and executable usage are finalized after implementation.

## Implemented modules and public API

- `domain/types.ts`: immutable-by-contract serializable profile, eligibility, history, metadata, targets, planned work, issues, scores and extension interfaces.
- `policy.ts`: frozen versioned defaults. Clone and assign a new version when tuning; generated programs carry a full policy snapshot.
- `data/`: validated metadata/index construction, curated JSON overrides with provenance/relationships, deterministic inference fallback, SHA-256 media fingerprints, source-record fingerprints, stale-review fail-closed behavior, explicit role rules, ancillary equipment, and the non-destructive legacy adapter. Curated `familyId`, `duplicateOf` and `variantOf` metadata can improve continuity and substitutions while source records remain intact.
- `analysis/`: effective volume, rolling windows, decayed workload, compatible e1RM/trends and linked adherence.
- `planning/`: target derivation, split candidates and allocation, prescriptions, duration, bounded beam/local optimizer, generation, residual-volume/frequency/specificity adaptation, and substitution ranking. Substitutions use a richer family/pattern/direct-muscle/mechanics/tracking/laterality/equipment similarity than the global redundancy score.
- `scoring/`: normalized explainable candidate/session/week objectives, similarity and priority ordering.
- `progression/`: achievable grids, double progression, repetition progression, assistance semantics and pluggable strategies.
- `validation/`: request, policy, eligibility and independent whole-program checks; important derived semantics are recomputed rather than trusted from persisted fields, and unknown input is rejected structurally at generation/validation boundaries.
- `summary.ts`: pure debug summaries. Scripts perform file I/O and console reporting; the core does neither.

Main API from `src/training/index.ts`:

```ts
const result = generateTrainingProgram(request)
if (result.status === 'success' || result.status === 'partial') {
  const index = createExerciseIndex(request.exercises, request.metadata)
  const validation = validateTrainingProgram(result.program, request, index)
  const evaluation = evaluateTrainingProgram(result.program, request, index)
  const summary = summarizeProgram(result.program, index)
}
const state = analyzeTrainingState(request) // optional reusable index, targets, policy
const alternatives = findExerciseSubstitutions('0025', request)
const revision = adaptTrainingProgram({
  previousProgram,
  request: nextRequest, // one week, explicitly future UTC day slots
  mode: 'remaining_week', // or 'next_week'
})
```

`recommendProgression` accepts one indexed exercise, reps/RIR/set count, history, fixed clock, policy, optional load context and grid; callers may supply another `ProgressionStrategy`. `generateTrainingProgram` accepts an optional `ProgramOptimizer`. Epley and Brzycki implement `StrengthEstimator`. Accounting and duration utilities are exported for reporting and tests. Low-level analytics/helpers expect validated domain inputs; use `validateGenerationRequest` at persistence/adapter boundaries.

`success` means a valid plan with no target compromises; cold-start calibration and incomplete-history information may still be present. `partial` always includes a hard-valid program plus soft deficits. `infeasible` means this bounded optimizer found no hard-valid result. `invalid` means malformed input/data. `unsupported` means outside the supported population/capability. No generic exception is used for ordinary planning failure.

Schedule days are offsets 0–6 from an explicit UTC-midnight `weekStart`, not device-local weekdays. `now` is always supplied. Rolling hours differ from microcycles. A frontend must convert the user's timezone/day preferences into this domain contract. A remaining-week revision covers future slots only and carries source-program lineage; completed actual work contributes to original weekly hard limits during validation.

IDs are scoped to program revisions. Program and source-record content IDs are deterministic non-cryptographic fingerprints; reviewed WebP files use SHA-256. Persistence should use separate storage keys. Same dataset in another iteration order produces identical indexed selection and fingerprints. Engine output contains no nondeterministic timing values.

## Development and verification

```sh
bun run training:example
bun run training:audit
bun run training:test
bun run training:benchmark
bun run typecheck
bun run lint
bun run test
bun run build
```

No dependencies were added. Seeded invariant/malformed-input generation uses a small test-only LCG with fixed seeds, avoiding an extra property-testing dependency. The normal typecheck script now traverses TypeScript project references (`tsc -b --noEmit`), because the former root `tsc --noEmit` did not check the referenced application project. All implementation and test imports remain in the app's strict TypeScript project. Test source is excluded from production use by normal bundling.

## Deliberate specification refinements

A global muscle-specificity coefficient, exact recovery percentage, universal age multiplier, compulsory every-fourth-week deload and automatic increase in volume with more training days were rejected. Full physiological exercise metadata was not invented to fill missing values. Engine and default-policy versions moved to 1.3.0 for prescription capability and scoring changes; curation moved to 1.3.0 for fingerprinted review provenance. Rule inference remains 1.2.0 because its classification semantics did not change. Default beam width 3 remains configurable: the expanded matrix shows wider search can improve some scores at substantially higher cost, but bounded partial-state pruning and terminal local improvement make final quality non-monotonic. No solver/native runtime was necessary. Accurate set logs and further catalogue curation are the next prerequisites for individual calibration.
