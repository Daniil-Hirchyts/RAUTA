import exercises from "../../data/exercises.generated.json"
import type {
  CompletedSet,
  CompletedSession,
  ExerciseSummary,
  ProgramGenerationRequest,
  TrainingHistory,
} from "../domain/types"
export const fullEquipment = [
  ...new Set(exercises.map((e) => e.equipment)),
  "bench",
  "rack",
  "pull-up bar",
  "low bar",
  "chair",
  "step",
  "band anchor",
  "towel",
  "suspension straps",
]
export function request(
  overrides: Partial<ProgramGenerationRequest> = {}
): ProgramGenerationRequest {
  return {
    profile: {
      age: 32,
      trainingExperience: "intermediate",
      health: { status: "healthy" },
    },
    preferences: {
      goal: "hypertrophy",
      availableEquipment: fullEquipment,
      maxSessionDurationMinutes: 60,
    },
    schedule: {
      weekStart: "2026-09-07T00:00:00.000Z",
      days: [0, 2, 4],
      durationWeeks: 1,
    },
    history: { sessions: [], coverage: "unknown" },
    exercises: exercises as ExerciseSummary[],
    now: "2026-09-05T12:00:00.000Z",
    ...overrides,
  }
}
export function set(overrides: Partial<CompletedSet> = {}): CompletedSet {
  return {
    id: "set",
    reps: 12,
    resistance: {
      type: "external_load",
      kg: 70,
      stationId: "bench-A",
      basis: "total",
    },
    rir: 2,
    completed: true,
    setType: "working",
    side: "both",
    ...overrides,
  }
}
export function history(
  reps: number[][],
  exerciseId = "0025"
): TrainingHistory {
  return {
    coverage: "complete",
    coverageStart: "2026-07-01T00:00:00.000Z",
    sessions: reps.map((list, i): CompletedSession => ({
      id: `session-${i}`,
      startedAt: `2026-08-${String(10 + i * 3).padStart(2, "0")}T10:00:00.000Z`,
      completedAt: `2026-08-${String(10 + i * 3).padStart(2, "0")}T11:00:00.000Z`,
      status: "completed",
      exercises: [
        {
          exerciseId,
          sets: list.map((reps, j) => set({ reps, id: `set-${i}-${j}` })),
        },
      ],
    })),
  }
}
