import { beforeEach, describe, expect, it } from "vitest"

import { planSessionReconciliation } from "@/lib/session-reconciliation"
import {
  createTrainingWeek,
  plannedWorkoutFor,
  type PlannedSessionView,
} from "@/lib/training-plan"
import {
  reconcileRestoredActiveWorkout,
  useActiveWorkout,
} from "@/store/use-active-workout"
import { useFilters } from "@/store/use-filters"
import { DEFAULT_SETTINGS, useSettings } from "@/store/use-settings"
import { useTrainingProfile } from "@/store/use-training-profile"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts, type Workout } from "@/store/use-workouts"
import {
  createEmptyPersistedTrainingState,
  type PersistedSetObservation,
} from "@/training-persistence/schema"

/**
 * One workout across three stores that persist independently.
 *
 * These tests relaunch the app the way a device does — memory gone, storage
 * intact — and, for the crash cases, put back a storage snapshot in which one
 * store's write landed and its neighbour's did not. That is the whole hazard:
 * every interruption window between two of those writes restores a session
 * whose pieces describe different workouts.
 */

const BENCH = "0025"
const SQUAT = "0043"
const ROW = "0571"
const NOW = "2026-09-07T10:00:00.000Z"

const records = () => useTrainingRecords.getState()
const workouts = () => useWorkouts.getState()

const KEYS = {
  workouts: "gym-lib-workouts",
  active: "gym-lib-active-workout",
  training: "gym-lib-training",
} as const

type StorageSnapshot = Record<keyof typeof KEYS, string | null>

function snapshot(): StorageSnapshot {
  return {
    workouts: localStorage.getItem(KEYS.workouts),
    active: localStorage.getItem(KEYS.active),
    training: localStorage.getItem(KEYS.training),
  }
}

/**
 * What a relaunch does: memory gone, storage intact, then the one
 * reconciliation pass that the store module runs at import.
 *
 * `stored` lets a test hand back a storage image in which only some of a
 * multi-store write survived — exactly what a process killed between two of
 * them leaves behind.
 */
async function relaunch(stored: StorageSnapshot = snapshot()) {
  useActiveWorkout.setState({ session: null, lastOutcome: null })
  useWorkouts.setState({ workouts: [] })
  useTrainingRecords.setState({
    data: createEmptyPersistedTrainingState(),
    persistenceIssues: [],
  })
  for (const key of ["workouts", "active", "training"] as const) {
    const value = stored[key]
    if (value === null) localStorage.removeItem(KEYS[key])
    else localStorage.setItem(KEYS[key], value)
  }
  await useWorkouts.persist.rehydrate()
  await useActiveWorkout.persist.rehydrate()
  await useTrainingRecords.persist.rehydrate()
  return reconcileRestoredActiveWorkout()
}

function observation(kg = 80, reps = 10): PersistedSetObservation {
  return {
    reps,
    resistance: {
      type: "external_load",
      kg,
      basis: "total",
      stationId: "barbell",
    },
    completed: true,
    timestamp: new Date().toISOString(),
  }
}

function makeWorkout(name: string, exerciseIds: string[]): Workout {
  const id = workouts().createWorkout({
    name,
    date: "2026-09-08",
    exerciseIds,
  })
  return workouts().workouts.find((item) => item.id === id)!
}

function logFreeSet(exerciseId: string, kg = 80) {
  const draft = records().data.activeWorkout!
  const entry = draft.exercises.find((item) => item.exerciseId === exerciseId)!
  records().addUnplannedSet({
    exerciseEntryId: entry.id,
    setType: "working",
    side: "both",
    observation: observation(kg),
  })
}

function week() {
  const outcome = createTrainingWeek({ days: [0, 2, 4], now: NOW })
  if (outcome.status !== "created") throw new Error(outcome.message)
  return outcome.sessions
}

