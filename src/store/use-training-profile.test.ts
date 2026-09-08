import { beforeEach, describe, expect, it } from "vitest"

import {
  PROFILE_AGE,
  SESSION_DURATION,
  SUPPORTED_GOALS,
} from "@/lib/training-profile"
import {
  createDefaultTrainingProfile,
  isTrainingProfileConfigured,
  sanitizeTrainingProfileState,
  TRAINING_PROFILE_STORAGE_KEY,
  useTrainingProfile,
} from "@/store/use-training-profile"
import { DEFAULT_POLICY } from "@/training"

const state = () => useTrainingProfile.getState()

describe("training profile store", () => {
  beforeEach(() => {
    localStorage.clear()
    state().resetTrainingProfile()
  })

  it("starts from cautious defaults the engine accepts", () => {
    expect(state().profile).toEqual({
      version: 1,
      name: "",
      age: 30,
      trainingExperience: "beginner",
      goal: "general_fitness",
      preferredSessionDurationMinutes: 60,
      health: { status: "healthy" },
      priorityMuscles: [],
    })
    expect(state().onboarding).toEqual({ completed: false, completedAt: null })
    // A profile nobody has touched must not win an iCloud first-run conflict.
    expect(isTrainingProfileConfigured(state())).toBe(false)
  })

  it("persists edits and restores them on reload", async () => {
    state().updateProfile({ name: "  Alex  ", age: 41, goal: "hypertrophy" })
    state().setMusclePriority("chest", "specialization")
    state().completeOnboarding("2026-09-01T12:00:00.000Z")

    const written = localStorage.getItem(TRAINING_PROFILE_STORAGE_KEY) ?? "{}"
    const stored = JSON.parse(written)
    expect(stored.version).toBe(1)
    expect(stored.state.profile).toMatchObject({ name: "Alex", age: 41 })
    expect(stored.state.onboarding.completed).toBe(true)

    // A relaunch: memory starts empty and the stored copy is what comes back.
    useTrainingProfile.setState({
      profile: createDefaultTrainingProfile(),
      onboarding: { completed: false, completedAt: null },
    })
    localStorage.setItem(TRAINING_PROFILE_STORAGE_KEY, written)
    await useTrainingProfile.persist.rehydrate()

    expect(state().profile).toMatchObject({
      name: "Alex",
      age: 41,
      goal: "hypertrophy",
      priorityMuscles: [{ muscleId: "chest", level: "specialization" }],
    })
    expect(state().onboarding.completed).toBe(true)
    expect(isTrainingProfileConfigured(state())).toBe(true)
  })

  it("sanitizes stored values without falling back to the bottom of each dial", () => {
    const restored = sanitizeTrainingProfileState({
      profile: {
        name: 42,
        age: 9,
        trainingExperience: "elite",
        goal: "power",
        preferredSessionDurationMinutes: 47,
        health: { status: "unsupported", reasons: ["haunted", "pregnancy"] },
        priorityMuscles: [
          { muscleId: "chest", level: "high" },
          { muscleId: "chest", level: "low" },
          { muscleId: "gills", level: "high" },
          { muscleId: "biceps", level: "obsessive" },
        ],
      },
      onboarding: { completed: true, completedAt: "2026-01-01T00:00:00.000Z" },
    })

    const defaults = createDefaultTrainingProfile()
    expect(restored.profile).toEqual({
      ...defaults,
      // Under the planner's own minimum age, and a goal it refuses to plan.
      age: PROFILE_AGE.min,
      preferredSessionDurationMinutes: 45,
      health: { status: "unsupported", reasons: ["pregnancy"] },
      priorityMuscles: [{ muscleId: "chest", level: "high" }],
    })
    expect(restored.onboarding.completed).toBe(true)

    // A missing profile keeps the defaults rather than the range minimums.
    expect(sanitizeTrainingProfileState({}).profile).toEqual(defaults)
  })

  it("keeps completed setup while the profile itself is re-sanitized", () => {
    const migrated = sanitizeTrainingProfileState({
      profile: { age: "unreadable" },
      onboarding: { completed: true, completedAt: "2026-02-02T00:00:00.000Z" },
    })
    expect(migrated.profile.age).toBe(createDefaultTrainingProfile().age)
    expect(migrated.onboarding).toEqual({
      completed: true,
      completedAt: "2026-02-02T00:00:00.000Z",
    })
  })

  it("only claims an unsupported status while a reason stands behind it", () => {
    state().toggleHealthLimitation("active_injury")
    expect(state().profile.health).toEqual({
      status: "unsupported",
      reasons: ["active_injury"],
    })

    state().toggleHealthLimitation("pregnancy")
    expect(state().profile.health).toMatchObject({
      reasons: ["active_injury", "pregnancy"],
    })

    state().toggleHealthLimitation("active_injury")
    state().toggleHealthLimitation("pregnancy")
    expect(state().profile.health).toEqual({ status: "healthy" })

    state().toggleHealthLimitation("rehabilitation")
    state().setHealthy()
    expect(state().profile.health).toEqual({ status: "healthy" })
  })

  it("keeps one entry per prioritised muscle and can drop them all", () => {
    state().setMusclePriority("gluteal", "high")
    state().setMusclePriority("gluteal", "low")
    state().setMusclePriority("calves", "specialization")
    expect(state().profile.priorityMuscles).toEqual([
      { muscleId: "gluteal", level: "low" },
      { muscleId: "calves", level: "specialization" },
    ])

    state().setMusclePriority("gluteal", null)
    expect(state().profile.priorityMuscles).toEqual([
      { muscleId: "calves", level: "specialization" },
    ])

    state().clearMusclePriorities()
    expect(state().profile.priorityMuscles).toEqual([])
  })

  it("advances a muscle a level per tap, even two taps in one frame", () => {
    // The first tap lands on the strongest level rather than easing into it.
    state().cycleMusclePriority("chest")
    expect(state().profile.priorityMuscles).toEqual([
      { muscleId: "chest", level: "specialization" },
    ])

    // Both calls read what is stored rather than what a render last saw, so
    // the second steps down and the third hands the muscle back.
    state().cycleMusclePriority("chest")
    state().cycleMusclePriority("chest")
    expect(state().profile.priorityMuscles).toEqual([])

    state().cycleMusclePriority("chest")
    expect(state().profile.priorityMuscles).toEqual([
      { muscleId: "chest", level: "specialization" },
    ])
  })

  it("clamps knob values to the range the engine supports", () => {
    state().updateProfile({ age: 4, preferredSessionDurationMinutes: 500 })
    expect(state().profile.age).toBe(PROFILE_AGE.min)
    expect(state().profile.preferredSessionDurationMinutes).toBe(
      SESSION_DURATION.max
    )
  })

  it("offers exactly the goals the engine's policy plans for", () => {
    expect([...SUPPORTED_GOALS].sort()).toEqual(
      Object.keys(DEFAULT_POLICY.goals).sort()
    )
    expect(SUPPORTED_GOALS).not.toContain("power")
  })
})
