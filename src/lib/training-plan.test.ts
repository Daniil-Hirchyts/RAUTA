import { beforeEach, describe, expect, it, vi } from "vitest"

import { EXERCISES_BY_ID } from "@/lib/exercises"
import { buildTrainingEngineInputs } from "@/lib/training-engine-adapter"
import {
  activePlannedSessions,
  createTrainingWeek,
  ensurePlannedWorkout,
  isPlannedSessionRecorded,
  plannedSessionTitle,
  plannedSessionView,
  plannedWorkoutFor,
} from "@/lib/training-plan"
import { beginTrainingDraft } from "@/lib/training-session"
import { buildTrainingRequest, trainingIndex } from "@/lib/training-workflow"
import { useFilters } from "@/store/use-filters"
import { DEFAULT_SETTINGS, useSettings } from "@/store/use-settings"
import { useTrainingProfile } from "@/store/use-training-profile"
import {
  TRAINING_STORAGE_KEY,
  useTrainingRecords,
} from "@/store/use-training-records"
import { useWorkouts } from "@/store/use-workouts"
import { createEmptyPersistedTrainingState } from "@/training-persistence/schema"

const records = () => useTrainingRecords.getState()

/** Every generated week in this file is asked for from the same instant, so a
 *  schedule is a fixed set of calendar days rather than "whenever the suite
 *  happened to run". */
const NOW = "2026-09-07T10:00:00.000Z"

function reset() {
  localStorage.clear()
  useTrainingRecords.setState({
    data: createEmptyPersistedTrainingState(),
    persistenceIssues: [],
  })
  useWorkouts.setState({ workouts: [] })
  useTrainingProfile.getState().resetTrainingProfile()
  useSettings.setState(DEFAULT_SETTINGS)
  useFilters.setState({
    equipmentPresets: [],
    gymEquipment: [],
    selectedEquipment: [],
    selectedMuscles: [],
  })
}

function createdWeek(days: number[] = [0, 2, 4]) {
  const outcome = createTrainingWeek({ days, now: NOW })
  if (outcome.status !== "created")
    throw new Error(`Expected a week, got: ${outcome.message}`)
  return outcome
}

