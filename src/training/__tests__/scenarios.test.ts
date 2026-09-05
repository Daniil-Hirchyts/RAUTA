import { describe, expect, it } from "vitest"
import {
  adaptTrainingProgram,
  createExerciseIndex,
  generateTrainingProgram,
  validateTrainingProgram,
  calculateProgramVolume,
  findExerciseSubstitutions,
  summarizeProgram,
} from "../index"
import type { ProgramGenerationRequest, TrainingProgram } from "../domain/types"
import { request, history, set } from "./fixtures"
import { preparation } from "../planning/generate"
import { deriveProgramTargets } from "../planning/targets"
import { exerciseSimilarity, volumeUtility } from "../scoring/scores"
import { generateSplitCandidates } from "../planning/optimizer"
const index = createExerciseIndex(request().exercises)
function plan(r: ProgramGenerationRequest): TrainingProgram {
  const result = generateTrainingProgram(r)
  expect(result.status).toMatch(/success|partial/)
  if (!("program" in result)) throw new Error(JSON.stringify(result))
  expect(validateTrainingProgram(result.program, r, index).valid).toBe(true)
  return result.program
}
const scenarios = [
  [
    "beginner bodyweight 2x30",
    "beginner",
    "hypertrophy",
    [0, 3],
    30,
    ["body weight"],
  ],
  [
    "beginner general 3x45",
    "beginner",
    "general_fitness",
    [0, 2, 4],
    45,
    undefined,
  ],
  [
    "intermediate chest 4x60",
    "intermediate",
    "hypertrophy",
    [0, 1, 3, 4],
    60,
    undefined,
  ],
  [
    "intermediate strength 4x60",
    "intermediate",
    "strength",
    [0, 1, 3, 4],
    60,
    undefined,
  ],
  [
    "advanced specialization 5x60",
    "advanced",
    "hypertrophy",
    [0, 1, 2, 4, 5],
    60,
    undefined,
  ],
  [
    "advanced hybrid stagnation",
    "advanced",
    "strength_hypertrophy",
    [0, 2, 4],
    60,
    undefined,
  ],
  [
    "dumbbells only",
    "intermediate",
    "hypertrophy",
    [0, 2, 4],
    45,
    ["dumbbell"],
  ],
  [
    "bodyweight and bands",
    "beginner",
    "general_fitness",
    [0, 3],
    30,
    ["body weight", "band", "resistance band"],
  ],
  [
    "20 minute sessions",
    "beginner",
    "general_fitness",
    [0, 2, 4],
    20,
    undefined,
  ],
  ["endurance", "intermediate", "muscular_endurance", [0, 2, 4], 45, undefined],
  [
    "fat loss support",
    "intermediate",
    "fat_loss_support",
    [0, 2, 4],
    45,
    undefined,
  ],
] as const

