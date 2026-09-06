import { beforeEach, describe, expect, it } from "vitest"

import { EQUIPMENT_OPTIONS, EXERCISES } from "@/lib/exercises"
import {
  buildTrainingEngineInputs,
  buildTrainingEngineProfile,
  buildTrainingPlanningPreferences,
  SESSION_DURATION_HEADROOM_MINUTES,
  toEngineEquipment,
} from "@/lib/training-engine-adapter"
import { buildTrainingRequest } from "@/lib/training-workflow"
import { useFilters } from "@/store/use-filters"
import { DEFAULT_SETTINGS, useSettings } from "@/store/use-settings"
import {
  createDefaultTrainingProfile,
  useTrainingProfile,
} from "@/store/use-training-profile"
import { createExerciseIndex, validateGenerationRequest } from "@/training"

const catalogueEquipment = (() => {
  const index = createExerciseIndex(EXERCISES)
  return new Set(
    [...index.byId.values()].flatMap((item) => item.metadata.requiredEquipment)
  )
})()

describe("training engine adapter", () => {
  beforeEach(() => {
    localStorage.clear()
    useTrainingProfile.getState().resetTrainingProfile()
    useSettings.setState(DEFAULT_SETTINGS)
    useFilters.setState({
      equipmentPresets: [],
      gymEquipment: [],
      selectedEquipment: [],
      selectedMuscles: [],
    })
  })

  it("hands the engine its own profile vocabulary", () => {
    const profile = {
      ...createDefaultTrainingProfile(),
      name: "Alex",
      age: 41,
      trainingExperience: "advanced" as const,
    }

    expect(buildTrainingEngineProfile(profile)).toEqual({
      age: 41,
      trainingExperience: "advanced",
      health: { status: "healthy" },
    })
    // The person's name is application data; the engine is never told it.
    expect(buildTrainingEngineProfile(profile)).not.toHaveProperty("name")

    expect(
      buildTrainingEngineProfile(
        {
          ...profile,
          health: {
            status: "unsupported",
            reasons: ["active_injury", "pregnancy"],
          },
        },
        { bodyWeightKg: 82 }
      )
    ).toEqual({
      age: 41,
      trainingExperience: "advanced",
      bodyWeightKg: 82,
      health: {
        status: "unsupported",
        reasons: ["active_injury", "pregnancy"],
      },
    })
  })

  it("turns the saved preferences into planning preferences", () => {
    const profile = {
      ...createDefaultTrainingProfile(),
      goal: "hypertrophy" as const,
      preferredSessionDurationMinutes: 45,
      priorityMuscles: [{ muscleId: "chest" as const, level: "high" as const }],
    }

    const preferences = buildTrainingPlanningPreferences(profile, ["dumbbell"])
    expect(preferences).toMatchObject({
      goal: "hypertrophy",
      preferredSessionDurationMinutes: 45,
      maxSessionDurationMinutes: 45 + SESSION_DURATION_HEADROOM_MINUTES,
      priorityMuscles: [{ muscleId: "chest", level: "high" }],
    })
    expect(preferences.availableEquipment).toContain("dumbbell")

    // No priorities means no key at all, not an empty promise to the planner.
    expect(
      buildTrainingPlanningPreferences(createDefaultTrainingProfile(), [])
    ).not.toHaveProperty("priorityMuscles")
  })

  it("grants the fixtures the chosen equipment stands on", () => {
    expect(toEngineEquipment(["barbell"])).toEqual(
      expect.arrayContaining(["barbell", "bench", "rack"])
    )
    // Nothing a body-weight-only room cannot be assumed to have.
    expect(toEngineEquipment(["body weight"])).not.toContain("pull-up bar")
    // An unanswered equipment question still leaves something to plan with.
    expect(toEngineEquipment([])).toEqual([
      "body weight",
      "chair",
      "wall",
      "step",
      "towel",
      "support",
    ])

    const full = toEngineEquipment(EQUIPMENT_OPTIONS)
    expect(new Set(full).size).toBe(full.length)
    for (const item of full)
      expect(catalogueEquipment.has(item), item).toBe(true)
  })

  it("reads the saved profile, equipment and Health weight without asking again", () => {
    useTrainingProfile.getState().updateProfile({
      age: 28,
      goal: "strength",
      preferredSessionDurationMinutes: 75,
      trainingExperience: "intermediate",
    })
    useTrainingProfile.getState().setMusclePriority("gluteal", "specialization")
    useFilters.getState().setGymEquipment(["barbell", "dumbbell"])
    useSettings.setState({
      ...DEFAULT_SETTINGS,
      appleHealthEnabled: true,
      healthBodyWeightKg: 74,
    })

    const { preferences, profile } = buildTrainingEngineInputs()
    expect(profile).toEqual({
      age: 28,
      trainingExperience: "intermediate",
      bodyWeightKg: 74,
      health: { status: "healthy" },
    })
    expect(preferences).toMatchObject({
      goal: "strength",
      preferredSessionDurationMinutes: 75,
      priorityMuscles: [{ muscleId: "gluteal", level: "specialization" }],
    })
    expect(preferences.availableEquipment).toEqual(
      expect.arrayContaining(["barbell", "dumbbell", "bench", "rack"])
    )

    // Health weight is only borrowed while the integration is switched on.
    useSettings.setState({ ...DEFAULT_SETTINGS, healthBodyWeightKg: 74 })
    expect(buildTrainingEngineInputs().profile).not.toHaveProperty(
      "bodyWeightKg"
    )
  })

  it("accepts a per-plan override without changing what is saved", () => {
    useFilters.getState().setGymEquipment(["dumbbell"])
    const { preferences } = buildTrainingEngineInputs({
      availableEquipment: ["barbell"],
      goal: "power",
    })

    expect(preferences.availableEquipment).toEqual(["barbell"])
    expect(preferences.goal).toBe("power")
    expect(useTrainingProfile.getState().profile.goal).toBe("general_fitness")
    expect(useFilters.getState().gymEquipment).toEqual(["dumbbell"])
  })

  it("builds a generation request the engine validates without complaint", () => {
    useTrainingProfile
      .getState()
      .updateProfile({ age: 33, goal: "hypertrophy" })
    useTrainingProfile.getState().setMusclePriority("chest", "high")
    useFilters.getState().setGymEquipment([...EQUIPMENT_OPTIONS])

    const request = buildTrainingRequest(
      buildTrainingEngineInputs(),
      "2026-09-06T10:00:00.000Z"
    )
    expect(validateGenerationRequest(request)).toEqual([])
    expect(request.profile.age).toBe(33)
    expect(request.preferences.goal).toBe("hypertrophy")
  })
})
