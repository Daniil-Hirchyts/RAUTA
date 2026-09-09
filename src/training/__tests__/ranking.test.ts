import { describe, expect, it } from "vitest"
import { rankExerciseCandidates } from "../planning/rank"
import { findExerciseSubstitutions } from "../planning/substitutions"
import { createExerciseIndex } from "../data/exercises"
import { history, request } from "./fixtures"

const index = createExerciseIndex(request().exercises)
describe("shared planner exercise ranking", () => {
  it("uses goals, muscle priorities, experience, and actual history in candidate scores", () => {
    const base = request()
    const original = rankExerciseCandidates(base, { index })
    const personalized = rankExerciseCandidates(
      {
        ...base,
        profile: { ...base.profile, trainingExperience: "beginner" },
        preferences: {
          ...base.preferences,
          goal: "strength",
          priorityMuscles: [{ muscleId: "chest", level: "specialization" }],
        },
        history: history(
          [
            [10, 10, 10],
            [11, 11, 11],
          ],
          "0025"
        ),
      },
      { index }
    )
    expect(personalized.map((item) => item.exerciseId)).not.toEqual(
      original.map((item) => item.exerciseId)
    )
    const bench = personalized.find((item) => item.exerciseId === "0025")!
    expect(
      bench.score.contributions.find((item) => item.factor === "continuity")
        ?.rawValue
    ).toBe(1)
    expect(
      bench.score.contributions.find((item) => item.factor === "specificity")
        ?.weight
    ).not.toBe(
      original
        .find((item) => item.exerciseId === "0025")!
        .score.contributions.find((item) => item.factor === "specificity")
        ?.weight
    )
  })

  it("ranks alternatives for the current equipment and goal, excluding exercises already selected", () => {
    const base = request()
    base.preferences.availableEquipment = [
      "dumbbell",
      "bench",
      "body weight",
      "wall",
      "chair",
      "support",
      "step",
    ]
    const alternatives = findExerciseSubstitutions("0025", base, 100, { index })
    expect(alternatives.length).toBeGreaterThan(0)
    for (const item of alternatives) {
      const exercise = index.byId.get(item.exerciseId)!
      expect(["dumbbell", "body weight"]).toContain(exercise.exercise.equipment)
      expect(
        item.score.contributions.some((factor) => factor.factor === "planning")
      ).toBe(true)
    }
    const selected = alternatives[0].exerciseId
    expect(
      findExerciseSubstitutions("0025", base, 100, {
        index,
        selectedExerciseIds: [selected],
      }).some((item) => item.exerciseId === selected)
    ).toBe(false)
    const strength = findExerciseSubstitutions(
      "0025",
      { ...base, preferences: { ...base.preferences, goal: "strength" } },
      100,
      { index }
    )
    expect(strength.map((item) => item.score.total)).not.toEqual(
      alternatives.map((item) => item.score.total)
    )
  })
})
