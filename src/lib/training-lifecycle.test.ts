import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import { substituteRunningPlannedExercise } from "@/lib/planned-substitution"
import {
  adjustRemainingWeek,
  createNextTrainingWeek,
} from "@/lib/training-adaptation"
import {
  activePlannedSessions,
  activeProgramRecord,
  createTrainingWeek,
  plannedWorkoutFor,
} from "@/lib/training-plan"
import { nextPerformance, replacementIds } from "@/lib/training-workflow"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useFilters } from "@/store/use-filters"
import { useTrainingProfile } from "@/store/use-training-profile"
import {
  TRAINING_STORAGE_KEY,
  useTrainingRecords,
} from "@/store/use-training-records"
import { useWorkouts } from "@/store/use-workouts"
import { createEmptyPersistedTrainingState } from "@/training-persistence/schema"
import { isStartablePlannedSession } from "@/training-persistence/program"

/**
 * One person, one month, through every state the product has.
 *
 * The individual transitions each have their own tests. This one walks the
 * whole lifecycle in order — profile, equipment, plan, perform, substitute,
 * finish short, crash, adapt, finish the week, plan the next one — and checks
 * at every step that the things which must never happen still have not: no
 * prescription counted as performance, no fabricated set, no mutated snapshot,
 * no lost lineage, no session written twice, and no load carried across a
 * station it was never measured at.
 */
const records = () => useTrainingRecords.getState()
const START = "2026-09-07T10:00:00.000Z"

function trainedSets(sessionId: string) {
  return records()
    .data.sessions.find((session) => session.id === sessionId)!
    .exercises.flatMap((exercise) => exercise.sets)
}

beforeEach(() => {
  localStorage.clear()
  useTrainingRecords.setState({
    data: createEmptyPersistedTrainingState(),
    persistenceIssues: [],
  })
  useWorkouts.setState({ workouts: [] })
  useActiveWorkout.setState({ session: null, lastOutcome: null })
  useTrainingProfile.getState().resetTrainingProfile()
  useFilters.setState({
    equipmentPresets: [],
    equipmentLoadIncrements: {},
    gymEquipment: ["dumbbell", "barbell"],
    selectedEquipment: [],
    selectedMuscles: [],
  })
})

afterEach(() => vi.restoreAllMocks())

