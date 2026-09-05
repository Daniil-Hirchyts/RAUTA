# Mathematical specification

This is the implementation contract; formulas below describe accounting and optimizer utility, not predicted gains.

- Set credit: direct role = 1, curated/inferred meaningful indirect role = policy fraction 0.5, incidental/unknown = 0. Editorial participation weights do not enter the equation. Warmups and incomplete sets contribute zero. A paired left/right set counts once for the muscle group; an explicitly single-side record contributes half. Drop sets are tracked separately and excluded from standard set-equivalent accounting by default.
- Volume: sum credits over actual completed sets. Rolling windows are `(now − N × 24h, now]`. Current microcycle is `[weekStart, min(weekStart + 7d, now)]`. Future observations are invalid. Calendar dates are UTC adapter responsibilities.
- Workload heuristic: sum credit × exp(−ln(2) × elapsedHours / halfLifeHours). Default half-life 48h is a tunable scheduling assumption. No percentage recovery is inferred.
- e1RM: Epley `load × (1 + reps / 30)` or Brzycki `load × 36 / (37 − reps)`, only external load, compatible station and load basis, 1–10 reps, known RIR 0–2. A true 1@0 uses load directly. No bodyweight/assistance e1RM. Estimates are descriptive, not maximal-test prescriptions.
- Trend: compare medians of the most recent three versus preceding three comparable session estimates. Require six observations, use a 3% deadband, never extrapolate kilograms across exercises or stations.
- Volume utility: increases linearly to preferred volume then decreases toward the upper guideline; no unlimited reward. Minimum and preferred are soft; explicit user volume bounds are hard.
- Duration: general warmup + specific warmup execution/rest + working reps at upper rep bound × seconds per rep × side multiplier + inter-set rests + transition/setup allowances. No final working-set rest; warmup-to-working rest is included. A strict cap applies to the conservative estimate, not a promise of actual wall time.
- Progression: all prescribed sets at top reps and acceptable observed RIR allow the next achievable increment; otherwise hold/progress reps. Repeated underperformance permits one conservative reduction. Unknown effort, incomplete sets, long gaps and station changes prevent optimistic load escalation.

Final exact scoring coefficients, normalization, target adjustment and adaptation formulas are documented with the implemented policy below once validated.

## Implemented targets

All 18 source muscle groups receive state and volume accounting. Ten major groups (chest, upper-back, deltoids, biceps, triceps, quadriceps, gluteal, hamstring, calves, abs) receive default preferred targets. Other groups receive targets when explicitly prioritized. This is a product taxonomy choice, not an anatomical claim that the other muscles do not matter.

Goal ranges `(minimum, preferred, upper guideline)` are hypertrophy `(6,10,18)`, strength `(4,6,12)`, general/energy-support/endurance `(3,6,12)`, hybrid `(5,8,16)`. A beginner's base preferred target is capped at 6 before priority. Priority multiplies by low 0.75, normal 1, high 1.25 or specialization 1.5. Round to whole effective sets; clip to upper guideline. Preferred frequency is `min(slots, max(strength ? 2 : 1, ceil(preferred / 6)))`; it does not automatically raise weekly volume. Source muscles are broad groups and these initial targets need empirical tuning.

With explicitly complete ≥28-day history and at least six meaningful muscle sessions, preferred sets cannot exceed `observed 28-day sets / 4 + 2`. This is a conservative increase guard, not an estimate of maximum recoverable volume. Linked set adherence below 0.7 multiplies preferred by 0.9. Low reported readiness together with at least two declining exercises also multiplies by 0.9. Advanced status does not automatically multiply volume. Frequency never directly increases preferred volume. High soreness contributes a candidate penalty, never a diagnosis.

## Exact scoring

Every component is clipped to `[0,1]`. `Score.total = Σ(component × weight) / Σ(abs(weight))`, giving a bounded `[-1,1]` utility. Each contribution returns factor, normalized raw value, weight and product. Ties use code-point exercise IDs, not locale-dependent ordering. Arrays with no elements yield mean zero.

Exercise coverage for a candidate is the sum over relevant target muscles of `credit × importance × min(weekly remaining fraction, session quota remaining fraction)`, divided by `max(1, relevant importance sum / 3)`. Quota is preferred sets divided by the number of split slots serving that muscle. Weights: coverage 5; continuity 0.8 (doubled for adaptation context); preference 0.5; new movement pattern 0.7; classification confidence 0.4; redundancy −1.5; recent workload −0.5; setup/time pressure −0.5. Goal specificity uses weight 2 strength, 1.4 hybrid, 0.5 hypertrophy, 0.3 general/energy support, 0.2 endurance. Explicit specific exercises score 1; externally loaded compounds 0.5; others zero. Preference is favorite 1, neutral 0.5, disliked 0; exclusion is handled before scoring. Continuity is known prior exposure or a source-plan exercise. Workload is the mean of direct muscles' `clamp(decayedSets / 6)` plus an explicit high-soreness penalty, clipped again. This is a scheduling heuristic.

Pair similarity = `0.5 × Jaccard(patterns) + 0.4 × Jaccard(direct muscles) + 0.1 × same source equipment`; identical IDs score 1. Session redundancy is mean pair similarity. Candidate redundancy is maximum similarity against current session exercises. Source naming near-duplicates are separately audited.

