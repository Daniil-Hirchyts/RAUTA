import { create } from "zustand"
import { persist } from "zustand/middleware"

import { EXERCISES_BY_ID } from "@/lib/exercises"
import { useWorkouts } from "@/store/use-workouts"
import {
  createPersistedProgramRecord,
  toEngineProgramSnapshot,
} from "@/training-persistence/program"
import { toTrainingHistory, type LegacyWorkoutObservation } from "@/training-persistence/history"
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
    }
  ) => void
  activateProgram: (programId: string) => void
  archiveProgram: (programId: string) => void
  startPlannedWorkout: (
    programId: string,
    plannedSessionId: string,
    startedAt?: string
  ) => string
  startFreeWorkout: (exerciseIds: string[], startedAt?: string) => string
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
    (set, get) => ({
      data: createEmptyPersistedTrainingState(),
      persistenceIssues: [],
      saveProgram: (program, options = {}) => {
        const record = createPersistedProgramRecord(program, {
          lifecycle: options.activate === false ? "archived" : "active",
          manualSourceProgramId: options.manualSourceProgramId,
          manualRevisionAt: options.manualRevisionAt,
        })
        set((state) => {
          const existing = state.data.programs.find((item) => item.id === record.id)
          if (existing) {
            if (JSON.stringify(existing.snapshot) !== JSON.stringify(record.snapshot))
              throw new Error("Program ID already exists with a different immutable snapshot")
            return {}
          }
          if (record.revision && !state.data.programs.some((item) => item.id === record.revision?.sourceProgramId))
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
              activeProgramId: options.activate === false ? state.data.activeProgramId : record.id,
            }),
          }
        })
      },
      activateProgram: (programId) =>
        set((state) => {
          if (!state.data.programs.some((program) => program.id === programId))
            throw new Error("Program not found")
          return {
            data: checked({
              ...state.data,
              activeProgramId: programId,
              programs: state.data.programs.map((program) => ({
                ...program,
                lifecycle: program.id === programId ? "active" : program.lifecycle === "active" ? "archived" : program.lifecycle,
              })),
            }),
          }
        }),
      archiveProgram: (programId) =>
        set((state) => {
          if (!state.data.programs.some((program) => program.id === programId))
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
      startPlannedWorkout: (programId, plannedSessionId, startedAt = new Date().toISOString()) => {
        const state = get()
        if (state.data.activeWorkout) throw new Error("A workout is already active")
        const record = state.data.programs.find((program) => program.id === programId)
        if (!record) throw new Error("Program not found")
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
        })
        set({ data: checked({ ...state.data, activeWorkout: draft }) })
        return draftId
      },
      startFreeWorkout: (exerciseIds, startedAt = new Date().toISOString()) => {
        const state = get()
        if (state.data.activeWorkout) throw new Error("A workout is already active")
        const draftId = makeId("workout-draft")
        const draft = createFreeWorkoutDraft({
          draftId,
          startedAt,
          exerciseIds,
          makeId: (kind) => makeId(`draft-${kind}`),
          exerciseNameSnapshot: exerciseName,
        })
        set({ data: checked({ ...state.data, activeWorkout: draft }) })
        return draftId
      },
      recordSet: (input) =>
        set((state) => {
          if (!state.data.activeWorkout) throw new Error("No active workout")
          const activeWorkout = recordSetObservation(state.data.activeWorkout, input)
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
          const activeWorkout = substituteDraftExercise(state.data.activeWorkout, {
            exerciseEntryId,
            exerciseId,
            exerciseNameSnapshot: exerciseName(exerciseId),
          })
          return { data: checked({ ...state.data, activeWorkout }) }
        }),
      completeWorkout: (status = "completed", completedAt = new Date().toISOString()) => {
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
        if (hasCompletedWork) return get().completeWorkout("partial", completedAt)
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
              loadConfigurations: state.data.settings.loadConfigurations.filter(
                (item) => item.id !== id
              ),
            },
          }),
        })),
      getTrainingHistory: (legacyWorkouts = useWorkouts.getState().workouts) =>
        toTrainingHistory(get().data, legacyWorkouts),
    }),
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
