# Validation record

Final local verification on 2026-09-06:

| Check                        | Result                                                                                   |
| ---------------------------- | ---------------------------------------------------------------------------------------- |
| `bun run typecheck`          | Passed; traverses referenced app/Node TypeScript projects                                |
| `bun run lint`               | Passed                                                                                   |
| `bun run training:example`   | Passed; generated and validated the deterministic example plan                           |
| `bun run training:media-fingerprints:check` | Passed; 1,324 media files matched 1,324 committed SHA-256 fingerprints with no missing, extra, or changed entries |
| `bun run training:catalogue:check` | Passed; 1,324/1,324 fully reviewed with zero partial, rule-only, stale, unresolved conflict, duplicate-group, review-queue, relationship, or planner-mismatch issues |
| `bun run training:audit`     | Passed; regenerated the catalogue audit from source data and current review fingerprints |
| `bun run training:persistence:test` | Passed: 18 persistence/migration/history-adapter tests across one file                         |
| `bun test src/training/__tests__/boundaries.test.ts src/training/__tests__/scenarios.test.ts` | Passed: 46 targeted planner/progression tests across two files |
| `bun test scripts/__tests__/webp-compositor.test.ts` | Passed: 3 delta-frame compositor tests |
| `bun run training:test`      | Passed: 100 tests across five files (engine + persistence prefix suites)                 |
| `bun run test`               | Passed: 336 tests across 30 files                                                        |
| `bun run build`              | Passed; Vite reports the application's large-chunk warning                               |
| `git diff --check`           | Passed                                                                                   |
| `bun run training:benchmark` | Completed; actual measurements in PERFORMANCE.md and benchmark-results.json              |

The engine has 82 training tests in four engine suites. The separate persistence suite adds 18 tests for versioned schema validation/migration, corruption recovery, legacy zero-set compatibility including default bridging from the existing workout store, planned and unplanned structured sessions, partial completion, substitution lineage, resistance/load contexts, unilateral accounting, immutable program revisions, historical policy/dataset snapshots, no-input-mutation behavior, active-draft reload, and atomic draft-to-history completion.

Accounting tests cover direct/indirect credits, independent participation weights, working versus warmup/drop/incomplete sets, UTC window edges, exponential workload decay, compatible e1RM, station/basis guards, missing effort, achievable grids, bodyweight-only rep progression context, band-resistance-only progression context, added-weight/bodyweight e1RM exclusion, assistance direction, separate-side pairing, linked IDs, and conservative load changes. Program validators are exercised independently using mutated outputs.

Fixed-seed generated testing covers 40 valid profiles and 250 malformed input cases, plus explicit malformed/cyclic payloads. Metamorphic checks cover expanded equipment feasibility, exclusion behavior, priority target monotonicity, frequency without automatic volume escalation, bounded session time without rest compression, input/dataset permutation determinism and input immutability. Regression checks also cover stale-review rejection after source or media changes, qualitative band resistance, planner capability filtering, skill suitability, policy fingerprints, and immutable output snapshots. This is meaningful regression coverage, not a proof over all inputs or of scientific efficacy.

The persistence implementation is isolated to `src/training-persistence`, `src/store/use-training-records.ts`, documentation, and package scripts. The pure `src/training` engine remains storage/UI independent. No dependency, workout-UI redesign, device integration, runtime network, AI, backend, database server, or cloud sync was added.
