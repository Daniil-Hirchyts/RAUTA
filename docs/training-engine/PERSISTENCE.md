# Versioned training persistence

Structured training persistence lives outside the deterministic engine under `src/training-persistence` and `src/store/use-training-records.ts`.

The dependency direction is:

```text
UI / interaction
→ useTrainingRecords application store
→ versioned persisted training schema
→ explicit persistence/domain adapters
→ src/training deterministic engine
```

`src/training` does not import Zustand, localStorage, React, Capacitor, networking, or this persistence package.

## Storage contract

The stable storage key is `gym-lib-training`. The payload itself carries `schemaVersion: 1`; the storage key is intentionally not version-suffixed.

V1 contains four explicit domains:

- immutable program records containing the complete generated program snapshot, policy snapshot, policy version, engine version, dataset fingerprint, diagnostics, planned session/set IDs, and adaptation lineage;
- structured completed sessions containing actual exercise/set observations;
- one recoverable active workout draft, kept separate from completed history inside the same transactionally persisted envelope;
- settings containing explicit history coverage and station/basis-specific load grids.

All persisted values are JSON-safe. Canonical numeric units are kilograms, seconds, meters where applicable, and ISO UTC timestamps. UI display units are boundary concerns and are not stored as mixed training evidence.

## Program immutability and lineage

`createPersistedProgramRecord` snapshots a generated `TrainingProgram` rather than regenerating it later. Historical policy snapshots and `datasetFingerprint` values are restored verbatim. Program adaptation lineage preserves `sourceProgramId`, `asOf`, and `remaining_week` / `next_week`; application-level manual regeneration can record the same source relationship explicitly.

Program snapshots are never edited in place. The application store exposes activation and archival metadata, but there is no destructive program-delete action. A new adaptation is persisted as a new program record and may become `activeProgramId`; the source record remains available for completed-session lineage.

Completed session IDs and completed set IDs are generated independently from `plannedSessionId` and `plannedSetId`. Planned IDs are linkage only.

## Active workout and completion transaction

An active workout draft preserves planned targets separately from user observations:

```text
target.reps / target.rir / target.resistance
observation.reps / observation.rir / observation.rpe / observation.resistance
```

Creating a draft from a planned session copies exercise IDs, planned set IDs, and target metadata, but leaves `observation` absent. Planned 8–12 reps therefore never become fictional completed reps.

The persisted active draft survives browser/app/process restart. Completion performs one Zustand persistence update:

```text
validated active draft
→ completed or partial structured session
→ append durable history
→ activeWorkout = null
```

Only sets with an explicit completed observation are emitted. Unperformed planned sets remain absent from completed history and can be inferred as skipped later from plan lineage. Additional unplanned sets have no `plannedSetId`. Free workouts have no program/session lineage. Exercise substitution preserves the originally planned canonical exercise ID while storing the canonical exercise ID actually performed.

A set logged by mistake can be taken back while the draft is live: `discardLoggedSet` removes an unplanned draft set whether or not it carries an observation, because only completion writes evidence. Prescribed sets are never removed this way — they are the prescription, not a record.

## Completed observations

A completed structured set persists:

- independent completed-set ID;
- optional planned-set ID;
- actual reps;
- actual structured resistance;
- optional actual RIR and/or RPE;
- set type (`warmup`, `working`, `backoff`, `drop`, `other`);
- side (`both`, `left`, `right`);
- completion flag and optional observation timestamp.

External load and assistance preserve `kg`, `stationId`, and `basis` (`total` or `per_implement`). Assistance remains assistance; no negative-load encoding exists. Bodyweight remains `{ type: "bodyweight" }`. Band resistance remains qualitative `{ type: "band_resistance" }`; persistence never assigns band kilograms. Different station IDs are not interchangeable load evidence.

Load grids are persisted separately from history as explicit exercise + station + basis configurations. They are never inferred from observed sets.

## History adapter and coverage

`toTrainingHistory` converts structured persisted sessions into the engine `TrainingHistory` contract without inventing values. Persisted exercise segments with the same canonical exercise ID are merged only at the engine boundary; every set value is copied from the actual persisted observation.

History coverage is explicit:

- `unknown` remains unknown;
- `complete` requires a persisted `coverageStart` timestamp.

Structured logging does not automatically claim historical completeness. A product flow may mark coverage complete starting from the point where it can actually guarantee structured capture.

Legacy `gym-lib-workouts` records continue to coexist independently. `adaptLegacyWorkout` preserves their observed session identity, timestamps, duration, and completed exercise IDs while creating **zero completed sets**.

## NO FABRICATED LEGACY SETS

Legacy records do not contain reps, load, RIR/RPE, set type, side, or planned-set identity. Migration and adapters therefore never synthesize values such as `3 × 10`, unknown kilograms, RIR 2, or planned-set links. Legacy exercise occurrences contribute no fake effective volume or progression evidence.

Calories remain legacy/application metadata and are not training-engine evidence.

## Runtime validation and migrations

`validatePersistedTrainingState` checks schema version, IDs, duplicate record/set identities, ISO timestamps, finite numeric values, resistance variants, effort ranges, sides, set types, planned lineage, load grids, program snapshot structure, and JSON safety.

`migratePersistedTrainingState` is the deterministic migration entry point. It accepts V1 and the pre-release V0 envelope. V0 had no coverage claim, so its migration explicitly sets coverage to `unknown`; it does not invent observations. Unsupported versions reject.

`recoverPersistedTrainingState` is the fail-safe hydration path used by the store. If a payload is partially corrupt, valid records are retained where this is structurally safe and invalid records are dropped with structured issues. Corrupt values are never numerically coerced or reinterpreted as training evidence.

Migration/adapters clone inputs and do not mutate callers. `serializePersistedTrainingState` normalizes top-level record ordering and uses stable key ordering for deterministic serialized output while preserving meaningful program/session/set array order.

## Application workouts as structured sessions

`useWorkouts` and `useActiveWorkout` keep serving the manual flow — muscles, equipment, exercises, workout, perform — unchanged. `src/lib/training-session.ts` is the single seam between that session and the structured record:

```text
start a workout   → free draft, exercises listed, zero sets
log a set         → one completed observation appended to the draft
finish            → completed structured session
discard           → partial structured session, or no session when nothing was logged
```

A free workout has no program, planned session, planned exercise or planned set, and none is invented for it. Its performed sets are the same structured observations a generated session will produce, in the same history.

`sourceWorkoutId` names the application workout a structured session was performed from. It is lineage between the two application stores, not plan lineage, and it exists so there is one training history rather than two: `toTrainingHistory` drops the legacy `gym-lib-workouts` record of any workout a structured session already claims, instead of counting the same session twice — once with sets and once as a set-less exposure. Workouts performed before this integration keep contributing through `adaptLegacyWorkout` exactly as before.

The field is optional inside schema version 1: payloads written before it validate and load unchanged, and its absence means "no known application workout", never a guess.

## Set-level observations from the application UI

The active-workout screen collects observations through `src/lib/resistance.ts`, which decides from catalogue metadata and equipment which resistance shape an exercise is measured in — external load per implement or total, assistance, body weight, band — and in which increments its load moves. Prefilling the editor from the previous set, or from the last session, is a convenience; nothing is persisted until the set is confirmed, and an exercise that was never logged produces no record when the workout ends.
