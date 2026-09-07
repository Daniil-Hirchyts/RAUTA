import { create, type StoreApi } from "zustand"
import { persist } from "zustand/middleware"

import { EXERCISES_BY_ID } from "@/lib/exercises"
import { useWorkouts } from "@/store/use-workouts"
import {
  createPersistedProgramRecord,
  isSupersededPlannedSession,
  toEngineProgramSnapshot,
} from "@/training-persistence/program"
import {
  toTrainingHistory,
  type LegacyWorkoutObservation,
} from "@/training-persistence/history"
import {
  TRAINING_PERSISTENCE_SCHEMA_VERSION,
  createEmptyPersistedTrainingState,
  type PersistedActiveSetDraft,
  type PersistedLoadConfiguration,
  type PersistedLoadGrid,
  type PersistedSetObservation,
  type PersistedTrainingStateLatest,
  type TrainingPersistenceIssue,
} from "@/training-persistence/schema"
import {
  normalizePersistedTrainingState,
  recoverPersistedTrainingState,
  TrainingPersistenceValidationError,
  validatePersistedTrainingState,
} from "@/training-persistence/validation"
import {
  addUnplannedSet,
  completeWorkoutDraft,
  createActiveWorkoutFromPlannedSession,
  createFreeWorkoutDraft,
  recordSetObservation,
  substituteDraftExercise,
} from "@/training-persistence/workout"
import type { TrainingHistory, TrainingProgram } from "@/training/domain/types"

export const TRAINING_STORAGE_KEY = "gym-lib-training"

type PersistedTrainingStoreState = {
  data: PersistedTrainingStateLatest
}

export type TrainingRecordsState = {
  data: PersistedTrainingStateLatest
  persistenceIssues: TrainingPersistenceIssue[]
  saveProgram: (
    program: TrainingProgram,
    options?: {
      activate?: boolean
      manualSourceProgramId?: string
      manualRevisionAt?: string
      incorporatedSessionIds?: string[]
      replacedSessionIds?: string[]
    }
  ) => void
  activateProgram: (programId: string) => void
  archiveProgram: (programId: string) => void
  startPlannedWorkout: (
    programId: string,
    plannedSessionId: string,
    startedAt?: string,
    sourceWorkoutId?: string
  ) => string
  startFreeWorkout: (
    exerciseIds: string[],
    startedAt?: string,
    sourceWorkoutId?: string
  ) => string
  recordSet: (input: {
    exerciseEntryId: string
    setDraftId: string
    observation: PersistedSetObservation
  }) => void
  addUnplannedSet: (input: {
    exerciseEntryId: string
    setType: PersistedActiveSetDraft["setType"]
    side: PersistedActiveSetDraft["side"]
    observation?: PersistedSetObservation
  }) => string
  substituteExercise: (exerciseEntryId: string, exerciseId: string) => void
  addExercise: (exerciseId: string) => void
  moveExercise: (exerciseEntryId: string, direction: -1 | 1) => void
  reorderExercises: (exerciseEntryIds: string[]) => void
  updateSetDetails: (
    exerciseEntryId: string,
    setDraftId: string,
    details: Pick<PersistedActiveSetDraft, "setType" | "side">
  ) => void
  removeUnplannedSet: (exerciseEntryId: string, setDraftId: string) => void
  discardLoggedSet: (exerciseEntryId: string, setDraftId: string) => void
  completeWorkout: (
    status?: "completed" | "partial",
    completedAt?: string
  ) => string | null
  abortWorkout: (completedAt?: string) => string | null
  cancelWorkout: () => void
  setHistoryCoverageUnknown: () => void
  setHistoryCoverageCompleteFrom: (coverageStart: string) => void
  saveLoadConfiguration: (input: {
    id?: string
    exerciseId: string
    stationId: string
    basis: "total" | "per_implement"
    grid: PersistedLoadGrid
  }) => string
  removeLoadConfiguration: (id: string) => void
  getTrainingHistory: (
    legacyWorkouts?: readonly LegacyWorkoutObservation[]
  ) => TrainingHistory
}

function makeId(prefix: string) {
  const uuid = globalThis.crypto?.randomUUID?.()
  return uuid
    ? `${prefix}-${uuid}`
    : `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`
}

function exerciseName(exerciseId: string) {
  return EXERCISES_BY_ID.get(exerciseId)?.name
}

function checked(data: PersistedTrainingStateLatest) {
  const normalized = normalizePersistedTrainingState(data)
  const issues = validatePersistedTrainingState(normalized)
  if (issues.length) throw new TrainingPersistenceValidationError(issues)
  return normalized
}

