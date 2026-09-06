# Performance

Run `bun scripts/benchmark-training-engine.ts`. Measured on Apple M1 Pro, darwin arm64, runtime Bun 1.3.14 (Node compatibility v24.3.0). Core operations use one warmup plus 7 timed repetitions. Scenario-matrix generation uses one warmup plus 3 timed repetitions per scenario/beam combination. The reported p95 is the maximum of each small sample; it is not a precise tail-latency estimate. Wall-clock measurements remain outside deterministic core results.

| Operation | Median ms | Sample p95 ms |
|---|---:|---:|
| index build (1,324 records) | 94.63 | 100.24 |
| indexed muscle query (10,000 lookups) | 0.11 | 0.17 |
| state (120 sessions / 1,440 sets) | 5.55 | 6.29 |
| substitution search | 90.7 | 97.99 |
| generate (4 weeks, full data, history) | 1084.71 | 1095.6 |
| adapt next week | 250.02 | 256.12 |
| independent validation (4 weeks) | 17.73 | 20.87 |

## Representative beam-width comparison

| Width | Median ms | Score |
|---|---:|---:|
| beam width 1 | 580.16 | 0.7682 |
| beam width 3 | 1125.93 | 0.7848 |
| beam width 8 | 2617.22 | 0.7848 |

## Scenario matrix

| Scenario | Beam | Median ms | Score | Hard-feasible | Status |
|---|---:|---:|---:|:---:|---|
| beginner 2-day | 1 | 269.7 | 0.7015 | yes | partial |
| beginner 2-day | 3 | 391.61 | 0.7015 | yes | partial |
| beginner 2-day | 8 | 669.97 | 0.7015 | yes | partial |
| beginner 3-day | 1 | 355.33 | 0.7514 | yes | partial |
| beginner 3-day | 3 | 728.28 | 0.7514 | yes | partial |
| beginner 3-day | 8 | 1628.67 | 0.7353 | yes | partial |
| hypertrophy 4-day | 1 | 620.49 | 0.7371 | yes | partial |
| hypertrophy 4-day | 3 | 1255.93 | 0.7371 | yes | partial |
| hypertrophy 4-day | 8 | 2964.21 | 0.7371 | yes | partial |
| strength 4-day | 1 | 496.77 | 0.7725 | yes | partial |
| strength 4-day | 3 | 1042.38 | 0.7650 | yes | partial |
| strength 4-day | 8 | 2551.87 | 0.7650 | yes | partial |
| strength 5-day | 1 | 582.88 | 0.7726 | yes | partial |
| strength 5-day | 3 | 1329.12 | 0.7575 | yes | partial |
| strength 5-day | 8 | 3667.35 | 0.7869 | yes | success |
| equipment-limited | 1 | 260.2 | 0.6378 | yes | partial |
| equipment-limited | 3 | 442.89 | 0.6247 | yes | partial |
| equipment-limited | 8 | 793.9 | 0.6438 | yes | partial |
| time-limited | 1 | 270.83 | 0.6374 | yes | partial |
| time-limited | 3 | 493.41 | 0.6374 | yes | partial |
| time-limited | 8 | 1070.09 | 0.6489 | yes | partial |
| priority muscle | 1 | 661.65 | 0.7487 | yes | partial |
| priority muscle | 3 | 1206.4 | 0.7487 | yes | partial |
| priority muscle | 8 | 2664.37 | 0.7481 | yes | partial |
| dense history | 1 | 536.49 | 0.7682 | yes | partial |
| dense history | 3 | 976.06 | 0.7848 | yes | success |
| dense history | 8 | 2433.92 | 0.7848 | yes | success |

| Beam | Feasible scenarios | Median scenario latency ms | Median score |
|---|---:|---:|---:|
| 1 | 9/9 | 496.77 | 0.7487 |
| 3 | 9/9 | 976.06 | 0.7487 |
| 8 | 9/9 | 2433.92 | 0.7371 |

Scores are optimizer utility, not predicted fitness outcomes. The default beam width remains 3 unless the matrix shows a repeatable quality improvement that justifies additional latency; one case alone is not used to change policy.

## Profiling and limits

An initial cold-start run took about 2,097 ms. Bun CPU profiling showed repeated muscle-volume aggregation inside candidate scoring as the dominant sampled stack. Computing one scoring context per partial session and iterating only known set roles reduced that same cold-start run to about 508 ms. This is an algorithmic change with invariant/scenario regression tests. No native code or optimization dependency was needed. Indexes are reusable for analytics, validation and queries. Generation currently builds its own index once per request.

These are desktop development measurements, not iPhone benchmarks or a latency SLA. Several-thousand-exercise inputs and very long histories should be profiled on target hardware before UI integration. The pure synchronous API can be called from a future Web Worker without redesigning the domain. Persisted programs include a policy snapshot; payload size trades off against reproducibility.
