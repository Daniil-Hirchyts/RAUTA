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
| `bun test src/training/__tests__/boundaries.test.ts src/training/__tests__/scenarios.test.ts` | Passed: 46 targeted planner/progression tests across two files |
| `bun test scripts/__tests__/webp-compositor.test.ts` | Passed: 3 delta-frame compositor tests |
| `bun run training:test`      | Passed: 82 tests across four files                                                       |
| `bun run test`               | Passed: 318 tests across 29 files                                                        |
| `bun run build`              | Passed; Vite reports the application's large-chunk warning                               |
| `git diff --check`           | Passed                                                                                   |
| `bun run training:benchmark` | Completed; actual measurements in PERFORMANCE.md and benchmark-results.json              |

The engine has 82 training tests in four suites. Tests include real-data cold start, multiple goals, novice through advanced profiles, muscle priorities, full gym, bodyweight, dumbbells, bands, short sessions, exclusions, impossible volume/time, known squat/bench/deadlift histories, strength-lift repeated exposure, stagnation, regression, partial and missed work, next-week continuity and reduced-volume triggers.

Accounting tests cover direct/indirect credits, independent participation weights, working versus warmup/drop/incomplete sets, UTC window edges, exponential workload decay, compatible e1RM, station/basis guards, missing effort, achievable grids, bodyweight-only rep progression context, band-resistance-only progression context, added-weight/bodyweight e1RM exclusion, assistance direction, separate-side pairing, linked IDs, and conservative load changes. Program validators are exercised independently using mutated outputs.

Fixed-seed generated testing covers 40 valid profiles and 250 malformed input cases, plus explicit malformed/cyclic payloads. Metamorphic checks cover expanded equipment feasibility, exclusion behavior, priority target monotonicity, frequency without automatic volume escalation, bounded session time without rest compression, input/dataset permutation determinism and input immutability. Regression checks also cover stale-review rejection after source or media changes, qualitative band resistance, planner capability filtering, skill suitability, policy fingerprints, and immutable output snapshots. This is meaningful regression coverage, not a proof over all inputs or of scientific efficacy.

Production changes are limited to `src/training`, development scripts, documentation, and package scripts. No dependency, UI, store migration, device integration, runtime network, AI, or backend was added.
