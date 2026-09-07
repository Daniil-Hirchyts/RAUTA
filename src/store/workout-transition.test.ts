import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

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
import { planTransitionRecovery } from "@/training-persistence/transition"
import { validatePersistedTrainingState } from "@/training-persistence/validation"

/**
 * Interrupting a workout transition at every write it is made of.
 *
 * Starting and finishing a workout each touch three separately persisted
 * stores. These tests stop the app between each pair of those writes — by
 * relaunching from the storage image that existed at that moment — and check
 * that the journal carries the same transition forward to the same result.
 */

const BENCH = "0025"
const SQUAT = "0043"

const records = () => useTrainingRecords.getState()
const workouts = () => useWorkouts.getState()

const KEYS = {
  workouts: "gym-lib-workouts",
  active: "gym-lib-active-workout",
  training: "gym-lib-training",
} as const

type Image = Record<keyof typeof KEYS, string | null>

function snapshot(): Image {
  return {
    workouts: localStorage.getItem(KEYS.workouts),
    active: localStorage.getItem(KEYS.active),
    training: localStorage.getItem(KEYS.training),
  }
}

/** Memory gone, storage as it stood, then the one recovery pass the store
 *  module runs at import. */
async function relaunch(stored: Image = snapshot()) {
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

function observation(kg = 80): PersistedSetObservation {
  return {
    reps: 10,
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

function makeWorkout(exerciseIds: string[] = [BENCH, SQUAT]): Workout {
  const id = workouts().createWorkout({
    name: "Push",
    date: "2026-09-08",
    exerciseIds,
  })
  return workouts().workouts.find((item) => item.id === id)!
}

function logSet(exerciseId = BENCH, kg = 80) {
  const draft = records().data.activeWorkout!
  const entry = draft.exercises.find((item) => item.exerciseId === exerciseId)!
  records().addUnplannedSet({
    exerciseEntryId: entry.id,
    setType: "working",
    side: "both",
    observation: observation(kg),
  })
}

describe("interrupted workout transitions", () => {
  afterEach(() => vi.restoreAllMocks())
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

  it("leaves no journal entry once a transition has run", () => {
    const workout = makeWorkout()
    useActiveWorkout.getState().start(workout)
    expect(records().data.transition).toBeUndefined()
    logSet()
    useActiveWorkout.getState().finish()
    expect(records().data.transition).toBeUndefined()
    expect(records().data.sessions).toHaveLength(1)
  })

  describe("start", () => {
    it("carries nothing forward when the draft never landed", async () => {
      const workout = makeWorkout()
      // Boundary 1: the intent is written, the draft is not.
      const { recordStartIntent } = await import("@/lib/workout-transition")
      recordStartIntent(workout, Date.now())

      const outcome = await relaunch()

      expect(records().data.transition).toBeUndefined()
      expect(useActiveWorkout.getState().session).toBeNull()
      expect(records().data.activeWorkout).toBeNull()
      // Pressing start and getting nowhere is not a session.
      expect(records().data.sessions).toEqual([])
      expect(outcome.reason).toBe("idle")
    })

    it("puts the shell back when only the draft landed", async () => {
      const workout = makeWorkout()
      const { recordStartIntent } = await import("@/lib/workout-transition")
      recordStartIntent(workout, Date.parse("2026-09-08T10:00:00.000Z"))
      // Boundary 2: the draft is open, the shell was never exposed.
      records().startFreeWorkout(
        workout.exerciseIds,
        "2026-09-08T10:00:00.000Z",
        workout.id
      )

      await relaunch()

      const session = useActiveWorkout.getState().session!
      expect(session.workoutId).toBe(workout.id)
      expect(session.exerciseIds).toEqual(workout.exerciseIds)
      expect(session.startedAt).toBe(Date.parse("2026-09-08T10:00:00.000Z"))
      // The draft it belongs to is untouched and still live.
      expect(records().data.activeWorkout?.sourceWorkoutId).toBe(workout.id)
      expect(records().data.sessions).toEqual([])
      expect(records().data.transition).toBeUndefined()
    })

    it("does not rebuild a shell that is already running", async () => {
      const workout = makeWorkout()
      useActiveWorkout.getState().start(workout)
      logSet()
      useActiveWorkout.getState().toggleComplete(BENCH)
      // Boundary 3: everything landed, the note was never cleared.
      const { recordStartIntent } = await import("@/lib/workout-transition")
      recordStartIntent(workout, Date.now())
      const before = structuredClone(useActiveWorkout.getState().session)

      await relaunch()

      // Check marks and elapsed time are the person's, not the intent's.
      expect(useActiveWorkout.getState().session).toEqual(before)
      expect(records().data.activeWorkout!.exercises[0].sets).toHaveLength(1)
      expect(records().data.transition).toBeUndefined()
    })
  })

  describe("finish", () => {
    /** A workout mid-finish: intent written, nothing else applied yet. */
    async function finishIntent() {
      const workout = makeWorkout()
      useActiveWorkout.getState().start(workout)
      logSet(BENCH, 90)
      const { recordFinishIntent } = await import("@/lib/workout-transition")
      const intent = recordFinishIntent(useActiveWorkout.getState().session!, {
        durationMs: 1_800_000,
        completedAt: new Date(Date.now() + 1000).toISOString(),
      })
      return { workout, intent }
    }

    it("completes the whole finish when nothing else landed", async () => {
      const { workout, intent } = await finishIntent()

      await relaunch()

      // Boundary 1: legacy completion, structured session and shell all owed.
      expect(workouts().workouts[0].completion?.durationMs).toBe(1_800_000)
      expect(workouts().workouts[0].completion?.completedAt).toBe(
        intent.completedAt
      )
      const [saved] = records().data.sessions
      expect(saved.id).toBe(intent.sessionId)
      expect(saved.completedAt).toBe(intent.completedAt)
      expect(saved.status).toBe("completed")
      expect(saved.sourceWorkoutId).toBe(workout.id)
      expect(saved.exercises[0].sets[0].resistance).toMatchObject({ kg: 90 })
      expect(useActiveWorkout.getState().session).toBeNull()
      expect(records().data.transition).toBeUndefined()
    })

    it("does not replace a legacy completion that already landed", async () => {
      const { workout, intent } = await finishIntent()
      // Boundary 2: the legacy completion landed with its own numbers.
      workouts().completeWorkout(workout.id, {
        activeCalories: 999,
        completedAt: "2026-09-08T12:00:00.000Z",
        completedExerciseIds: [BENCH],
        durationMs: 4_242,
        healthSyncStatus: "not-requested",
        startedAt: "2026-09-08T11:00:00.000Z",
      })

      await relaunch()

      // The completion the person saw is the one that stands.
      expect(workouts().workouts[0].completion?.durationMs).toBe(4_242)
      expect(workouts().workouts[0].completion?.activeCalories).toBe(999)
      // The structured session still lands, under the intent's identity.
      expect(records().data.sessions).toHaveLength(1)
      expect(records().data.sessions[0].id).toBe(intent.sessionId)
      expect(records().data.transition).toBeUndefined()
    })

    it("writes no second session when the structured one already landed", async () => {
      const { intent } = await finishIntent()
      // Boundary 3: the draft was closed under the intent's identity.
      records().completeWorkout(
        "completed",
        intent.completedAt,
        intent.sessionId
      )
      const written = structuredClone(records().data.sessions)
      expect(written).toHaveLength(1)

      await relaunch()

      expect(records().data.sessions).toEqual(written)
      expect(useActiveWorkout.getState().session).toBeNull()
      expect(records().data.transition).toBeUndefined()
      expect(records().getTrainingHistory().sessions).toHaveLength(1)
    })

    it("only clears the note when every step already landed", async () => {
      const { workout, intent } = await finishIntent()
      // Boundary 4: every step applied, the note alone survives.
      workouts().completeWorkout(workout.id, {
        ...intent.legacy!,
        completedExerciseIds: [...intent.legacy!.completedExerciseIds],
      })
      records().completeWorkout(
        "completed",
        intent.completedAt,
        intent.sessionId
      )
      useActiveWorkout.setState({ session: null, lastOutcome: "finished" })
      const sessions = structuredClone(records().data.sessions)
      const completion = structuredClone(workouts().workouts[0].completion)

      await relaunch()

      expect(records().data.sessions).toEqual(sessions)
      expect(workouts().workouts[0].completion).toEqual(completion)
      expect(records().data.transition).toBeUndefined()
    })

    it("resumes to one deterministic completion however often it runs", async () => {
      const { intent } = await finishIntent()
      const image = snapshot()

      await relaunch(image)
      const first = {
        sessions: structuredClone(records().data.sessions),
        completion: structuredClone(workouts().workouts[0].completion),
      }
      // The same interrupted state, recovered again from scratch.
      await relaunch(image)
      reconcileRestoredActiveWorkout()
      reconcileRestoredActiveWorkout()

      // The completion itself is fixed by the intent: same identity, same
      // instant, same status, same sets, and never a second session. Only the
      // record-local identities are stable too.
      expect(records().data.sessions).toEqual(first.sessions)
      expect(workouts().workouts[0].completion).toEqual(first.completion)
      const [replayed] = records().data.sessions
      expect(replayed.id).toBe(intent.sessionId)
      expect(replayed.completedAt).toBe(intent.completedAt)
      expect(replayed.status).toBe(first.sessions[0].status)
      expect(replayed.durationSeconds).toBe(first.sessions[0].durationSeconds)
      expect(
        replayed.exercises.map((exercise) => [
          exercise.exerciseId,
          exercise.sets.map((set) => [set.reps, set.resistance, set.rir]),
        ])
      ).toEqual(
        first.sessions[0].exercises.map((exercise) => [
          exercise.exerciseId,
          exercise.sets.map((set) => [set.reps, set.resistance, set.rir]),
        ])
      )
    })

    it("records no session for a finish that had nothing to save", async () => {
      const workout = makeWorkout()
      useActiveWorkout.getState().start(workout)
      useActiveWorkout.getState().toggleComplete(BENCH)
      const { recordFinishIntent } = await import("@/lib/workout-transition")
      recordFinishIntent(useActiveWorkout.getState().session!, {
        durationMs: 60_000,
      })

      await relaunch()

      // A check mark is not a set: the legacy record still completes, and
      // nothing fictional reaches structured history.
      expect(workouts().workouts[0].completion).not.toBeNull()
      expect(records().data.sessions).toEqual([])
      expect(records().data.activeWorkout).toBeNull()
      expect(records().data.transition).toBeUndefined()
    })
  })

  describe("cancel", () => {
    it("keeps the sets a discarded session produced", async () => {
      const workout = makeWorkout()
      useActiveWorkout.getState().start(workout)
      logSet(BENCH, 70)
      const { recordCancelIntent } = await import("@/lib/workout-transition")
      recordCancelIntent(useActiveWorkout.getState().session!)

      await relaunch()

      const [saved] = records().data.sessions
      expect(saved.status).toBe("partial")
      expect(saved.sourceWorkoutId).toBe(workout.id)
      expect(saved.exercises[0].sets[0].resistance).toMatchObject({ kg: 70 })
      expect(workouts().workouts[0].completion).toBeNull()
      expect(useActiveWorkout.getState().session).toBeNull()
      expect(records().data.transition).toBeUndefined()
    })

    it("leaves nothing behind when the session logged nothing", async () => {
      const workout = makeWorkout()
      useActiveWorkout.getState().start(workout)
      const { recordCancelIntent } = await import("@/lib/workout-transition")
      recordCancelIntent(useActiveWorkout.getState().session!)

      await relaunch()

      expect(records().data.sessions).toEqual([])
      expect(records().data.activeWorkout).toBeNull()
      expect(workouts().workouts[0].completion).toBeNull()
    })
  })

  describe("recovery write failures", () => {
    it.each([KEYS.workouts, KEYS.training])(
      "keeps a failed finish pending when %s fails",
      async (failedKey) => {
        const workout = makeWorkout()
        useActiveWorkout.getState().start(workout)
        logSet()
        const { recordFinishIntent } = await import("@/lib/workout-transition")
        const intent = recordFinishIntent(
          useActiveWorkout.getState().session!,
          { durationMs: 1000 }
        )
        const draft = structuredClone(records().data.activeWorkout)
        const original = localStorage.setItem.bind(localStorage)
        const write = vi
          .spyOn(localStorage, "setItem")
          .mockImplementation(function (key, value) {
            if (key === failedKey) throw new Error("disk full")
            return original(key, value)
          })
        expect(() => useActiveWorkout.getState().finish()).toThrow("disk full")
        expect(records().data.transition).toEqual(intent)
        expect(records().data.activeWorkout).toEqual(draft)
        expect(useActiveWorkout.getState().session?.workoutId).toBe(workout.id)
        write.mockRestore()
        useActiveWorkout.getState().finish()
        expect(records().data.sessions).toHaveLength(1)
        expect(records().data.sessions[0].id).toBe(intent.sessionId)
        expect(records().data.sessions[0].completedAt).toBe(intent.completedAt)
        expect(records().data.transition).toBeUndefined()
      }
    )

    it("retains the start intent until the restored shell is durable", async () => {
      const workout = makeWorkout()
      const { recordStartIntent, recoverWorkoutTransition } =
        await import("@/lib/workout-transition")
      const startedAt = new Date().toISOString()
      recordStartIntent(workout, Date.parse(startedAt))
      records().startFreeWorkout(workout.exerciseIds, startedAt, workout.id)
      const intent = structuredClone(records().data.transition)
      expect(recoverWorkoutTransition().shell).toBe("restore")
      expect(records().data.transition).toEqual(intent)
      // Crash after draft recovery, before its caller persists the shell.
      await relaunch()
      expect(useActiveWorkout.getState().session?.workoutId).toBe(workout.id)
      expect(records().data.sessions).toEqual([])
      expect(records().data.transition).toBeUndefined()
    })

    it("does not clear a newer coherent workout because of a stale cancel", async () => {
      const first = makeWorkout()
      useActiveWorkout.getState().start(first)
      const { recordCancelIntent } = await import("@/lib/workout-transition")
      const stale = recordCancelIntent(useActiveWorkout.getState().session!)
      records().clearTransition()
      useActiveWorkout.getState().cancel()
      const next = makeWorkout()
      useActiveWorkout.getState().start(next)
      logSet()
      const draft = structuredClone(records().data.activeWorkout)
      records().beginTransition(stale)
      await relaunch()
      expect(useActiveWorkout.getState().session?.workoutId).toBe(next.id)
      expect(records().data.activeWorkout).toEqual(draft)
      expect(records().data.sessions).toEqual([])
    })
  })

  it("preserves new observations when a cancelled manual workout is attempted again", async () => {
    const workout = makeWorkout()
    useActiveWorkout.getState().start(workout)
    logSet(BENCH, 70)
    useActiveWorkout.getState().cancel()
    vi.setSystemTime(new Date("2026-09-01T14:00:00.000Z"))
    useActiveWorkout.getState().start(workout)
    logSet(BENCH, 80)
    await relaunch()
    expect(records().data.activeWorkout).not.toBeNull()
    useActiveWorkout.getState().finish()
    expect(records().data.sessions).toHaveLength(2)
    expect(
      records().data.sessions.map(
        (session) => session.exercises[0].sets[0].resistance
      )
    ).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ kg: 70 }),
        expect.objectContaining({ kg: 80 }),
      ])
    )
  })

  describe("the journal itself", () => {
    it("refuses a malformed intent rather than storing it", () => {
      const issues = validatePersistedTrainingState({
        ...createEmptyPersistedTrainingState(),
        // A finish with no completion instant cannot be replayed determinis-
        // tically, so it must never become stored state.
        transition: {
          id: "t1",
          kind: "finish",
          recordedAt: "2026-09-08T10:00:00.000Z",
          sourceWorkoutId: "w1",
        },
      })
      expect(issues).toHaveLength(1)
      expect(issues[0].path).toBe("transition")
    })

    it("drops a corrupt intent while keeping the observations", async () => {
      const workout = makeWorkout()
      useActiveWorkout.getState().start(workout)
      logSet(BENCH, 60)
      const image = snapshot()
      const training = JSON.parse(image.training!)
      training.state.data.transition = { id: "", kind: "finish" }

      const outcome = await relaunch({
        ...image,
        training: JSON.stringify(training),
      })

      // Nothing was replayed from a note that could not be read, and the
      // reconciliation layer took the state from there.
      expect(records().data.transition).toBeUndefined()
      expect(outcome.reason).toBe("coherent")
      expect(
        records().data.activeWorkout!.exercises[0].sets[0].observation
      ).toMatchObject({ reps: 10 })
    })

    it("does nothing when no transition was in flight", () => {
      const plan = planTransitionRecovery({
        intent: undefined,
        draft: null,
        sessions: [],
        workoutCompleted: false,
        workoutExists: false,
      })
      expect(plan).toMatchObject({
        reason: "none",
        draft: "keep",
        shell: "keep",
        clearIntent: false,
      })
    })

    it("abandons an intent whose workout is gone", () => {
      const plan = planTransitionRecovery({
        intent: {
          id: "t1",
          kind: "finish",
          recordedAt: "2026-09-08T10:00:00.000Z",
          sourceWorkoutId: "gone",
          completedAt: "2026-09-08T10:30:00.000Z",
          sessionId: "s1",
          status: "completed",
        },
        draft: null,
        sessions: [],
        workoutCompleted: false,
        workoutExists: false,
      })
      expect(plan).toMatchObject({ reason: "intent-stale", clearIntent: true })
      expect(plan.legacy).toBeUndefined()
    })
  })
})
