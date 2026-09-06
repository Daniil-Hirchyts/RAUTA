# Validation record

Final local verification on 2026-09-06:

| Check                        | Result                                                                                   |
| ---------------------------- | ---------------------------------------------------------------------------------------- |
| `bun run typecheck`          | Passed; traverses referenced app/Node TypeScript projects                                |
| `bun run lint`               | Passed                                                                                   |
| `bun run training:example`   | Passed; generated and validated the deterministic example plan                           |
| `bun run training:audit`     | Passed; regenerated the catalogue audit from source data and current review fingerprints |
| `bun run training:test`      | Passed: 80 tests across four files                                                       |
| `bun run test`               | Passed: 313 tests across 28 files                                                        |
| `bun run build`              | Passed; Vite reports the application's large-chunk warning                               |
| `git diff --check`           | Passed                                                                                   |
| `bun run training:benchmark` | Completed; actual measurements in PERFORMANCE.md and benchmark-results.json              |

The engine has 80 tests in four suites. Tests include real-data cold start, multiple goals, novice through advanced profiles, muscle priorities, full gym, bodyweight, dumbbells, bands, short sessions, exclusions, impossible volume/time, known squat/bench/deadlift histories, stagnation, regression, partial and missed work, next-week continuity and reduced-volume triggers.

Accounting tests cover direct/indirect credits, independent participation weights, working versus warmup/drop/incomplete sets, UTC window edges, exponential workload decay, compatible e1RM, station/basis guards, missing effort, achievable grids, bodyweight rep progression, added-weight/bodyweight e1RM exclusion, assistance direction, separate-side pairing, linked IDs, and conservative load changes. Program validators are exercised independently using mutated outputs.

Fixed-seed generated testing covers 40 valid profiles and 250 malformed input cases, plus explicit malformed/cyclic payloads. Metamorphic checks cover expanded equipment feasibility, exclusion behavior, priority target monotonicity, frequency without automatic volume escalation, bounded session time without rest compression, input/dataset permutation determinism and input immutability. Regression checks also cover stale-review rejection after source or media changes, qualitative band resistance, planner capability filtering, skill suitability, policy fingerprints, and immutable output snapshots. This is meaningful regression coverage, not a proof over all inputs or of scientific efficacy.

Production changes are limited to `src/training`, development scripts, documentation, and package scripts. No dependency, UI, store migration, device integration, runtime network, AI, or backend was added.
