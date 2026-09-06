# Performance

Run `bun scripts/benchmark-training-engine.ts`. Measured on Apple M1 Pro, darwin arm64, runtime Bun 1.3.14 (Node compatibility v24.3.0). Core operations use one warmup plus 7 timed repetitions. Scenario-matrix generation uses one warmup plus 2 timed repetitions per scenario/beam combination. The reported p95 is the maximum of each small sample; it is not a precise tail-latency estimate. Wall-clock measurements remain outside deterministic core results.

| Operation | Median ms | Sample p95 ms |
|---|---:|---:|
| index build (1,324 records) | 88.47 | 94.5 |
| indexed muscle query (10,000 lookups) | 0.12 | 0.36 |
| state (120 sessions / 1,440 sets) | 5.76 | 11.93 |
| substitution search | 91.9 | 95.74 |
| generate (4 weeks, full data, history) | 1018 | 1141.6 |
| adapt next week | 233.92 | 244.47 |
| independent validation (4 weeks) | 16.37 | 18.21 |

## Representative beam-width comparison

| Width | Median ms | Score |
|---|---:|---:|
| beam width 1 | 475.41 | 0.7628 |
| beam width 3 | 965.46 | 0.7628 |
| beam width 8 | 2272.37 | 0.7748 |

## Scenario matrix

| Scenario | Beam | Median ms | Score | Hard-feasible | Status | Warnings |
|---|---:|---:|---:|:---:|---|---|
| beginner 2-day | 1 | 244.09 | 0.7314 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| beginner 2-day | 3 | 329.06 | 0.7314 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| beginner 2-day | 8 | 678.72 | 0.7314 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| beginner 3-day | 1 | 307.37 | 0.7591 | yes | success | INCOMPLETE_HISTORY, INSUFFICIENT_HISTORY_FOR_LOAD |
| beginner 3-day | 3 | 634.87 | 0.7591 | yes | success | INCOMPLETE_HISTORY, INSUFFICIENT_HISTORY_FOR_LOAD |
| beginner 3-day | 8 | 1438.14 | 0.7591 | yes | success | INCOMPLETE_HISTORY, INSUFFICIENT_HISTORY_FOR_LOAD |
| hypertrophy 4-day | 1 | 500.77 | 0.7455 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| hypertrophy 4-day | 3 | 986.73 | 0.7426 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| hypertrophy 4-day | 8 | 2636.89 | 0.7426 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| strength 4-day | 1 | 416.47 | 0.7746 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| strength 4-day | 3 | 955.47 | 0.7746 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| strength 4-day | 8 | 2658.71 | 0.7887 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| strength 5-day | 1 | 606.51 | 0.7747 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| strength 5-day | 3 | 1220.66 | 0.7747 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| strength 5-day | 8 | 3509.33 | 0.7888 | yes | success | INCOMPLETE_HISTORY, INSUFFICIENT_HISTORY_FOR_LOAD |
| equipment-limited | 1 | 219.97 | 0.6405 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| equipment-limited | 3 | 456.6 | 0.6398 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| equipment-limited | 8 | 966.46 | 0.6457 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| time-limited | 1 | 315.9 | 0.6742 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| time-limited | 3 | 436.14 | 0.6742 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| time-limited | 8 | 982.97 | 0.6859 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| priority muscle | 1 | 494.62 | 0.7448 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| priority muscle | 3 | 964.51 | 0.7448 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| priority muscle | 8 | 2297.05 | 0.7448 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| endurance beginner 3-day | 1 | 302.17 | 0.7617 | yes | success | INCOMPLETE_HISTORY, INSUFFICIENT_HISTORY_FOR_LOAD |
| endurance beginner 3-day | 3 | 608.18 | 0.7624 | yes | success | INCOMPLETE_HISTORY, INSUFFICIENT_HISTORY_FOR_LOAD |
| endurance beginner 3-day | 8 | 1359.76 | 0.7624 | yes | success | INCOMPLETE_HISTORY, INSUFFICIENT_HISTORY_FOR_LOAD |
| hypertrophy advanced 5-day | 1 | 697.04 | 0.7503 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| hypertrophy advanced 5-day | 3 | 1531.28 | 0.7503 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| hypertrophy advanced 5-day | 8 | 3642.09 | 0.7503 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| strength beginner 3-day | 1 | 337.4 | 0.7450 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| strength beginner 3-day | 3 | 566.21 | 0.7450 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| strength beginner 3-day | 8 | 1309.32 | 0.7450 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| bodyweight only | 1 | 200.81 | 0.7455 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| bodyweight only | 3 | 364.61 | 0.7455 | yes | success | INCOMPLETE_HISTORY, INSUFFICIENT_HISTORY_FOR_LOAD |
| bodyweight only | 8 | 820.37 | 0.7455 | yes | success | INCOMPLETE_HISTORY, INSUFFICIENT_HISTORY_FOR_LOAD |
| bands and bodyweight | 1 | 174.78 | 0.7230 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| bands and bodyweight | 3 | 293.32 | 0.7137 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| bands and bodyweight | 8 | 606.5 | 0.7137 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| six-day cold start | 1 | 722.7 | 0.7534 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| six-day cold start | 3 | 1727.44 | 0.7534 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| six-day cold start | 8 | 4146.22 | 0.7534 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| lower-body priority | 1 | 422.68 | 0.7025 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| lower-body priority | 3 | 912.04 | 0.7255 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| lower-body priority | 8 | 1871.27 | 0.7032 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| weekly-set cap | 1 | 275.19 | 0.5824 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| weekly-set cap | 3 | 438.94 | 0.5707 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| weekly-set cap | 8 | 880.54 | 0.5707 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| explicit chest bounds | 1 | 441.5 | 0.7369 | yes | success | INCOMPLETE_HISTORY, INSUFFICIENT_HISTORY_FOR_LOAD |
| explicit chest bounds | 3 | 822.02 | 0.7413 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| explicit chest bounds | 8 | 1945.17 | 0.7413 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| very tight duration | 1 | 147.65 | 0.4052 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| very tight duration | 3 | 207.1 | 0.4052 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| very tight duration | 8 | 386.52 | 0.4052 | yes | partial | INCOMPLETE_HISTORY, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, VOLUME_BELOW_TARGET, FREQUENCY_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |
| dense history | 1 | 455.23 | 0.7628 | yes | success | INSUFFICIENT_HISTORY_FOR_LOAD |
| dense history | 3 | 944.56 | 0.7628 | yes | success | INSUFFICIENT_HISTORY_FOR_LOAD |
| dense history | 8 | 2229.72 | 0.7748 | yes | partial | VOLUME_BELOW_TARGET, INSUFFICIENT_HISTORY_FOR_LOAD |

