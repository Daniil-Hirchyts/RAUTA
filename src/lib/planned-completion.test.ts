import { beforeEach, describe, expect, it } from "vitest"

import { substituteRunningPlannedExercise } from "@/lib/planned-substitution"
import {
  createTrainingWeek,
  plannedWorkoutFor,
  type PlannedSessionView,
} from "@/lib/training-plan"
import { replacementIds } from "@/lib/training-workflow"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useFilters } from "@/store/use-filters"
import { DEFAULT_SETTINGS, useSettings } from "@/store/use-settings"
import { useTrainingProfile } from "@/store/use-training-profile"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts, type Workout } from "@/store/use-workouts"
import {
  createEmptyPersistedTrainingState,
  type PersistedSetObservation,
} from "@/training-persistence/schema"
import { plannedWorkCoverage } from "@/training-persistence/workout"

/**
 * What "completed" is allowed to mean.
 *
 * A planned session carries a prescription, and the deterministic engine reads
 * the difference between a prescription that was carried out and one that was
 * cut short. So the status of a structured session is decided by the sets that
 * were really performed, never by the button that closed the screen — and
 * never by a check mark, a target, or an extra set logged next to the one
 * nobody did.
 */

const records = () => useTrainingRecords.getState()
const NOW = "2026-09-07T10:00:00.000Z"

function week() {
  const outcome = createTrainingWeek({ days: [0, 2, 4], now: NOW })
  if (outcome.status !== "created") throw new Error(outcome.message)
  return outcome.sessions
}

function observation(reps = 8): PersistedSetObservation {
  return {
    reps,
    rir: 2,
    resistance: {
      type: "external_load",
      kg: 40,
      basis: "total",
      stationId: "Rack A",
    },
    completed: true,
  }
}

function startPlanned(view: PlannedSessionView): Workout {
  const workout = plannedWorkoutFor(view)!
  expect(useActiveWorkout.getState().start(workout)).toBe(true)
  return workout
}

/** Every planned set of the draft that is prescribed work rather than warmup,
 *  as `{ exerciseEntryId, setDraftId }` pairs taken before anything is logged
 *  — draft entries are replaced on every write, but their IDs are stable. */
function prescribedSets() {
  return records().data.activeWorkout!.exercises.flatMap((exercise) =>
    exercise.sets
      .filter((set) => set.plannedSetId && set.setType !== "warmup")
      .map((set) => ({ exerciseEntryId: exercise.id, setDraftId: set.id }))
  )
}

function logSets(
  targets: readonly { exerciseEntryId: string; setDraftId: string }[]
) {
  for (const target of targets)
    records().recordSet({ ...target, observation: observation() })
}