describe("real-data golden scenarios", () => {
  it.each(scenarios)(
    "%s",
    (_name, experience, goal, days, minutes, equipment) => {
      const r = request()
      r.profile.trainingExperience = experience
      r.preferences.goal = goal
      r.schedule.days = [...days]
      r.preferences.maxSessionDurationMinutes = minutes
      if (equipment) r.preferences.availableEquipment = [...equipment]
      if (_name.includes("chest") || _name.includes("specialization")) {
        r.preferences.priorityMuscles = [{ muscleId: "chest", level: "high" }]
        r.history = history([
          [8, 8, 8],
          [8, 8, 8],
          [9, 9, 9],
          [9, 9, 9],
          [10, 10, 10],
          [10, 10, 10],
        ])
      }
      if (_name.includes("strength")) {
        r.preferences.strengthExerciseIds = ["0025", "0032", "0043"]
        r.history = history([
          [5, 5, 5],
          [5, 5, 5],
          [5, 5, 5],
          [5, 5, 5],
          [5, 5, 5],
          [5, 5, 5],
        ])
      }
      if (_name.includes("stagnation"))
        r.history = history(Array.from({ length: 6 }, () => [6, 6, 6]))
      if (_name.includes("specialization"))
        r.preferences.maxWeeklyWorkingSets = 65
      const p = plan(r)
      expect(p.weeks[0].sessions).toHaveLength(days.length)
      expect(
        p.weeks[0].sessions.every(
          (s) => s.duration.totalSeconds <= minutes * 60
        )
      ).toBe(true)
      expect(
        calculateProgramVolume(p, index)[0].muscles.chest.effective
      ).toBeGreaterThan(0)
      for (const s of p.weeks[0].sessions)
        for (const e of s.exercises)
          for (const set of e.workingSets)
            expect(["unknown", "bodyweight"]).toContain(set.resistance.type)
    },
    30_000
  )
  it("reports impossible time and hard volume rather than violating them", () => {
    const r = request()
    r.preferences.maxSessionDurationMinutes = 1
    expect(generateTrainingProgram(r).status).toBe("infeasible")
    r.preferences.maxSessionDurationMinutes = 20
    r.preferences.muscleVolumeBounds = [{ muscleId: "chest", minimum: 30 }]
    expect(generateTrainingProgram(r).status).toBe("infeasible")
  })
  it("never selects exclusions even when preferred and suggests compatible substitutes", () => {
    const r = request()
    r.preferences.excludedExerciseIds = ["0025", "0032", "0043"]
    r.preferences.preferredExerciseIds = ["0025", "0032", "0043"]
    const p = plan(r)
    expect(
      p.weeks[0].sessions
        .flatMap((s) => s.exercises)
        .some((e) => r.preferences.excludedExerciseIds!.includes(e.exerciseId))
    ).toBe(false)
    expect(
      findExerciseSubstitutions("0025", r).every((e) => e.exerciseId !== "0025")
    ).toBe(true)
  }, 30_000)
  it("preserves exercise selection across future unobserved weeks", () => {
    const r = request()
    r.schedule.durationWeeks = 4
    const p = plan(r)
    expect(
      p.weeks[0].sessions.map((s) => s.exercises.map((e) => e.exerciseId))
    ).toEqual(
      p.weeks[3].sessions.map((s) => s.exercises.map((e) => e.exerciseId))
    )
    expect(summarizeProgram(p, index).weeks).toHaveLength(4)
  }, 30_000)
})
describe("adaptation", () => {
  it("handles partial work, retains future slots and never stacks missed sessions", () => {
    const r = request()
    const previous = plan(r)
    const first = previous.weeks[0].sessions[0]
    const chosen = first.exercises[0]
    const adaptedRequest = request({
      now: "2026-09-08T12:00:00.000Z",
      schedule: { ...r.schedule, days: [2, 4] },
      history: {
        coverage: "complete",
        coverageStart: "2026-08-01T00:00:00.000Z",
        sessions: [
          {
            id: "actual",
            plannedSessionId: first.id,
            startedAt: "2026-09-07T10:00:00.000Z",
            completedAt: "2026-09-07T10:20:00.000Z",
            status: "partial",
            exercises: [
              {
                exerciseId: chosen.exerciseId,
                sets: [
                  set({
                    id: "actual-set",
                    plannedSetId: chosen.workingSets[0].id,
                    resistance: { type: "unknown" },
                  }),
                ],
              },
            ],
          },
        ],
      },
    })
    const before = JSON.stringify(previous)
    const result = adaptTrainingProgram({
      previousProgram: previous,
      request: adaptedRequest,
      mode: "remaining_week",
    })
    expect(result.status).toMatch(/success|partial/)
    if ("program" in result) {
      expect(result.program.weeks[0].sessions).toHaveLength(2)
      expect(
        result.program.weeks[0].sessions.every(
          (s) => Date.parse(s.scheduledAt) > Date.parse(adaptedRequest.now)
        )
      ).toBe(true)
      expect(result.program.adaptation?.sourceProgramId).toBe(previous.id)
    }
    expect(JSON.stringify(previous)).toBe(before)
  }, 30_000)
  it("preserves next-week continuity and applies observed load progression", () => {
    const r = request()
    r.preferences.preferredExerciseIds = ["0025"]
    const previous = plan(r)
    const next = {
      ...r,
      now: "2026-09-13T12:00:00.000Z",
      schedule: { ...r.schedule, weekStart: "2026-09-14T00:00:00.000Z" },
      history: history([[12, 12, 12]]),
      preferences: {
        ...r.preferences,
        loadGrids: { "0025": { incrementKg: 2.5 } },
        loadContexts: {
          "0025": { stationId: "bench-A", basis: "total" as const },
        },
      },
    }
    next.history.sessions[0].startedAt = "2026-09-11T10:00:00.000Z"
    next.history.sessions[0].completedAt = "2026-09-11T11:00:00.000Z"
    const result = adaptTrainingProgram({
      previousProgram: previous,
      request: next,
      mode: "next_week",
    })
    expect(result.status).toMatch(/success|partial/)
    if ("program" in result) {
      const p = result.program.weeks[0].sessions
        .flatMap((s) => s.exercises)
        .find((e) => e.exerciseId === "0025")
      expect(p?.progression.resistance).toMatchObject({ kg: 72.5 })
    }
  }, 30_000)
})
it("targets, volume utility, similarity and split candidates express intended science/policy", () => {
  const r = request()
  const input = preparation(r)
  const base = input.targets.find((t) => t.muscleId === "chest")!
  r.preferences.priorityMuscles = [{ muscleId: "chest", level: "high" }]
  expect(
    deriveProgramTargets(r, input.state, input.policy).find(
      (t) => t.muscleId === "chest"
    )!.preferred
  ).toBeGreaterThanOrEqual(base.preferred)
  r.schedule.days = [0, 1, 2, 3, 4]
  expect(
    deriveProgramTargets(r, input.state, input.policy).find(
      (t) => t.muscleId === "quadriceps"
    )!.preferred
  ).toBe(input.targets.find((t) => t.muscleId === "quadriceps")!.preferred)
  expect(volumeUtility(20, 10, 18)).toBeLessThan(volumeUtility(10, 10, 18))
  expect(
    exerciseSimilarity(index.byId.get("0025")!, index.byId.get("0289")!)
  ).toBeGreaterThan(
    exerciseSimilarity(index.byId.get("0025")!, index.byId.get("0032")!)
  )
  expect(generateSplitCandidates(input)).toHaveLength(3)
})