describe("the whole training lifecycle", () => {
  it("carries real performance from a first week into the next one", async () => {
    // 1. Profile and equipment: everything the engine needs is already saved,
    // so creating a week asks only which days are free.
    useTrainingProfile.getState().updateProfile({
      age: 34,
      goal: "hypertrophy",
      trainingExperience: "intermediate",
      preferredSessionDurationMinutes: 45,
    })
    useFilters.getState().setEquipmentLoadIncrement("dumbbell", 2)

    // 2. Create the plan.
    const created = createTrainingWeek({ days: [0, 2, 4], now: START })
    if (created.status !== "created") throw new Error(created.message)
    const programId = created.programId
    // Compared through JSON, which is how the snapshot is actually stored:
    // what must not change is every value the program states.
    const stateOf = (id: string) =>
      JSON.parse(
        JSON.stringify(
          records().data.programs.find((item) => item.id === id)!.snapshot
        )
      )
    const snapshot = stateOf(programId)
    expect(created.sessions).toHaveLength(3)

    // 3. Inspect the planned workout: it exists on the workout list as an
    // ordinary workout, with a prescription and no performance.
    const first = created.sessions[0]
    const workout = plannedWorkoutFor(first)!
    expect(workout.planned).toEqual({ programId, sessionId: first.sessionId })
    expect(workout.completion ?? null).toBeNull()
    expect(records().data.sessions).toEqual([])

    // 4. Start it through the ordinary Start button.
    vi.setSystemTime(new Date(`${first.date}T10:00:00.000Z`))
    expect(useActiveWorkout.getState().start(workout)).toBe(true)
    const draft = records().data.activeWorkout!
    expect(draft).toMatchObject({
      plannedProgramId: programId,
      plannedSessionId: first.sessionId,
      sourceWorkoutId: workout.id,
    })
    // Prescribed sets are listed and none of them is an observation.
    expect(draft.exercises.flatMap((item) => item.sets).length).toBeGreaterThan(
      0
    )
    expect(
      draft.exercises
        .flatMap((item) => item.sets)
        .every((set) => set.observation === undefined)
    ).toBe(true)

    // 5. Substitute one prescribed exercise, keeping its planned lineage.
    const planned = draft.exercises[0]
    const replacement = replacementIds(planned.exerciseId)[0]
    substituteRunningPlannedExercise(
      workout.id,
      planned.exerciseId,
      replacement
    )
    const substituted = records().data.activeWorkout!.exercises.find(
      (item) => item.id === planned.id
    )!
    expect(substituted.exerciseId).toBe(replacement)
    expect(substituted.plannedExerciseId).toBe(planned.exerciseId)
    expect(stateOf(programId)).toEqual(snapshot)

    // 6. Log two sets of the substitute and nothing else, then finish. Only
    // part of the prescription was performed, so this is a partial session.
    for (const set of substituted.sets
      .filter((item) => item.setType === "working")
      .slice(0, 2))
      records().recordSet({
        exerciseEntryId: substituted.id,
        setDraftId: set.id,
        observation: {
          reps: 12,
          rir: 2,
          resistance: {
            type: "external_load",
            kg: 30,
            stationId: "dumbbell",
            basis: "per_implement",
          },
          completed: true,
          timestamp: `${first.date}T10:20:00.000Z`,
        },
      })
    vi.setSystemTime(new Date(`${first.date}T10:30:00.000Z`))
    useActiveWorkout.getState().finish()

    const partial = records().data.sessions.at(-1)!
    expect(partial).toMatchObject({
      status: "partial",
      plannedProgramId: programId,
      plannedSessionId: first.sessionId,
      sourceWorkoutId: workout.id,
    })
    expect(trainedSets(partial.id)).toHaveLength(2)
    // The substitute's sets keep the prescription they answered.
    expect(
      trainedSets(partial.id).every((set) => Boolean(set.plannedSetId))
    ).toBe(true)
    expect(records().data.activeWorkout).toBeNull()
    expect(records().data.transition).toBeUndefined()

    // 7. A reload changes nothing: recovery is idempotent and writes no second
    // session for work history already holds.
    const stored = localStorage.getItem(TRAINING_STORAGE_KEY)!
    useTrainingRecords.setState({
      data: createEmptyPersistedTrainingState(),
      persistenceIssues: [],
    })
    localStorage.setItem(TRAINING_STORAGE_KEY, stored)
    await useTrainingRecords.persist.rehydrate()
    expect(records().data.sessions).toHaveLength(1)
    expect(records().data.sessions[0].id).toBe(partial.id)

    // 8. Adapt the rest of the week from what was actually performed. The
    // source program survives byte for byte and its future slots are replaced.
    vi.setSystemTime(new Date(`${created.sessions[1].date}T06:00:00.000Z`))
    const adjusted = adjustRemainingWeek()
    expect(adjusted.status).toBe("adjusted")
    const revision = activeProgramRecord()!
    expect(revision.id).not.toBe(programId)
    expect(revision.revision).toMatchObject({
      sourceProgramId: programId,
      incorporatedSessionIds: [partial.id],
    })
    expect(stateOf(programId)).toEqual(snapshot)
    // The session already performed stays performed and cannot be started
    // again from the superseded plan.
    expect(
      isStartablePlannedSession(records().data, programId, first.sessionId)
    ).toBe(false)
    // The same observation cannot be incorporated twice.
    expect(adjustRemainingWeek()).toMatchObject({
      status: "blocked",
      reason: "incorporated",
    })

    // 9. Perform the rest of the revised week at a real load.
    for (const session of activePlannedSessions()) {
      const scheduled = plannedWorkoutFor(session)!
      vi.setSystemTime(new Date(`${session.date}T10:00:00.000Z`))
      if (!useActiveWorkout.getState().start(scheduled)) continue
      const entry = records().data.activeWorkout!.exercises[0]
      for (const set of entry.sets.filter((item) => item.setType === "working"))
        records().recordSet({
          exerciseEntryId: entry.id,
          setDraftId: set.id,
          observation: {
            reps: 12,
            rir: 2,
            resistance: {
              type: "external_load",
              kg: 30,
              stationId: "dumbbell",
              basis: "per_implement",
            },
            completed: true,
            timestamp: `${session.date}T10:20:00.000Z`,
          },
        })
      vi.setSystemTime(new Date(`${session.date}T10:30:00.000Z`))
      useActiveWorkout.getState().finish()
    }

    // 10. The week is over: the next one comes from the same lineage.
    vi.setSystemTime(new Date("2026-09-21T08:00:00.000Z"))
    const next = createNextTrainingWeek({
      days: [0, 2, 4],
      sourceProgramId: revision.id,
    })
    expect(next.status).toBe("created")
    const nextRecord = activeProgramRecord()!
    expect(nextRecord.revision?.sourceProgramId).toBe(revision.id)
    expect(stateOf(programId)).toEqual(snapshot)
    // Duplicate next weeks are refused rather than stacked.
    expect(
      createNextTrainingWeek({ days: [0, 2, 4], sourceProgramId: revision.id })
    ).toMatchObject({ status: "blocked", reason: "already_planned" })

    // 11. Progression reads the real sets, at the station they were logged at,
    // in the basis they were logged in.
    const exerciseId = records()
      .data.sessions.flatMap((session) => session.exercises)
      .at(-1)!.exerciseId
    const recommendation = nextPerformance(
      {
        id: "probe",
        exerciseId,
        sets: [{ id: "probe-set", setType: "working", side: "both" }],
      },
      "2026-09-21T09:00:00.000Z"
    )!
    expect(recommendation.resistance).toMatchObject({
      type: "external_load",
      basis: "per_implement",
      stationId: "dumbbell",
    })
    // Two-kilogram dumbbells: the step comes from the equipment page, and the
    // load from sets that were really logged.
    expect(recommendation.resistance).toMatchObject({ kg: 32 })
    expect(recommendation.reasons).toContain("top_of_range")

    // Nothing anywhere in the lifecycle invented a session or a set.
    expect(
      records().data.sessions.every((session) =>
        session.exercises.every((exercise) =>
          exercise.sets.every((set) => set.completed)
        )
      )
    ).toBe(true)
    expect(records().persistenceIssues).toEqual([])
  }, 60000)
})