describe("engine-generated planned sessions", () => {
  beforeEach(() => {
    reset()
    useFilters.getState().setGymEquipment(["dumbbell"])
  })

  it("builds the engine request from the saved profile rather than asking again", () => {
    useTrainingProfile.getState().updateProfile({
      age: 41,
      goal: "hypertrophy",
      preferredSessionDurationMinutes: 45,
      trainingExperience: "advanced",
    })
    useTrainingProfile.getState().setMusclePriority("chest", "specialization")
    useFilters.getState().setGymEquipment(["barbell"])

    const request = buildTrainingRequest(
      buildTrainingEngineInputs(),
      NOW,
      undefined,
      [1, 3]
    )

    expect(request.profile).toMatchObject({
      age: 41,
      trainingExperience: "advanced",
      health: { status: "healthy" },
    })
    expect(request.preferences).toMatchObject({
      goal: "hypertrophy",
      preferredSessionDurationMinutes: 45,
      priorityMuscles: [{ muscleId: "chest", level: "specialization" }],
    })
    // The one genuinely week-specific answer is the only one that came from
    // outside the saved profile.
    expect(request.schedule.days).toEqual([1, 3])
  })

  it("only prescribes exercises the saved equipment can actually run", () => {
    useFilters.getState().setGymEquipment(["dumbbell"])
    const week = createdWeek([0, 2])

    const prescribed = new Set(
      week.sessions.flatMap((session) => session.exerciseIds)
    )
    expect(prescribed.size).toBeGreaterThan(0)
    // Body weight is the one thing the engine treats as always on hand; every
    // other requirement has to be something the profile actually saved.
    const allowed = new Set([
      "body weight",
      ...buildTrainingEngineInputs().preferences.availableEquipment,
    ])
    for (const exerciseId of prescribed) {
      const metadata = trainingIndex().byId.get(exerciseId)?.metadata
      for (const item of metadata?.requiredEquipment ?? [])
        expect(allowed.has(item), `${exerciseId} needs ${item}`).toBe(true)
    }
    expect(allowed.has("barbell")).toBe(false)
    expect(allowed.has("cable")).toBe(false)
  })

  it("carries structured history into the request without double-counting the workout it came from", () => {
    const week = createdWeek([0, 2, 4])
    const session = week.sessions[0]
    const workoutId = ensurePlannedWorkout(session)
    records().startPlannedWorkout(
      session.programId,
      session.sessionId,
      "2026-09-14T10:00:00.000Z",
      workoutId
    )
    const draft = records().data.activeWorkout!
    const exercise = draft.exercises[0]
    const set = exercise.sets.find((item) => item.setType === "working")!
    records().recordSet({
      exerciseEntryId: exercise.id,
      setDraftId: set.id,
      observation: {
        reps: 10,
        rir: 1,
        resistance: {
          type: "external_load",
          kg: 22.5,
          stationId: "Rack 1",
          basis: "total",
        },
        completed: true,
        timestamp: "2026-09-14T10:04:00.000Z",
      },
    })
    records().completeWorkout("completed", "2026-09-14T11:00:00.000Z")

    const history = records().getTrainingHistory([
      {
        id: workoutId,
        completion: {
          startedAt: "2026-09-14T10:00:00.000Z",
          completedAt: "2026-09-14T11:00:00.000Z",
          durationMs: 3_600_000,
          completedExerciseIds: [exercise.exerciseId],
        },
      },
    ])
    expect(history.sessions).toHaveLength(1)
    expect(history.sessions[0].exercises[0].sets[0]).toMatchObject({
      reps: 10,
      resistance: { kg: 22.5 },
    })

    const request = buildTrainingRequest(buildTrainingEngineInputs(), NOW)
    expect(request.history.sessions[0].exercises[0].sets[0]).toMatchObject({
      reps: 10,
      rir: 1,
    })
  })

  it("persists the program, activates it and restores both after a reload", async () => {
    const week = createdWeek([0, 2, 4])

    expect(records().data.programs).toHaveLength(1)
    expect(records().data.activeProgramId).toBe(week.programId)
    // Compared as it is stored: JSON is what a reload actually gets back.
    const snapshot = JSON.parse(
      JSON.stringify(records().data.programs[0])
    ) as unknown

    // A relaunch: memory is gone, and only what reached storage comes back.
    const stored = localStorage.getItem(TRAINING_STORAGE_KEY)!
    useTrainingRecords.setState({
      data: createEmptyPersistedTrainingState(),
      persistenceIssues: [],
    })
    localStorage.setItem(TRAINING_STORAGE_KEY, stored)
    await useTrainingRecords.persist.rehydrate()

    expect(records().data.activeProgramId).toBe(week.programId)
    expect(JSON.parse(JSON.stringify(records().data.programs[0]))).toEqual(
      snapshot
    )
    expect(activePlannedSessions().map((item) => item.sessionId)).toEqual(
      week.sessions.map((item) => item.sessionId)
    )
  })

  it("projects each planned session as a workout that points back at the plan", () => {
    const week = createdWeek([0, 2, 4])
    const workouts = useWorkouts.getState().workouts

    expect(workouts).toHaveLength(week.sessions.length)
    for (const session of week.sessions) {
      const projection = plannedWorkoutFor(session)!
      expect(projection.planned).toEqual({
        programId: session.programId,
        sessionId: session.sessionId,
      })
      expect(projection.date).toBe(session.date)
      expect(projection.exerciseIds).toEqual(session.exerciseIds)
      expect(projection.name).toBe(session.title)
    }
    // Asking twice reuses the projection instead of growing a second one.
    ensurePlannedWorkout(week.sessions[0])
    expect(useWorkouts.getState().workouts).toHaveLength(week.sessions.length)
  })

  it("starts a planned structured draft with full lineage, targets and no observations", () => {
    const week = createdWeek([0, 2, 4])
    const session = week.sessions[0]
    const workout = plannedWorkoutFor(session)!

    beginTrainingDraft(
      workout.exerciseIds,
      "2026-09-14T10:00:00.000Z",
      workout.id,
      workout.planned
    )

    const draft = records().data.activeWorkout!
    expect(draft.plannedProgramId).toBe(session.programId)
    expect(draft.plannedSessionId).toBe(session.sessionId)
    expect(draft.sourceWorkoutId).toBe(workout.id)

    const snapshot = plannedSessionView(session.programId, session.sessionId)!
    for (const exercise of draft.exercises) {
      expect(exercise.plannedExerciseId).toBe(exercise.exerciseId)
      expect(exercise.exerciseNameSnapshot).toBe(
        EXERCISES_BY_ID.get(exercise.exerciseId)?.name
      )
      for (const set of exercise.sets) {
        expect(set.plannedSetId).toBeTruthy()
        expect(set.target).toBeTruthy()
        // A prescription is not a performance.
        expect(set.observation).toBeUndefined()
      }
    }
    const working = draft.exercises[0].sets.filter(
      (set) => set.setType === "working"
    )
    expect(working).toHaveLength(snapshot.prescription[0].sets)
    expect(working[0].target).toMatchObject({
      reps: snapshot.prescription[0].reps,
      rir: snapshot.prescription[0].rir,
    })
    // Nothing has been performed, so history holds no set at all.
    expect(records().getTrainingHistory([]).sessions).toEqual([])
  })

  it("refuses a missing planned session instead of silently opening a free draft", () => {
    const started = beginTrainingDraft(
      ["0001"],
      "2026-09-14T10:00:00.000Z",
      "planned-projection",
      { programId: "missing-program", sessionId: "missing-session" }
    )

    expect(started).toBe(false)
    expect(records().data.activeWorkout).toBeNull()
  })

  it("keeps a free workout free: no program identities are invented for it", () => {
    createdWeek([0, 2, 4])
    const workoutId = useWorkouts.getState().createWorkout({
      name: "",
      date: "2026-09-08",
      exerciseIds: ["0001", "0002"],
    })
    beginTrainingDraft(["0001", "0002"], "2026-09-08T10:00:00.000Z", workoutId)

    const draft = records().data.activeWorkout!
    expect(draft.plannedProgramId).toBeUndefined()
    expect(draft.plannedSessionId).toBeUndefined()
    expect(draft.sourceWorkoutId).toBe(workoutId)
    // An exercise that was listed is not an exercise that was performed.
    expect(draft.exercises.every((item) => item.sets.length === 0)).toBe(true)
  })

  it("records only what was performed and never rewrites the program snapshot", () => {
    const week = createdWeek([0, 2, 4])
    const session = week.sessions[0]
    const workout = plannedWorkoutFor(session)!
    const original = structuredClone(records().data.programs[0])

    beginTrainingDraft(
      workout.exerciseIds,
      "2026-09-14T10:00:00.000Z",
      workout.id,
      workout.planned
    )
    const draft = records().data.activeWorkout!
    const performed = draft.exercises[0]
    const skipped = draft.exercises[1]
    const set = performed.sets.find((item) => item.setType === "working")!
    const target = structuredClone(set.target!)

    // Deliberately different from what was prescribed.
    records().recordSet({
      exerciseEntryId: performed.id,
      setDraftId: set.id,
      observation: {
        reps: target.reps.max + 4,
        rir: 0,
        resistance: {
          type: "external_load",
          kg: 42.5,
          stationId: "Rack 1",
          basis: "total",
        },
        completed: true,
        timestamp: "2026-09-14T10:05:00.000Z",
      },
    })
    records().completeWorkout("partial", "2026-09-14T10:40:00.000Z")

    const saved = records().data.sessions[0]
    expect(saved.status).toBe("partial")
    expect(saved.plannedProgramId).toBe(session.programId)
    expect(saved.plannedSessionId).toBe(session.sessionId)
    expect(saved.sourceWorkoutId).toBe(workout.id)
    expect(saved.exercises).toHaveLength(1)
    expect(saved.exercises[0].plannedExerciseId).toBe(performed.exerciseId)
    expect(saved.exercises[0].sets).toHaveLength(1)
    expect(saved.exercises[0].sets[0]).toMatchObject({
      plannedSetId: set.plannedSetId,
      reps: target.reps.max + 4,
      rir: 0,
    })
    // The exercise nobody touched left no observation behind.
    expect(
      saved.exercises.some((item) => item.exerciseId === skipped.exerciseId)
    ).toBe(false)

    // Prescription is history of its own: it still says what it said.
    expect(records().data.programs[0]).toEqual(original)
    const stillPlanned = plannedSessionView(
      session.programId,
      session.sessionId
    )!
    expect(stillPlanned.prescription).toEqual(session.prescription)
    expect(stillPlanned.prescription[0].reps).toEqual(target.reps)
    expect(isPlannedSessionRecorded(session.sessionId)).toBe(true)
  })

  it("refuses an infeasible week with the engine's own explanation and somewhere to fix it", () => {
    // A session no equipment and no time can hold.
    useFilters.getState().setGymEquipment([])
    useTrainingProfile
      .getState()
      .updateProfile({ preferredSessionDurationMinutes: 20 })
    useTrainingProfile.getState().toggleHealthLimitation("active_injury")

    const outcome = createTrainingWeek({ days: [0, 2, 4], now: NOW })
    expect(outcome.status).toBe("blocked")
    if (outcome.status !== "blocked") return
    expect(outcome.reason).toBe("health")
    expect(outcome.page).toBe("profile-health")
    expect(outcome.issues[0].code).toBe("UNSUPPORTED_POPULATION")
    // Nothing weaker was invented in its place.
    expect(records().data.programs).toEqual([])
    expect(useWorkouts.getState().workouts).toEqual([])
  })

  it("refuses a week with no days at all", () => {
    const outcome = createTrainingWeek({ days: [], now: NOW })
    expect(outcome).toMatchObject({ status: "blocked", reason: "days" })
    expect(records().data.programs).toEqual([])
  })

  it("names a session from the split the engine chose", () => {
    expect(plannedSessionTitle("upper_lower", ["chest", "triceps"])).toBe(
      "Upper"
    )
    expect(plannedSessionTitle("upper_lower", ["quadriceps", "abs"])).toBe(
      "Lower"
    )
    expect(plannedSessionTitle("push_pull_legs", ["chest", "deltoids"])).toBe(
      "Push"
    )
    expect(
      plannedSessionTitle("push_pull_legs", ["upper-back", "biceps"])
    ).toBe("Pull")
    expect(plannedSessionTitle("push_pull_legs", ["gluteal"])).toBe("Legs")
    expect(plannedSessionTitle("full_body", ["chest", "gluteal"])).toBe(
      "Full body"
    )
  })

  it("leaves legacy workouts loading and counted exactly once", () => {
    vi.setSystemTime(new Date("2026-09-20T12:00:00.000Z"))
    const legacyId = useWorkouts.getState().createWorkout({
      name: "Old session",
      date: "2026-09-01",
      exerciseIds: ["0001"],
    })
    useWorkouts.getState().completeWorkout(legacyId, {
      startedAt: "2026-09-01T09:00:00.000Z",
      completedAt: "2026-09-01T10:00:00.000Z",
      durationMs: 3_600_000,
      completedExerciseIds: ["0001"],
      activeCalories: 300,
      healthSyncStatus: "not-requested",
    })

    const history = records().getTrainingHistory()
    expect(history.sessions).toHaveLength(1)
    // A legacy record is an observation of a session, never a set nobody logged.
    expect(history.sessions[0].exercises.flatMap((e) => e.sets)).toEqual([])
  })
})
