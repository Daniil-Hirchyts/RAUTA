# Performance

Run `bun scripts/benchmark-training-engine.ts`. Measured on Apple M1 Pro, darwin arm64, runtime Bun 1.3.14 (Node compatibility v24.3.0). One warmup plus 7 timed repetitions per operation. The reported p95 is the maximum of this small sample; it is not a precise tail-latency estimate. Input: full 1,324-record dataset, four-week program, 3 × 45-minute sessions/week, 120 historical sessions and 1,440 completed sets. Wall-clock measurements remain outside deterministic core results.

| Operation | Median ms | Sample p95 ms |
|---|---:|---:|
| index build (1,324 records) | 86.38 | 89.09 |
| indexed muscle query (10,000 lookups) | 0.11 | 0.17 |
| state (120 sessions / 1,440 sets) | 5.18 | 5.64 |
| substitution search | 85.39 | 92.82 |
| generate (4 weeks, full data, history) | 1035.11 | 1054.51 |
| adapt next week | 227.44 | 232.32 |
| independent validation (4 weeks) | 16.56 | 17.34 |

## Beam width comparison

| Width | Median ms | Score |
|---|---:|---:|
| beam width 1 | 529.67 | 0.7602 |
| beam width 3 | 1047.74 | 0.7602 |
| beam width 8 | 2367.73 | 0.7848 |

Scores are optimizer utility, not predicted fitness outcomes. One representative case does not establish global optimality. Default width 3 bounds latency; widening is configurable.

## Profiling and limits

An initial cold-start run took about 2,097 ms. Bun CPU profiling showed repeated muscle-volume aggregation inside candidate scoring as the dominant sampled stack. Computing one scoring context per partial session and iterating only known set roles reduced that same cold-start run to about 508 ms. This is an algorithmic change with invariant/scenario regression tests. No native code or optimization dependency was needed. Indexes are reusable for analytics, validation and queries. Generation currently builds its own index once per request.

These are desktop development measurements, not iPhone benchmarks or a latency SLA. Several-thousand-exercise inputs and very long histories should be profiled on target hardware before UI integration. The pure synchronous API can be called from a future Web Worker without redesigning the domain. Persisted programs include a policy snapshot; payload size trades off against reproducibility.
