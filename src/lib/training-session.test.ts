import { beforeEach, describe, expect, it } from "vitest"

import { useActiveWorkout } from "@/store/use-active-workout"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts } from "@/store/use-workouts"
import { createEmptyPersistedTrainingState } from "@/training-persistence/schema"
import type { PersistedSetObservation } from "@/training-persistence/schema"

/**
 * The manual workout flow — muscles, equipment, exercises, workout, perform —
 * and the structured training history the deterministic engine reads are one
 * system. These tests hold that seam: a free workout produces real observations
 * and nothing else, and a legacy record keeps meaning exactly what it always
 * meant.
 */

const BENCH = "0025"
const SQUAT = "0043"
const ROW = "0571"

const records = () => useTrainingRecords.getState()
const workouts = () => useWorkouts.getState()

function benchSet(kg: number, reps: number, rir?: number) {
  return {
    reps,
    resistance: {
      type: "external_load",
      kg,
      basis: "total",
      stationId: "barbell",
    },
    ...(rir === undefined ? {} : { rir }),
    completed: true,
    timestamp: new Date().toISOString(),
  } satisfies PersistedSetObservation
}

function startWorkout(exerciseIds: string[]) {
  const id = workouts().createWorkout({
    name: "Push",
    date: "2026-09-01",
    exerciseIds,
  })
  const workout = workouts().workouts.find((item) => item.id === id)!
  useActiveWorkout.getState().start(workout)
  return workout
}

function logSet(exerciseId: string, observation: PersistedSetObservation) {
  const draft = records().data.activeWorkout!
  const entry = draft.exercises.find((item) => item.exerciseId === exerciseId)!
  return records().addUnplannedSet({
    exerciseEntryId: entry.id,
    setType: "working",
    side: "both",
    observation,
  })
}