| Beam | Feasible scenarios | Median scenario latency ms | Median score |
|---|---:|---:|---:|
| 1 | 19/19 | 337.4 | 0.7450 |
| 3 | 19/19 | 634.87 | 0.7448 |
| 8 | 19/19 | 1438.14 | 0.7448 |

Scores are optimizer utility, not predicted fitness outcomes. The default beam width remains 3 unless the matrix shows a repeatable quality improvement that justifies additional latency. Wider beams are not guaranteed to be monotonic in final score: pruning ranks partial weeks, and bounded local improvement runs only after the final pre-improvement candidate is selected. A path retained by a narrow beam can therefore be displaced by several temporarily stronger partial paths in a wider beam, while a different final candidate can respond less well to local improvement. This matrix found 5 adjacent-width score regressions; exact cases are recorded in benchmark-results.json. Guaranteeing monotonicity would require keeping an explicit incumbent or improving and comparing more terminal candidates, which would change search cost and semantics, so no policy change is made from this diagnostic alone.

## Profiling and limits

An initial cold-start run took about 2,097 ms. Bun CPU profiling showed repeated muscle-volume aggregation inside candidate scoring as the dominant sampled stack. Computing one scoring context per partial session and iterating only known set roles reduced that same cold-start run to about 508 ms. This is an algorithmic change with invariant/scenario regression tests. No native code or optimization dependency was needed. Indexes are reusable for analytics, validation and queries. Generation currently builds its own index once per request.

These are desktop development measurements, not iPhone benchmarks or a latency SLA. Several-thousand-exercise inputs and very long histories should be profiled on target hardware before UI integration. The pure synchronous API can be called from a future Web Worker without redesigning the domain. Persisted programs include a policy snapshot; payload size trades off against reproducibility.