function startPlanned(view: PlannedSessionView) {
  const workout = plannedWorkoutFor(view)!
  expect(useActiveWorkout.getState().start(workout)).toBe(true)
  return workout
}

function logFirstPlannedSet() {
  const draft = records().data.activeWorkout!
  const exercise = draft.exercises[0]
  const set = exercise.sets.find((item) => item.setType !== "warmup")!
  records().recordSet({
    exerciseEntryId: exercise.id,
    setDraftId: set.id,
    observation: observation(60, 8),
  })
}

describe("restoring one workout from three stores", () => {
  beforeEach(() => {
    useActiveWorkout.setState({ session: null, lastOutcome: null })
    localStorage.clear()
    useWorkouts.setState({ workouts: [] })
    useTrainingRecords.setState({
      data: createEmptyPersistedTrainingState(),
      persistenceIssues: [],
    })
    useTrainingProfile.getState().resetTrainingProfile()
    useSettings.setState(DEFAULT_SETTINGS)
    useFilters.setState({
      equipmentPresets: [],
      gymEquipment: ["dumbbell"],
      selectedEquipment: [],
      selectedMuscles: [],
    })
  })

  it("resumes a coherent session unchanged, with its observations intact", async () => {
    const workout = makeWorkout("Push", [BENCH, SQUAT])
    useActiveWorkout.getState().start(workout)
    logFreeSet(BENCH, 82.5)
    const session = structuredClone(useActiveWorkout.getState().session)
    const draft = structuredClone(records().data.activeWorkout)

    const outcome = await relaunch()

    expect(outcome).toMatchObject({
      draft: "keep",
      session: "keep",
      reason: "coherent",
    })
    // Byte for byte: recovery re-reads observations, it never rebuilds them.
    expect(records().data.activeWorkout).toEqual(draft)
    expect(useActiveWorkout.getState().session).toEqual(session)
    expect(records().data.sessions).toEqual([])
    expect(useActiveWorkout.getState().session!.workoutId).toBe(
      records().data.activeWorkout!.sourceWorkoutId
    )
  })

  it("does not log against another workout's draft when the two disagree", async () => {
    const first = makeWorkout("First", [BENCH])
    const second = makeWorkout("Second", [SQUAT])
    useActiveWorkout.getState().start(first)
    const shellOfFirst = snapshot().active

    // Starting the second workout opens its draft and then exposes its shell.
    // A process killed between those two writes restores the first workout's
    // shell on top of the second workout's draft.
    useActiveWorkout.getState().start(second)
    const draftOfSecond = snapshot().training

    const outcome = await relaunch({
      workouts: snapshot().workouts,
      active: shellOfFirst,
      training: draftOfSecond,
    })

    expect(outcome.reason).toBe("workout-mismatch")
    // Before reconciliation this shell would have pointed the set editor at
    // the first workout while every set landed in the second workout's draft.
    expect(useActiveWorkout.getState().session).toBeNull()
    expect(records().data.activeWorkout).toBeNull()
    // The second draft held no observations, so it leaves no history behind.
    expect(records().data.sessions).toEqual([])
  })

  it("keeps the observations when the shell it belonged to is gone", async () => {
    const workout = makeWorkout("Push", [BENCH, SQUAT])
    useActiveWorkout.getState().start(workout)
    logFreeSet(BENCH, 100)
    logFreeSet(SQUAT, 140)

    const outcome = await relaunch({ ...snapshot(), active: null })

    expect(outcome.reason).toBe("draft-without-session")
    const [saved] = records().data.sessions
    expect(saved.status).toBe("partial")
    expect(saved.sourceWorkoutId).toBe(workout.id)
    expect(saved.exercises.map((item) => item.exerciseId)).toEqual([
      BENCH,
      SQUAT,
    ])
    expect(saved.exercises[0].sets[0].resistance).toMatchObject({ kg: 100 })
    expect(records().data.activeWorkout).toBeNull()
  })

  it("closes a shell that has no structured record behind it", async () => {
    const workout = makeWorkout("Push", [BENCH])
    useActiveWorkout.getState().start(workout)

    const outcome = await relaunch({ ...snapshot(), training: null })

    expect(outcome.reason).toBe("session-without-draft")
    expect(useActiveWorkout.getState().session).toBeNull()
    // Nothing is opened in its place: a draft invented here would be a session
    // the person never started.
    expect(records().data.activeWorkout).toBeNull()
    expect(records().data.sessions).toEqual([])
  })

  it("does not offer a second finish for a workout already completed", async () => {
    const workout = makeWorkout("Push", [BENCH])
    useActiveWorkout.getState().start(workout)
    logFreeSet(BENCH)
    const beforeFinish = snapshot()

    // finish() writes the legacy completion, then closes the draft, then
    // clears the shell. This is the state left by a kill after the first write.
    workouts().completeWorkout(workout.id, {
      activeCalories: 120,
      completedAt: "2026-09-08T11:00:00.000Z",
      completedExerciseIds: [BENCH],
      durationMs: 3_600_000,
      healthSyncStatus: "not-requested",
      startedAt: "2026-09-08T10:00:00.000Z",
    })

    const outcome = await relaunch({
      workouts: snapshot().workouts,
      active: beforeFinish.active,
      training: beforeFinish.training,
    })

    expect(outcome.reason).toBe("workout-completed")
    expect(useActiveWorkout.getState().session).toBeNull()
    // The sets survive as their own partial session, and the workout keeps the
    // single completion it already had.
    expect(records().data.sessions).toHaveLength(1)
    expect(records().data.sessions[0].status).toBe("partial")
    expect(records().data.sessions[0].sourceWorkoutId).toBe(workout.id)
    expect(workouts().workouts[0].completion?.durationMs).toBe(3_600_000)
    // One workout, one session in what the engine reads.
    expect(records().getTrainingHistory().sessions).toHaveLength(1)
  })

  it("never writes a second session for a workout history already holds", async () => {
    const workout = makeWorkout("Push", [BENCH])
    useActiveWorkout.getState().start(workout)
    logFreeSet(BENCH)
    const beforeFinish = snapshot()
    useActiveWorkout.getState().finish()
    const recorded = structuredClone(records().data.sessions)
    expect(recorded).toHaveLength(1)

    // finish() closes the draft and then clears the shell. A kill in between
    // brings the shell back on top of a session already written to history.
    const outcome = await relaunch({
      workouts: snapshot().workouts,
      active: beforeFinish.active,
      training: snapshot().training,
    })

    expect(outcome.reason).toBe("session-without-draft")
    expect(records().data.sessions).toEqual(recorded)
    expect(useActiveWorkout.getState().session).toBeNull()
  })

  it("discards a draft whose session history already holds", () => {
    const workout = makeWorkout("Push", [BENCH])
    useActiveWorkout.getState().start(workout)
    logFreeSet(BENCH)
    const draft = records().data.activeWorkout!

    // The legacy completion never landed, so only history itself says this
    // workout is done. Closing the draft again would double-count it.
    const decision = planSessionReconciliation({
      session: null,
      workouts: workouts().workouts,
      training: {
        ...records().data,
        sessions: [
          {
            id: "already",
            sourceWorkoutId: workout.id,
            startedAt: "2026-09-08T10:00:00.000Z",
            completedAt: "2026-09-08T11:00:00.000Z",
            durationSeconds: 3600,
            status: "partial",
            exercises: [],
          },
        ],
      },
    })

    expect(decision).toMatchObject({
      draft: "discard",
      reason: "already-recorded",
    })
    expect(draft.exercises[0].sets).toHaveLength(1)
  })

  it("does not duplicate structured history when legacy completion also exists", async () => {
    const workout = makeWorkout("Push", [BENCH])
    useActiveWorkout.getState().start(workout)
    logFreeSet(BENCH)
    const draft = structuredClone(records().data.activeWorkout!)
    const completedAt = new Date(
      Math.max(
        Date.parse(draft.startedAt),
        ...draft.exercises.flatMap((exercise) =>
          exercise.sets.flatMap((set) =>
            set.observation?.timestamp
              ? [Date.parse(set.observation.timestamp)]
              : []
          )
        )
      ) + 1_000
    ).toISOString()

    workouts().completeWorkout(workout.id, {
      activeCalories: 120,
      completedAt,
      completedExerciseIds: [BENCH],
      durationMs: Date.parse(completedAt) - Date.parse(draft.startedAt),
      healthSyncStatus: "not-requested",
      startedAt: draft.startedAt,
    })
    records().completeWorkout("partial", completedAt)
    const recorded = structuredClone(records().data.sessions)
    expect(recorded).toHaveLength(1)

    // A corrupt/half-restored image can still contain the stale draft beside
    // both completion records. Recovery must prefer the structured record
    // that already exists; closing the draft would count the workout twice.
    useTrainingRecords.setState((state) => ({
      ...state,
      data: { ...state.data, activeWorkout: draft },
    }))

    const outcome = reconcileRestoredActiveWorkout()

    expect(outcome.reason).toBe("already-recorded")
    expect(records().data.sessions).toEqual(recorded)
    expect(records().data.activeWorkout).toBeNull()
    expect(useActiveWorkout.getState().session).toBeNull()
    expect(records().getTrainingHistory().sessions).toHaveLength(1)
  })

  it("leaves no fictional history behind a stale shell that logged nothing", async () => {
    const workout = makeWorkout("Push", [BENCH, SQUAT])
    useActiveWorkout.getState().start(workout)
    // Checked off by hand, but not one set was ever logged.
    useActiveWorkout.getState().toggleComplete(BENCH)

    const outcome = await relaunch({ ...snapshot(), active: null })

    expect(outcome.reason).toBe("draft-without-session")
    // A check mark is not a set: nothing reaches history.
    expect(records().data.sessions).toEqual([])
    expect(records().data.activeWorkout).toBeNull()
    expect(workouts().workouts[0].completion).toBeNull()
  })

  it("repairs the same state the same way however often it runs", async () => {
    const first = makeWorkout("First", [BENCH])
    const second = makeWorkout("Second", [SQUAT])
    useActiveWorkout.getState().start(first)
    logFreeSet(BENCH)
    const shellOfFirst = snapshot().active
    useActiveWorkout.getState().start(second)
    logFreeSet(SQUAT)

    await relaunch({
      workouts: snapshot().workouts,
      active: shellOfFirst,
      training: snapshot().training,
    })
    const afterOnce = {
      sessions: structuredClone(records().data.sessions),
      draft: records().data.activeWorkout,
      session: useActiveWorkout.getState().session,
    }
    // One from starting the second workout over the first, one from closing
    // the mismatched draft. Both are real work; neither is written twice.
    expect(afterOnce.sessions).toHaveLength(2)

    const second_ = reconcileRestoredActiveWorkout()
    const third = reconcileRestoredActiveWorkout()

    expect(second_.reason).toBe("idle")
    expect(third.reason).toBe("idle")
    expect(records().data.sessions).toEqual(afterOnce.sessions)
    expect(records().data.activeWorkout).toBe(afterOnce.draft)
    expect(useActiveWorkout.getState().session).toBe(afterOnce.session)
  })

  it("closes an orphaned draft when its workout is gone", async () => {
    const workout = makeWorkout("Push", [BENCH])
    useActiveWorkout.getState().start(workout)
    logFreeSet(BENCH)
    const withWorkout = snapshot()
    workouts().deleteWorkout(workout.id)

    const outcome = await relaunch({
      workouts: snapshot().workouts,
      active: withWorkout.active,
      training: withWorkout.training,
    })

    expect(outcome.reason).toBe("workout-missing")
    expect(records().data.sessions).toHaveLength(1)
    expect(records().data.sessions[0].status).toBe("partial")
    expect(useActiveWorkout.getState().session).toBeNull()
  })

  it("resumes a planned session with its prescription and lineage intact", async () => {
    const sessions = week()
    const workout = startPlanned(sessions[0])
    logFirstPlannedSet()
    const draft = structuredClone(records().data.activeWorkout)
    const programs = JSON.stringify(records().data.programs)

    const outcome = await relaunch()

    expect(outcome.reason).toBe("coherent")
    expect(records().data.activeWorkout).toEqual(draft)
    expect(records().data.activeWorkout!.plannedProgramId).toBe(
      workout.planned!.programId
    )
    expect(records().data.activeWorkout!.plannedSessionId).toBe(
      workout.planned!.sessionId
    )
    // The prescription is history of its own and recovery never touches it.
    expect(JSON.stringify(records().data.programs)).toBe(programs)
  })

  it("closes a planned session whose lineage no longer agrees", async () => {
    const sessions = week()
    startPlanned(sessions[0])
    logFirstPlannedSet()
    const programs = JSON.stringify(records().data.programs)

    // The shell comes back pointing at a different planned session than the
    // draft is recording — the prescription a set answers is no longer known.
    const stored = snapshot()
    const workoutsImage = JSON.parse(stored.workouts!)
    for (const item of workoutsImage.state.workouts)
      if (item.planned) item.planned.sessionId = sessions[1].sessionId

    const outcome = await relaunch({
      ...stored,
      workouts: JSON.stringify(workoutsImage),
    })

    expect(outcome.reason).toBe("planned-lineage-mismatch")
    expect(useActiveWorkout.getState().session).toBeNull()
    // The set was really performed, so it is kept — under the lineage it was
    // recorded with, never re-pointed at the prescription the shell claimed.
    const [saved] = records().data.sessions
    expect(saved.status).toBe("partial")
    expect(saved.plannedSessionId).toBe(sessions[0].sessionId)
    expect(saved.exercises[0].sets[0].plannedSetId).toBeDefined()
    expect(JSON.stringify(records().data.programs)).toBe(programs)
  })

  it("never lets a planned workout come back as a free one", () => {
    const sessions = week()
    const workout = plannedWorkoutFor(sessions[0])!
    // A free draft carrying a planned workout's identity: the prescription it
    // answered would be lost the moment it reached history.
    records().startFreeWorkout([BENCH], "2026-09-08T10:00:00.000Z", workout.id)

    const decision = planSessionReconciliation({
      session: null,
      workouts: workouts().workouts,
      training: records().data,
    })

    expect(decision).toMatchObject({
      draft: "close",
      reason: "planned-lineage-mismatch",
    })
  })

  it("keeps a hand-built workout recoverable", async () => {
    const workout = makeWorkout("Push", [BENCH, ROW])
    useActiveWorkout.getState().start(workout)
    logFreeSet(ROW, 65)
    const draft = structuredClone(records().data.activeWorkout)

    const outcome = await relaunch()

    expect(outcome.reason).toBe("coherent")
    expect(records().data.activeWorkout).toEqual(draft)
    expect(records().data.activeWorkout!.plannedProgramId).toBeUndefined()

    // And it still finishes normally afterwards.
    useActiveWorkout.getState().finish()
    expect(records().data.sessions).toHaveLength(1)
    expect(records().data.sessions[0].status).toBe("completed")
  })

  it("does nothing at all when there was no session to restore", async () => {
    makeWorkout("Push", [BENCH])

    const outcome = await relaunch()

    expect(outcome).toMatchObject({ reason: "idle", session: "keep" })
    expect(records().data.activeWorkout).toBeNull()
    expect(records().data.sessions).toEqual([])
  })
})