describe("free workouts as structured training history", () => {
  beforeEach(() => {
    localStorage.clear()
    useWorkouts.setState({ workouts: [] })
    useActiveWorkout.setState({ session: null, lastOutcome: null })
    useTrainingRecords.setState({ data: createEmptyPersistedTrainingState() })
  })

  it("opens a draft that lists the exercises and claims no performance", () => {
    startWorkout([BENCH, SQUAT])
    const draft = records().data.activeWorkout!

    expect(draft.exercises.map((item) => item.exerciseId)).toEqual([
      BENCH,
      SQUAT,
    ])
    // Listing an exercise is not performing it: no program, no planned session,
    // no sets whatsoever.
    expect(draft.plannedProgramId).toBeUndefined()
    expect(draft.plannedSessionId).toBeUndefined()
    expect(draft.exercises.flatMap((item) => item.sets)).toEqual([])
  })

  it("writes the sets that were performed and nothing the workout merely listed", () => {
    startWorkout([BENCH, SQUAT])
    logSet(BENCH, benchSet(80, 10, 2))
    logSet(BENCH, benchSet(80, 9, 1))
    useActiveWorkout.getState().finish()

    const [session] = records().data.sessions
    expect(session.status).toBe("completed")
    expect(session.exercises).toHaveLength(1)
    expect(session.exercises[0].exerciseId).toBe(BENCH)
    expect(session.exercises[0].sets).toMatchObject([
      { reps: 10, rir: 2, completed: true, setType: "working", side: "both" },
      { reps: 9, rir: 1, completed: true },
    ])
    expect(session.exercises[0].sets[0].resistance).toEqual({
      type: "external_load",
      kg: 80,
      basis: "total",
      stationId: "barbell",
    })
    // Completed set identity is the record's own; nothing links it to a plan.
    expect(session.exercises[0].sets[0].plannedSetId).toBeUndefined()
    expect(session.exercises[0].plannedExerciseId).toBeUndefined()

    const history = records().getTrainingHistory()
    expect(history.sessions).toHaveLength(1)
    expect(history.sessions[0].exercises[0].sets[0].reps).toBe(10)
  })

  it("counts an exercise with logged sets as performed in the saved workout", () => {
    startWorkout([BENCH, SQUAT])
    logSet(BENCH, benchSet(80, 10))
    useActiveWorkout.getState().finish()

    // Nothing was checked off by hand, but bench was demonstrably done — the
    // legacy record must not say the session was empty.
    expect(workouts().workouts[0].completion?.completedExerciseIds).toEqual([
      BENCH,
    ])
  })

  it("does not record a set that was only prepared in the editor", () => {
    startWorkout([BENCH])
    // The editor holds values without touching the store; only a confirmed set
    // reaches the draft, so a workout finished mid-thought records nothing.
    expect(records().data.activeWorkout!.exercises[0].sets).toEqual([])
    useActiveWorkout.getState().finish()

    expect(records().data.sessions).toEqual([])
    expect(records().data.activeWorkout).toBeNull()
    // The workout itself still completed: legacy duration and calories stand.
    expect(workouts().workouts[0].completion).not.toBeNull()
  })

  it("keeps the sets of a workout the person walked away from", () => {
    startWorkout([SQUAT, BENCH, ROW])
    logSet(SQUAT, benchSet(100, 5))
    logSet(BENCH, benchSet(80, 8))
    useActiveWorkout.getState().cancel()

    const [session] = records().data.sessions
    expect(session.status).toBe("partial")
    expect(session.exercises.map((item) => item.exerciseId)).toEqual([
      SQUAT,
      BENCH,
    ])
    expect(records().data.activeWorkout).toBeNull()
  })

  it("survives a reload with the draft and its observations intact", async () => {
    startWorkout([BENCH])
    logSet(BENCH, benchSet(82.5, 7, 1))
    const draft = structuredClone(records().data.activeWorkout)
    const stored = localStorage.getItem("gym-lib-training")!

    // What a relaunch does: memory gone, storage intact.
    useTrainingRecords.setState({ data: createEmptyPersistedTrainingState() })
    localStorage.setItem("gym-lib-training", stored)
    await useTrainingRecords.persist.rehydrate()

    expect(records().data.activeWorkout).toEqual(draft)
    const restored = records().data.activeWorkout!.exercises[0].sets[0]
    expect(restored.observation).toMatchObject({
      reps: 7,
      rir: 1,
      completed: true,
    })
    expect(restored.observation?.resistance).toMatchObject({ kg: 82.5 })
  })

  it("mirrors an exercise added to a running workout without disturbing logged sets", () => {
    const workout = startWorkout([BENCH])
    logSet(BENCH, benchSet(80, 10))

    workouts().updateWorkout(workout.id, { exerciseIds: [BENCH, ROW] })

    const draft = records().data.activeWorkout!
    expect(draft.exercises.map((item) => item.exerciseId)).toEqual([BENCH, ROW])
    expect(draft.exercises[0].sets).toHaveLength(1)
    expect(draft.exercises[1].sets).toEqual([])
  })

  it("closes a draft left behind by an earlier session under its own session", () => {
    startWorkout([BENCH])
    logSet(BENCH, benchSet(80, 10))
    // A process killed mid-workout leaves the structured draft behind while the
    // app session is gone.
    useActiveWorkout.setState({ session: null, lastOutcome: null })
    expect(records().data.activeWorkout).not.toBeNull()

    startWorkout([SQUAT])

    expect(records().data.sessions).toHaveLength(1)
    expect(records().data.sessions[0].exercises[0].exerciseId).toBe(BENCH)
    expect(records().data.activeWorkout!.exercises[0].exerciseId).toBe(SQUAT)
    expect(records().data.activeWorkout!.exercises[0].sets).toEqual([])
  })

  it("leaves legacy workouts as low-information history rather than inventing sets", () => {
    // A workout completed before structured logging existed: exercise IDs,
    // duration and calories, and no set data at all.
    const legacyId = workouts().createWorkout({
      name: "Old session",
      date: "2026-08-20",
      exerciseIds: [SQUAT, ROW],
    })
    workouts().completeWorkout(legacyId, {
      startedAt: "2026-08-20T09:00:00.000Z",
      completedAt: "2026-08-20T10:00:00.000Z",
      durationMs: 3_600_000,
      completedExerciseIds: [SQUAT],
      activeCalories: 320,
      healthSyncStatus: "not-requested",
    })

    startWorkout([BENCH])
    logSet(BENCH, benchSet(80, 10, 2))
    useActiveWorkout.getState().finish()

    const history = records().getTrainingHistory()
    const legacy = history.sessions.find((item) => item.id === legacyId)!
    expect(legacy.exercises).toEqual([{ exerciseId: SQUAT, sets: [] }])
    expect(legacy.durationSeconds).toBe(3600)

    // Two sessions, not three: the workout just performed is its structured
    // session and never also a set-less legacy exposure of itself.
    expect(history.sessions).toHaveLength(2)
    const structured = history.sessions.find((item) => item.id !== legacyId)!
    expect(structured.exercises[0].sets).toHaveLength(1)
    expect(history.sessions.map((item) => item.id)).not.toContain(
      workouts().workouts[1].id
    )
    // Coverage stays unknown: structured logging starting now says nothing
    // about the sessions that came before it.
    expect(history.coverage).toBe("unknown")
  })
})