Session score weights: focus coverage 2; duration 1; metadata quality 1; redundancy −1; muscle concentration above six sets −1; nonempty session 2. Focus coverage is fraction of focused muscle groups with any allocated effective sets. Duration score is 1 up to preferred time, then preferred/estimated time. Concentration averages `clamp((sets − 6)/6)` over targeted muscles.

Week score weights: volume 5; specificity 1 × goal-specificity weight; frequency 0.6; movement-family balance 0.6; quality 0.3; continuity 0.4; duration 0.4; preference 0.3; redundancy −0.6; closely spaced overlapping volume −0.6; average session utility 0.5. Specificity is the fraction of explicitly requested strength exercises included, or the proportion of externally loaded compounds when none are named. Volume fit is importance-weighted. Frequency fit saturates at preferred exposures. Balance covers push, pull, squat/lunge, hinge/curl/hip-extension and trunk families; these families are a broad heuristic, not a universal anatomical ratio. Close-session overlap is `mean_m(min(sets_i,m, sets_next,m)/6) × (1 − gapHours/48)` when gap <48h. Include the last-to-first weekly wrap, so repeated microcycles are evaluated too. For a single weekly session the gap is 168h.

For positive preferred target `p`, volume utility is `v/p` for `v≤p`, else `max(0, 1−(v−p)/max(1,upper−p))`. Thus excess can lower score. Program score is mean week score, with contribution means. Validation is a separate boolean gate; an invalid plan never competes with valid results.

Exercise order sorts by `10 × explicitly specific + 2 × highest direct-muscle importance + compound`, preserving construction order at ties. An explicit priority can put an isolation exercise ahead of a normal-priority compound.

## Construction and adaptation

Beam search expands one slot at a time, rotating across scheduled sessions. Each expansion considers the top eight filtered/scored exercises with one, two or three working sets, retaining three distinct best whole-week candidates. Existing partial candidates can remain unchanged. Depth is at most seven exercises × session count. Local search tries one-set removal and the best two alternative movements, accepting only strict score improvement under hard limits, for up to 12 passes. This is bounded heuristic optimization, not a feasibility proof or global optimality guarantee.

Multiweek templates preserve selection and prescriptions; no simulated future workouts enter analysis and no automatic weekly kg increases occur. Actual performance is required for adaptation.

Adaptation returns a **revision containing future slots only**, linked to the immutable source program. For a remaining week, `remaining preferred = max(0, preferred − actual microcycle effective sets)`. Hard weekly bounds and total-set budgets include actual work. Existing slots/exercises are preserved where permitted; unavailable exercises use compatible replacements; surplus and low-value work can be trimmed. Missed volume is never stacked onto one session. Next-week adaptation retains structure and refreshes each exercise prescription. A reduced-volume week requires low reported readiness plus at least two declining exercise trends; each exercise loses one working set, minimum one. This trigger is a product heuristic, not a diagnosis or mandatory calendar deload.

## Progression detail and units

A load grid is either an offset arithmetic sequence (minimum + k × increment) or an explicit list. Nearest ties choose the lower load. Progression steps to the next grid entry (opposite direction for assistance), with maximum relative change 10%; unavailable or excessive steps hold. Two consecutive comparable exposures with a majority of sets below minimum reps and RIR no higher than target permit one grid step toward easier work, also limited to 10%. A single bad workout holds. Top-of-range progression requires every completed working set to reach the top at RIR ≥target−1 and at least the prescribed paired count (both records plus the smaller left/right count), with no recorded unfinished working sets. Unknown RIR holds.

Bodyweight/unknown-resistance top-range performance can shift the rep range by one up to 30 reps; no effective body mass is fabricated. The updated rep target enters the actual prescription. Station and `total` versus `per_implement` basis must match for numeric load recommendations. Assistance is never converted to negative load. Per-implement dumbbell kg remains per-implement, not doubled. Load-free calibration carries target reps and RIR but no kg.

Warmup defaults: 180s general allowance, one compound rehearsal (5 reps) or two for heavy ≤8-rep work (5,3 reps), 60s after each ramp, external-load fractions 0.5 and 0.75 rounded down to an available load when possible. Otherwise prescribe calibration. Work execution uses upper rep bound ×4s; unilateral/alternating paired limbs multiply by 2. Setup is 60s for trackable external load, 30s otherwise; transitions 45s. Rest counts only working-set gaps, never an invented final rest. These timings are deliberately conservative estimates, not measured performance.

Confidence categories are ordinal. Median e1RM is calculated per session from eligible sets; the latest three session medians form recent strength, and the previous three form the trend baseline. Estimates older than 28 days are excluded from recent strength. Rep counts are not RIR-corrected into hypothetical failure repetitions. Very recent performance does not make e1RM exact. No demographic load formula, BMI adjustment, exact muscle recovery percentage, or calorie prediction exists.

Hard weekly working-set budgets use paired group units: a left/right pair totals one. Adherence awards half a planned set for one logged side and one for a completed pair. e1RM excludes explicitly single-side records to avoid mixing side-specific strength estimates. These conventions are data-accounting policies.