function unwrapPersistedStore(value: unknown): unknown {
  return typeof value === "object" && value !== null && "data" in value
    ? (value as { data?: unknown }).data
    : value
}

export const useTrainingRecords = create<TrainingRecordsState>()(
  persist<TrainingRecordsState, [], [], PersistedTrainingStoreState>(
    (persistSet, get) => {
      const set: StoreApi<TrainingRecordsState>["setState"] = (update) => {
        const previous = get()
        try {
          persistSet(update)
        } catch (error) {
          // Zustand notifies before writing storage. Restore the draft if the write fails.
          try {
            persistSet(previous)
          } catch {
            /* Memory has been restored even if storage remains unavailable. */
          }
          throw error
        }
      }
      return {
        data: createEmptyPersistedTrainingState(),
        persistenceIssues: [],
        saveProgram: (program, options = {}) => {
          const record = createPersistedProgramRecord(program, {
            lifecycle: options.activate === false ? "archived" : "active",
            manualSourceProgramId: options.manualSourceProgramId,
            manualRevisionAt: options.manualRevisionAt,
            incorporatedSessionIds: options.incorporatedSessionIds,
            replacedSessionIds: options.replacedSessionIds,
          })
          set((state) => {
            const existing = state.data.programs.find(
              (item) => item.id === record.id
            )
            if (existing) {
              if (
                JSON.stringify(existing.snapshot) !==
                JSON.stringify(record.snapshot)
              )
                throw new Error(
                  "Program ID already exists with a different immutable snapshot"
                )
              return {}
            }
            if (
              record.revision &&
              !state.data.programs.some(
                (item) => item.id === record.revision?.sourceProgramId
              )
            )
              throw new Error("Program revision source must be persisted first")
            const programs = state.data.programs.map((item) =>
              options.activate === false || item.lifecycle !== "active"
                ? item
                : { ...item, lifecycle: "archived" as const }
            )
            return {
              data: checked({
                ...state.data,
                programs: [...programs, record],
                activeProgramId:
                  options.activate === false
                    ? state.data.activeProgramId
                    : record.id,
              }),
            }
          })
        },
        activateProgram: (programId) =>
          set((state) => {
            if (
              !state.data.programs.some((program) => program.id === programId)
            )
              throw new Error("Program not found")
            return {
              data: checked({
                ...state.data,
                activeProgramId: programId,
                programs: state.data.programs.map((program) => ({
                  ...program,
                  lifecycle:
                    program.id === programId
                      ? "active"
                      : program.lifecycle === "active"
                        ? "archived"
                        : program.lifecycle,
                })),
              }),
            }
          }),
        archiveProgram: (programId) =>
          set((state) => {
            if (
              !state.data.programs.some((program) => program.id === programId)
            )
              throw new Error("Program not found")
            return {
              data: checked({
                ...state.data,
                activeProgramId:
                  state.data.activeProgramId === programId
                    ? undefined
                    : state.data.activeProgramId,
                programs: state.data.programs.map((program) =>
                  program.id === programId
                    ? { ...program, lifecycle: "archived" as const }
                    : program
                ),
              }),
            }
          }),
        startPlannedWorkout: (
          programId,
          plannedSessionId,
          startedAt = new Date().toISOString(),
          sourceWorkoutId
        ) => {
          const state = get()
          if (state.data.activeWorkout)
            throw new Error("A workout is already active")
          if (
            state.data.sessions.some(
              (item) => item.plannedSessionId === plannedSessionId
            )
          )
            throw new Error("This planned session has already been recorded")
          const record = state.data.programs.find(
            (program) => program.id === programId
          )
          if (!record) throw new Error("Program not found")
          if (
            isSupersededPlannedSession(state.data, programId, plannedSessionId)
          )
            throw new Error("This planned session has been replaced")
          const program = toEngineProgramSnapshot(record.snapshot)
          const session = program.weeks
            .flatMap((week) => week.sessions)
            .find((item) => item.id === plannedSessionId)
          if (!session) throw new Error("Planned session not found")
          const draftId = makeId("workout-draft")
          const draft = createActiveWorkoutFromPlannedSession({
            draftId,
            programId,
            session,
            startedAt,
            makeId: (kind) => makeId(`draft-${kind}`),
            exerciseNameSnapshot: exerciseName,
            sourceWorkoutId,
          })
          set({ data: checked({ ...state.data, activeWorkout: draft }) })
          return draftId
        },
        startFreeWorkout: (
          exerciseIds,
          startedAt = new Date().toISOString(),
          sourceWorkoutId
        ) => {
          const state = get()
          if (state.data.activeWorkout)
            throw new Error("A workout is already active")
          const draftId = makeId("workout-draft")
          const draft = createFreeWorkoutDraft({
            draftId,
            startedAt,
            exerciseIds,
            makeId: (kind) => makeId(`draft-${kind}`),
            exerciseNameSnapshot: exerciseName,
            sourceWorkoutId,
          })
          set({ data: checked({ ...state.data, activeWorkout: draft }) })
          return draftId
        },
        recordSet: (input) =>
          set((state) => {
            if (!state.data.activeWorkout) throw new Error("No active workout")
            const activeWorkout = recordSetObservation(
              state.data.activeWorkout,
              input
            )
            return { data: checked({ ...state.data, activeWorkout }) }
          }),
        addExercise: (exerciseId) =>
          set((state) => {
            if (!state.data.activeWorkout) throw new Error("No active workout")
            if (!EXERCISES_BY_ID.has(exerciseId))
              throw new Error("Exercise not found")
            const activeWorkout = structuredClone(state.data.activeWorkout)
            activeWorkout.exercises.push({
              id: makeId("draft-exercise"),
              exerciseId,
              exerciseNameSnapshot: exerciseName(exerciseId),
              sets: [],
            })
            return { data: checked({ ...state.data, activeWorkout }) }
          }),
        reorderExercises: (exerciseEntryIds) =>
          set((state) => {
            const draft = state.data.activeWorkout
            if (
              !draft ||
              exerciseEntryIds.length !== draft.exercises.length ||
              new Set(exerciseEntryIds).size !== exerciseEntryIds.length ||
              exerciseEntryIds.some(
                (id) => !draft.exercises.some((e) => e.id === id)
              )
            )
              throw new Error("Invalid exercise order")
            return {
              data: checked({
                ...state.data,
                activeWorkout: {
                  ...draft,
                  exercises: exerciseEntryIds.map((id) =>
                    draft.exercises.find((e) => e.id === id)!
                  ),
                },
              }),
            }
          }),
        moveExercise: (exerciseEntryId, direction) =>
          set((state) => {
            if (!state.data.activeWorkout) throw new Error("No active workout")
            const activeWorkout = structuredClone(state.data.activeWorkout)
            const index = activeWorkout.exercises.findIndex(
              (item) => item.id === exerciseEntryId
            )
            const next = index + direction
            if (index < 0 || next < 0 || next >= activeWorkout.exercises.length)
              return {}
            ;[activeWorkout.exercises[index], activeWorkout.exercises[next]] = [
              activeWorkout.exercises[next],
              activeWorkout.exercises[index],
            ]
            return { data: checked({ ...state.data, activeWorkout }) }
          }),
        updateSetDetails: (exerciseEntryId, setDraftId, details) =>
          set((state) => {
            if (!state.data.activeWorkout) throw new Error("No active workout")
            const activeWorkout = structuredClone(state.data.activeWorkout)
            const item = activeWorkout.exercises
              .find((e) => e.id === exerciseEntryId)
              ?.sets.find((s) => s.id === setDraftId)
            if (!item) throw new Error("Set not found")
            Object.assign(item, details)
            return { data: checked({ ...state.data, activeWorkout }) }
          }),
        removeUnplannedSet: (exerciseEntryId, setDraftId) =>
          set((state) => {
            if (!state.data.activeWorkout) throw new Error("No active workout")
            const activeWorkout = structuredClone(state.data.activeWorkout)
            const exercise = activeWorkout.exercises.find(
              (e) => e.id === exerciseEntryId
            )
            const item = exercise?.sets.find((s) => s.id === setDraftId)
            if (
              !exercise ||
              !item ||
              item.plannedSetId ||
              item.observation?.completed
            )
              throw new Error("Only unfinished additional sets can be removed")
            exercise.sets = exercise.sets.filter((s) => s.id !== setDraftId)
            return { data: checked({ ...state.data, activeWorkout }) }
          }),
        discardLoggedSet: (exerciseEntryId, setDraftId) =>
          set((state) => {
            if (!state.data.activeWorkout) throw new Error("No active workout")
            const activeWorkout = structuredClone(state.data.activeWorkout)
            const exercise = activeWorkout.exercises.find(
              (e) => e.id === exerciseEntryId
            )
            const item = exercise?.sets.find((s) => s.id === setDraftId)
            // A live draft is not history: only completion writes evidence, so
            // a set logged by mistake can still be taken back until then. A
            // planned set is the prescription rather than a record and stays.
            if (!exercise || !item || item.plannedSetId)
              throw new Error("Prescribed sets stay in the workout")
            exercise.sets = exercise.sets.filter((s) => s.id !== setDraftId)
            return { data: checked({ ...state.data, activeWorkout }) }
          }),
        addUnplannedSet: (input) => {
          const setDraftId = makeId("draft-set")
          const state = get()
          if (!state.data.activeWorkout) throw new Error("No active workout")
          const activeWorkout = addUnplannedSet(state.data.activeWorkout, {
            ...input,
            setDraftId,
          })
          set({ data: checked({ ...state.data, activeWorkout }) })
          return setDraftId
        },
        substituteExercise: (exerciseEntryId, exerciseId) =>
          set((state) => {
            if (!state.data.activeWorkout) throw new Error("No active workout")
            const activeWorkout = substituteDraftExercise(
              state.data.activeWorkout,
              {
                exerciseEntryId,
                exerciseId,
                exerciseNameSnapshot: exerciseName(exerciseId),
              }
            )
            return { data: checked({ ...state.data, activeWorkout }) }
          }),
        completeWorkout: (
          status = "completed",
          completedAt = new Date().toISOString()
        ) => {
          const state = get()
          const draft = state.data.activeWorkout
          if (!draft) return null
          const sessionId = makeId("training-session")
          const session = completeWorkoutDraft(draft, {
            sessionId,
            completedAt,
            status,
            makeId: (kind) => makeId(`completed-${kind}`),
          })
          // One persisted Zustand update is the local completion transaction.
          set({
            data: checked({
              ...state.data,
              sessions: [...state.data.sessions, session],
              activeWorkout: null,
            }),
          })
          return sessionId
        },
        abortWorkout: (completedAt = new Date().toISOString()) => {
          const state = get()
          const draft = state.data.activeWorkout
          if (!draft) return null
          const hasCompletedWork = draft.exercises.some((exercise) =>
            exercise.sets.some((set) => set.observation?.completed)
          )
          if (hasCompletedWork)
            return get().completeWorkout("partial", completedAt)
          set({ data: checked({ ...state.data, activeWorkout: null }) })
          return null
        },
        cancelWorkout: () =>
          set((state) => ({
            data: checked({ ...state.data, activeWorkout: null }),
          })),
        setHistoryCoverageUnknown: () =>
          set((state) => ({
            data: checked({
              ...state.data,
              settings: {
                ...state.data.settings,
                historyCoverage: { status: "unknown" },
              },
            }),
          })),
        setHistoryCoverageCompleteFrom: (coverageStart) =>
          set((state) => ({
            data: checked({
              ...state.data,
              settings: {
                ...state.data.settings,
                historyCoverage: { status: "complete", coverageStart },
              },
            }),
          })),
        saveLoadConfiguration: (input) => {
          const id = input.id ?? makeId("load-context")
          const configuration: PersistedLoadConfiguration = {
            id,
            exerciseId: input.exerciseId,
            stationId: input.stationId,
            basis: input.basis,
            grid: structuredClone(input.grid),
          }
          set((state) => ({
            data: checked({
              ...state.data,
              settings: {
                ...state.data.settings,
                loadConfigurations: [
                  ...state.data.settings.loadConfigurations.filter(
                    (item) => item.id !== id
                  ),
                  configuration,
                ],
              },
            }),
          }))
          return id
        },
        removeLoadConfiguration: (id) =>
          set((state) => ({
            data: checked({
              ...state.data,
              settings: {
                ...state.data.settings,
                loadConfigurations:
                  state.data.settings.loadConfigurations.filter(
                    (item) => item.id !== id
                  ),
              },
            }),
          })),
        getTrainingHistory: (
          legacyWorkouts = useWorkouts.getState().workouts
        ) => toTrainingHistory(get().data, legacyWorkouts),
      }
    },
    {
      name: TRAINING_STORAGE_KEY,
      version: TRAINING_PERSISTENCE_SCHEMA_VERSION,
      migrate: (persistedState) => ({
        data: recoverPersistedTrainingState(
          unwrapPersistedStore(persistedState)
        ).state,
      }),
      merge: (persistedState, currentState) => {
        const recovered = recoverPersistedTrainingState(
          unwrapPersistedStore(persistedState)
        )
        return {
          ...currentState,
          data: recovered.state,
          persistenceIssues: recovered.issues,
        }
      },
      partialize: ({ data }) => ({ data }),
    }
  )
)