describe("planned session completion", () => {
  beforeEach(() => {
    localStorage.clear()
    useTrainingRecords.setState({
      data: createEmptyPersistedTrainingState(),
      persistenceIssues: [],
    })
    useWorkouts.setState({ workouts: [] })
    useActiveWorkout.setState({ session: null, lastOutcome: null })
    useTrainingProfile.getState().resetTrainingProfile()
    useSettings.setState(DEFAULT_SETTINGS)
    useFilters.setState({
      equipmentPresets: [],
      gymEquipment: ["dumbbell"],
      selectedEquipment: [],
      selectedMuscles: [],
    })
  })

  it("records a fully performed prescription as completed", () => {
    const sessions = week()
    startPlanned(sessions[0])
    const prescribed = prescribedSets()
    expect(prescribed.length).toBeGreaterThan(1)

    logSets(prescribed)
    useActiveWorkout.getState().finish()

    const [saved] = records().data.sessions
    expect(saved.status).toBe("completed")
    expect(saved.plannedSessionId).toBe(sessions[0].sessionId)
    expect(saved.exercises.flatMap((item) => item.sets)).toHaveLength(
      prescribed.length
    )
  })

  it("records a prescription that was cut short as partial, even on Finish", () => {
    const sessions = week()
    startPlanned(sessions[0])
    const prescribed = prescribedSets()

    logSets(prescribed.slice(0, 1))
    useActiveWorkout.getState().finish()

    const [saved] = records().data.sessions
    expect(saved.status).toBe("partial")
    expect(saved.exercises.flatMap((item) => item.sets)).toHaveLength(1)
    // Finishing early is still finishing: the session closes and the legacy
    // workout keeps its duration.
    expect(useActiveWorkout.getState().session).toBeNull()
    expect(useActiveWorkout.getState().lastOutcome).toBe("finished")
    expect(records().data.activeWorkout).toBeNull()
  })

  it("leaves an untouched planned exercise without a single observation", () => {
    const sessions = week()
    startPlanned(sessions[0])
    const draft = records().data.activeWorkout!
    const untouched = draft.exercises.slice(1)
    expect(untouched.length).toBeGreaterThan(0)

    const first = draft.exercises[0]
    logSets(
      first.sets
        .filter((set) => set.setType !== "warmup")
        .map((set) => ({ exerciseEntryId: first.id, setDraftId: set.id }))
    )
    useActiveWorkout.getState().finish()

    const live = records().data.sessions[0]
    expect(live.status).toBe("partial")
    expect(live.exercises.map((item) => item.exerciseId)).toEqual([
      first.exerciseId,
    ])
    for (const exercise of untouched)
      expect(
        live.exercises.some((item) => item.exerciseId === exercise.exerciseId)
      ).toBe(false)
  })

  it("counts a substituted exercise against the prescription it replaced", () => {
    const sessions = week()
    const workout = startPlanned(sessions[0])
    const before = records().data.activeWorkout!.exercises[0]
    const replacementId = replacementIds(before.exerciseId).find(
      (exerciseId) => !workout.exerciseIds.includes(exerciseId)
    )!

    substituteRunningPlannedExercise(
      workout.id,
      before.exerciseId,
      replacementId
    )

    const after = records().data.activeWorkout!.exercises.find(
      (exercise) => exercise.id === before.id
    )!
    expect(after.exerciseId).toBe(replacementId)
    expect(after.plannedExerciseId).toBe(before.plannedExerciseId)

    logSets(prescribedSets())
    useActiveWorkout.getState().finish()

    // A different movement, but the same prescription: the planned lineage is
    // what coverage follows, so the session is complete.
    const [saved] = records().data.sessions
    expect(saved.status).toBe("completed")
    const substituted = saved.exercises.find(
      (item) => item.exerciseId === replacementId
    )!
    expect(substituted.plannedExerciseId).toBe(before.plannedExerciseId)
  })

  it("does not let extra sets stand in for prescribed work nobody did", () => {
    const sessions = week()
    startPlanned(sessions[0])
    const draft = records().data.activeWorkout!
    const first = draft.exercises[0]
    const prescribed = prescribedSets()
    const outstanding = prescribed.filter(
      (target) => target.exerciseEntryId !== first.id
    )
    expect(outstanding.length).toBeGreaterThan(0)

    logSets(prescribed.filter((target) => target.exerciseEntryId === first.id))
    // Real work, freely chosen — and more of it than the plan left outstanding.
    for (let index = 0; index <= outstanding.length; index += 1)
      records().addUnplannedSet({
        exerciseEntryId: first.id,
        setType: "working",
        side: "both",
        observation: observation(),
      })

    useActiveWorkout.getState().finish()

    const [saved] = records().data.sessions
    expect(saved.status).toBe("partial")
    // The extra sets are kept: they happened. They just answer no prescription.
    expect(
      saved.exercises[0].sets.filter((set) => set.plannedSetId === undefined)
    ).toHaveLength(outstanding.length + 1)
  })

  it("keeps an unlogged warmup out of the judgement", () => {
    const sessions = week()
    startPlanned(sessions[0])
    const warmups = records().data.activeWorkout!.exercises.flatMap(
      (exercise) => exercise.sets.filter((set) => set.setType === "warmup")
    )
    expect(warmups.length).toBeGreaterThan(0)

    logSets(prescribedSets())
    useActiveWorkout.getState().finish()

    // A warmup prepares for the prescription rather than being it.
    expect(records().data.sessions[0].status).toBe("completed")
  })

  it("measures against the snapshot, not against an edited draft", () => {
    const sessions = week()
    startPlanned(sessions[0])
    const warmup = records()
      .data.activeWorkout!.exercises.flatMap((exercise) =>
        exercise.sets.map((set) => ({ exerciseEntryId: exercise.id, set }))
      )
      .find((item) => item.set.setType === "warmup")!
    expect(warmup).toBeDefined()

    // Everything the snapshot actually prescribes, settled before the draft is
    // touched, so the relabelled warmup below stays unlogged.
    const prescribed = prescribedSets()
    // The draft is a working copy and its set types are writable. Whatever it
    // ends up claiming, the prescription is the one in the immutable snapshot.
    records().updateSetDetails(warmup.exerciseEntryId, warmup.set.id, {
      setType: "working",
      side: warmup.set.side,
    })
    logSets(prescribed)
    useActiveWorkout.getState().finish()

    // The relabelled warmup was never prescribed work, so leaving it unlogged
    // cannot hold the session open.
    const [saved] = records().data.sessions
    expect(saved.status).toBe("completed")
    expect(
      saved.exercises.some((exercise) =>
        exercise.sets.some(
          (set) => set.plannedSetId === warmup.set.plannedSetId
        )
      )
    ).toBe(false)
  })

  it("never certifies a prescription it cannot read", () => {
    const sessions = week()
    startPlanned(sessions[0])
    logSets(prescribedSets())
    const draft = records().data.activeWorkout!

    // Store validation keeps a planned draft's program resolvable, so this is
    // the guard behind that invariant rather than a reachable screen: with no
    // snapshot to measure against, every prescribed set being logged still
    // proves nothing about what was prescribed.
    const unreadable = plannedWorkCoverage(draft, null)!
    expect(unreadable.verified).toBe(false)
    expect(unreadable.complete).toBe(false)
    expect(unreadable.performed).toBe(unreadable.prescribed)

    // A snapshot for some other session is no more of an answer than none.
    const other = plannedWorkCoverage(draft, {
      id: "some-other-session",
      scheduledAt: sessions[0].date,
      focus: [],
      exercises: [],
      duration: {
        generalWarmupSeconds: 0,
        specificWarmupSeconds: 0,
        workingSetSeconds: 0,
        restSeconds: 0,
        transitionSeconds: 0,
        totalSeconds: 0,
        confidence: "none",
      },
    })!
    expect(other.verified).toBe(false)
    expect(other.complete).toBe(false)
  })

  it("keeps a discarded session partial however much of it was performed", () => {
    const sessions = week()
    startPlanned(sessions[0])
    logSets(prescribedSets())

    useActiveWorkout.getState().cancel()

    expect(records().data.sessions[0].status).toBe("partial")
  })

  it("writes no structured session when a planned workout logged nothing", () => {
    const sessions = week()
    const workout = startPlanned(sessions[0])

    useActiveWorkout.getState().finish()

    expect(records().data.sessions).toEqual([])
    expect(records().data.activeWorkout).toBeNull()
    // The workout itself still happened: legacy duration and calories stand.
    expect(
      useWorkouts.getState().workouts.find((item) => item.id === workout.id)
        ?.completion
    ).toBeTruthy()
  })

  it("finishes a free workout as completed, as it always has", () => {
    const workoutId = useWorkouts.getState().createWorkout({
      name: "Push",
      date: "2026-09-08",
      exerciseIds: ["0025", "0043"],
    })
    const workout = useWorkouts
      .getState()
      .workouts.find((item) => item.id === workoutId)!
    expect(useActiveWorkout.getState().start(workout)).toBe(true)

    const draft = records().data.activeWorkout!
    records().addUnplannedSet({
      exerciseEntryId: draft.exercises[0].id,
      setType: "working",
      side: "both",
      observation: observation(),
    })
    useActiveWorkout.getState().finish()

    // Nothing was prescribed, so nothing can be outstanding — one logged set
    // and a second listed exercise still make a completed session.
    const [saved] = records().data.sessions
    expect(saved.status).toBe("completed")
    expect(saved.plannedSessionId).toBeUndefined()
    expect(saved.exercises).toHaveLength(1)
  })

  it("leaves the program snapshot byte-for-byte unchanged", () => {
    const sessions = week()
    const original = JSON.stringify(records().data.programs)
    startPlanned(sessions[0])

    logSets(prescribedSets().slice(0, 1))
    useActiveWorkout.getState().finish()

    expect(records().data.sessions[0].status).toBe("partial")
    expect(JSON.stringify(records().data.programs)).toBe(original)
  })
})
