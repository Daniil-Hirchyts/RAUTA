import { describe, expect, it } from "vitest"
import type { ProgramGenerationRequest } from "../domain/types"
import {
  createExerciseIndex,
  DEFAULT_POLICY,
  generateTrainingProgram,
  validateGenerationRequest,
  validateTrainingProgram,
  inferExerciseMetadata,
} from "../index"
import { request } from "./fixtures"
import { exclusionReasons } from "../data/exercises"
import { preparation } from "../planning/generate"
import { scoreExercise } from "../scoring/scores"
import { generateSplitCandidates } from "../planning/optimizer"
import {
  CORE_PROGRAMMING_FIELDS,
  getCuratedExerciseReviews,
  isFullyCuratedReview,
} from "../data/curated-exercises"
// Seeded generated cases avoid a new dependency. The seed and failing index reproduce every case.
function random(seed: number) {
  let n = seed >>> 0
  return () => {
    n = (Math.imul(n, 1664525) + 1013904223) >>> 0
    return n / 4294967296
  }
}
const full = request()
const index = createExerciseIndex(full.exercises)
const smallData = [...index.byId.values()]
  .filter((e) => e.metadata.exerciseType === "resistance")
  .filter((_, i) => i % 8 === 0)
  .map((e) => e.exercise)
const fastPolicy = {
  ...structuredClone(DEFAULT_POLICY),
  beamWidth: 1,
  candidateLimit: 3,
  maxExercisesPerSession: 5,
  localIterations: 2,
}
function fastRequest() {
  return request({ exercises: smallData, policy: fastPolicy })
}
function freeze(value: unknown) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value)
    Object.values(value).forEach(freeze)
  }
}
function assertFinite(value: unknown) {
  if (typeof value === "number") expect(Number.isFinite(value)).toBe(true)
  else if (value && typeof value === "object")
    Object.values(value).forEach(assertFinite)
}

describe("generated invariants and metamorphic cases", () => {
  it("keeps the full catalogue indexed with valid programming metadata", () => {
    expect(index.issues).toEqual([])
    expect(index.byId.size).toBe(full.exercises.length)
    for (const item of index.byId.values()) {
      expect(index.byId.get(item.exercise.id)).toBe(item)
      expect(["allowed", "specialized_only", "manual_only"]).toContain(
        item.metadata.automaticProgramming
      )
      if (
        item.metadata.exerciseType === "resistance" &&
        item.metadata.automaticProgramming !== "manual_only"
      ) {
        expect(item.metadata.setRoles.some((role) => role.role === "direct")).toBe(
          true
        )
        expect(item.metadata.mechanics).not.toBe("unknown")
        expect(item.metadata.movementPatterns).not.toContain("unknown")
      }
      for (const relationship of [
        item.metadata.variantOf,
        item.metadata.duplicateOf,
      ]) {
        if (!relationship) continue
        expect(relationship).not.toBe(item.exercise.id)
        expect(index.byId.has(relationship)).toBe(true)
      }
    }
    for (const item of index.byAutomaticProgramming.get("manual_only") ?? [])
      expect(index.byId.has(item.exercise.id)).toBe(true)

    for (const id of [
      "0088",
      "1371",
      "0454",
      "1628",
      "0576",
      "0577",
      "0655",
      "0656",
      "0697",
      "1766",
      "0763",
      "1394",
    ]) {
      const metadata = index.byId.get(id)?.metadata
      expect(metadata?.provenance).toBe("curated")
      expect(metadata?.reviewStatus).toBe("partially_reviewed")
    }
    expect(index.byId.get("1371")?.metadata.duplicateOf).toBe("0088")
    expect(index.byId.get("0577")?.metadata.variantOf).toBe("0576")
    expect(index.byId.get("0656")?.metadata.tags).toContain(
      "source_media_conflict"
    )
    expect(index.byId.get("0697")?.metadata.automaticProgramming).toBe(
      "manual_only"
    )
  })

  it("rejects relationship cycles in explicit metadata", () => {
    const a = index.byId.get("0025")!
    const b = index.byId.get("0289")!
    const cycled = createExerciseIndex(
      [a.exercise, b.exercise],
      [
        { ...a.metadata, variantOf: b.exercise.id },
        { ...b.metadata, variantOf: a.exercise.id },
      ]
    )
    expect(cycled.issues.some((issue) => issue.code === "INVALID_EXERCISE_DATA")).toBe(
      true
    )
    expect(cycled.byId.size).toBe(0)
  })

  it("never presents partial review patches as fully curated programming metadata", () => {
    for (const review of getCuratedExerciseReviews()) {
      const metadata = index.byId.get(review.exerciseId)?.metadata
      expect(metadata).toBeDefined()
      if (isFullyCuratedReview(review)) {
        expect(metadata?.reviewStatus).toBe("fully_reviewed")
        const reviewed = new Set(review.reviewedFields ?? [])
        for (const field of CORE_PROGRAMMING_FIELDS) {
          expect(reviewed.has(field), `${review.exerciseId}:${field}`).toBe(true)
          expect(
            Object.prototype.hasOwnProperty.call(review.metadata, field),
            `${review.exerciseId}:${field}`
          ).toBe(true)
        }
      } else {
        expect(metadata?.reviewStatus).toBe("partially_reviewed")
      }
    }
  })

  it("40 seeded valid profiles retain all hard invariants", () => {
    const rnd = random(47329)
    for (let i = 0; i < 40; i++) {
      const r = fastRequest()
      r.profile.age = 18 + Math.floor(rnd() * 70)
      r.profile.trainingExperience = ["beginner", "intermediate", "advanced"][
        Math.floor(rnd() * 3)
      ] as typeof r.profile.trainingExperience
      r.preferences.goal = [
        "hypertrophy",
        "strength",
        "general_fitness",
        "muscular_endurance",
      ][Math.floor(rnd() * 4)] as typeof r.preferences.goal
      r.preferences.availableEquipment =
        r.preferences.availableEquipment.filter(() => rnd() > 0.3)
      r.preferences.maxSessionDurationMinutes = 15 + Math.floor(rnd() * 50)
      r.preferences.excludedExerciseIds = smallData
        .filter(() => rnd() < 0.1)
        .map((e) => e.id)
      r.schedule.days = [0, 2, 4, 6].slice(0, 1 + Math.floor(rnd() * 4))
      const result = generateTrainingProgram(r)
      assertFinite(result)
      if ("program" in result) {
        const validation = validateTrainingProgram(
          result.program,
          r,
          createExerciseIndex(r.exercises)
        )
        expect(validation, `seed 47329 case ${i}`).toMatchObject({
          valid: true,
        })
      } else expect(result.status).toBe("infeasible")
    }
  }, 60_000)
  it("determinism, no input mutation, and dataset permutation invariance", () => {
    const r = fastRequest()
    const before = JSON.stringify(r)
    freeze(r)
    const a = generateTrainingProgram(r)
    const b = generateTrainingProgram(r)
    expect(JSON.stringify(a)).toBe(JSON.stringify(b))
    expect(JSON.stringify(r)).toBe(before)
    const permuted = generateTrainingProgram({
      ...r,
      exercises: [...r.exercises].reverse(),
    })
    if ("program" in a && "program" in permuted)
      expect(a.program.weeks).toEqual(permuted.program.weeks)
  }, 30_000)
  it("expanded equipment keeps the previous plan feasible", () => {
    const r = fastRequest()
    r.preferences.availableEquipment = ["body weight", "dumbbell"]
    const result = generateTrainingProgram(r)
    expect("program" in result).toBe(true)
    if ("program" in result)
      expect(
        validateTrainingProgram(
          result.program,
          {
            ...r,
            preferences: {
              ...r.preferences,
              availableEquipment: full.preferences.availableEquipment,
            },
          },
          createExerciseIndex(r.exercises)
        ).valid
      ).toBe(true)
  }, 30_000)
  it("lower hard time gives bounded sessions without rest compression", () => {
    const r = fastRequest()
    r.preferences.maxSessionDurationMinutes = 20
    const result = generateTrainingProgram(r)
    if ("program" in result)
      for (const s of result.program.weeks[0].sessions) {
        expect(s.duration.totalSeconds).toBeLessThanOrEqual(1200)
        for (const e of s.exercises)
          expect(e.restSeconds).toBeGreaterThanOrEqual(90)
      }
  }, 30_000)
  it("strength-specific scoring and priority ordering are explicit", () => {
    const r = fastRequest()
    r.preferences.goal = "strength"
    r.preferences.strengthExerciseIds = ["0025"]
    r.exercises = full.exercises
    const input = preparation(r)
    const sessions = generateSplitCandidates(input)[0].sessions
    const week = {
      id: "w",
      start: r.schedule.weekStart,
      phase: "base" as const,
      sessions,
      targets: input.targets,
    }
    expect(
      scoreExercise(
        index.byId.get("0025")!,
        sessions[0],
        week,
        input
      ).contributions.find((c) => c.factor === "specificity")?.rawValue
    ).toBe(1)
  })

  it("separates manual and specialized eligibility from curated confidence", () => {
    const source = index.byId.get("0025")!
    const allowed = {
      ...source,
      metadata: {
        ...source.metadata,
        provenance: "curated" as const,
        classificationConfidence: 0.1,
        automaticProgramming: "allowed" as const,
      },
    }
    expect(
      exclusionReasons(allowed, full.preferences, DEFAULT_POLICY).some(
        (issue) => issue.code === "UNSUPPORTED_EXERCISE"
      )
    ).toBe(false)

    const manual = {
      ...allowed,
      metadata: { ...allowed.metadata, automaticProgramming: "manual_only" as const },
    }
    expect(
      exclusionReasons(
        manual,
        {
          ...full.preferences,
          preferredExerciseIds: [source.exercise.id],
        },
        DEFAULT_POLICY
      ).some((issue) => issue.code === "UNSUPPORTED_EXERCISE")
    ).toBe(true)

    const specialized = {
      ...allowed,
      metadata: {
        ...allowed.metadata,
        automaticProgramming: "specialized_only" as const,
      },
    }
    expect(
      exclusionReasons(specialized, full.preferences, DEFAULT_POLICY).some(
        (issue) => issue.code === "UNSUPPORTED_EXERCISE"
      )
    ).toBe(true)
    expect(
      exclusionReasons(
        specialized,
        {
          ...full.preferences,
          preferredExerciseIds: [source.exercise.id],
        },
        DEFAULT_POLICY
      ).some((issue) => issue.code === "UNSUPPORTED_EXERCISE")
    ).toBe(false)

    const ruleSpecialized = {
      ...source,
      metadata: {
        ...source.metadata,
        provenance: "rule" as const,
        automaticProgramming: "specialized_only" as const,
        classificationConfidence:
          DEFAULT_POLICY.minimumSpecializedClassificationConfidence,
      },
    }
    expect(
      exclusionReasons(ruleSpecialized, full.preferences, DEFAULT_POLICY).some(
        (issue) => issue.code === "UNSUPPORTED_EXERCISE"
      )
    ).toBe(true)
    for (const explicit of [
      { preferredExerciseIds: [source.exercise.id] },
      { strengthExerciseIds: [source.exercise.id] },
    ])
      expect(
        exclusionReasons(
          ruleSpecialized,
          { ...full.preferences, ...explicit },
          DEFAULT_POLICY
        ).some((issue) => issue.code === "UNSUPPORTED_EXERCISE")
      ).toBe(false)

    const ruleSpecializedLowConfidence = {
      ...ruleSpecialized,
      metadata: {
        ...ruleSpecialized.metadata,
        classificationConfidence:
          DEFAULT_POLICY.minimumSpecializedClassificationConfidence - 0.01,
      },
    }
    expect(
      exclusionReasons(
        ruleSpecializedLowConfidence,
        {
          ...full.preferences,
          preferredExerciseIds: [source.exercise.id],
        },
        DEFAULT_POLICY
      ).some((issue) => issue.code === "UNSUPPORTED_EXERCISE")
    ).toBe(true)

    const ruleAllowedLowConfidence = {
      ...ruleSpecialized,
      metadata: {
        ...ruleSpecialized.metadata,
        automaticProgramming: "allowed" as const,
        classificationConfidence:
          DEFAULT_POLICY.minimumAutomaticClassificationConfidence - 0.01,
      },
    }
    expect(
      exclusionReasons(
        ruleAllowedLowConfidence,
        {
          ...full.preferences,
          preferredExerciseIds: [source.exercise.id],
        },
        DEFAULT_POLICY
      ).some((issue) => issue.code === "UNSUPPORTED_EXERCISE")
    ).toBe(true)
  })

  it("classifies representative programming families deterministically", () => {
    const cases = [
      ["0025", "horizontal_push", "compound", "external_load", "bilateral", "chest"],
      ["0027", "horizontal_pull", "compound", "external_load", "bilateral", "upper-back"],
      ["0007", "vertical_pull", "compound", "external_load", "alternating", "upper-back"],
      ["0017", "vertical_pull", "compound", "assistance", "bilateral", "upper-back"],
      ["0024", "squat", "compound", "external_load", "bilateral", "quadriceps"],
      ["0032", "hinge", "compound", "external_load", "bilateral", "gluteal"],
      ["0054", "lunge", "compound", "external_load", "alternating", "gluteal"],
      ["1463", "squat", "compound", "external_load", "bilateral", "quadriceps"],
      ["0585", "knee_extension", "isolation", "external_load", "bilateral", "quadriceps"],
      ["0586", "knee_flexion", "isolation", "external_load", "bilateral", "hamstring"],
      ["3236", "hip_extension", "isolation", "band_resistance", "bilateral", "gluteal"],
      ["1370", "calf_raise", "isolation", "external_load", "bilateral", "calves"],
      ["0091", "vertical_push", "compound", "external_load", "bilateral", "deltoids"],
      ["0192", "shoulder_abduction", "isolation", "external_load", "unilateral", "deltoids"],
      ["0075", "horizontal_pull", "isolation", "external_load", "bilateral", "deltoids"],
      ["0031", "elbow_flexion", "isolation", "external_load", "bilateral", "biceps"],
      ["0201", "elbow_extension", "isolation", "external_load", "bilateral", "triceps"],
      ["1262", "horizontal_push", "isolation", "external_load", "unilateral", "chest"],
      ["3204", "trunk_flexion", "isolation", "bodyweight", "bilateral", "abs"],
      ["0573", "trunk_extension", "isolation", "external_load", "bilateral", "lower-back"],
      ["0493", "horizontal_push", "compound", "bodyweight", "bilateral", "chest"],
    ] as const

    for (const [id, pattern, mechanics, tracking, laterality, directMuscle] of cases) {
      const metadata = index.byId.get(id)?.metadata
      expect(metadata, id).toBeDefined()
      expect(metadata?.exerciseType, id).toBe("resistance")
      expect(metadata?.movementPatterns, id).toContain(pattern)
      expect(metadata?.mechanics, id).toBe(mechanics)
      expect(metadata?.tracking, id).toBe(tracking)
      expect(metadata?.laterality, id).toBe(laterality)
      expect(
        metadata?.setRoles.some(
          (role) => role.role === "direct" && role.muscleId === directMuscle
        ),
        id
      ).toBe(true)
    }

    expect(index.byId.get("1003")?.metadata.movementPatterns).toEqual([
      "horizontal_pull",
      "squat",
    ])
    expect(
      index.byId
        .get("0993")
        ?.metadata.setRoles.some(
          (role) => role.role === "direct" && role.muscleId === "chest"
        )
    ).toBe(false)
  })
})
describe("malformed input and hostile data", () => {
  it.each([null, undefined, 5, [], {}, { profile: {} }])(
    "returns structural invalid result for %j",
    (value) => {
      expect(
        generateTrainingProgram(value as ProgramGenerationRequest).status
      ).toBe("invalid")
    }
  )
  it("rejects 250 seeded malformed fields without throwing", () => {
    const rnd = random(931)
    const fields = [
      "age",
      "maxSessionDurationMinutes",
      "days",
      "goal",
      "now",
    ] as const
    const values: unknown[] = [
      NaN,
      Infinity,
      -1,
      null,
      {},
      [],
      "",
      "bad",
      99999,
    ]
    for (let i = 0; i < 250; i++) {
      const r = structuredClone(fastRequest())
      const field = fields[Math.floor(rnd() * fields.length)]
      const value = values[Math.floor(rnd() * values.length)]
      const object =
        field === "age"
          ? r.profile
          : field === "days"
            ? r.schedule
            : field === "now"
              ? r
              : r.preferences
      Object.assign(object, { [field]: value })
      expect(generateTrainingProgram(r).status).toBe("invalid")
    }
  })
  it("rejects invalid dates, duplicate IDs, bad weights and unsupported health", () => {
    const r = fastRequest()
    r.now = "2026-02-30T00:00:00.000Z"
    expect(validateGenerationRequest(r).length).toBeGreaterThan(0)
    r.now = full.now
    r.exercises = [r.exercises[0], r.exercises[0]]
    expect(generateTrainingProgram(r).status).toBe("invalid")
    r.exercises = [{ ...smallData[0], muscleWeights: [NaN] }]
    expect(generateTrainingProgram(r).status).toBe("invalid")
    r.exercises = smallData
    r.profile.health = { status: "unsupported", reasons: ["active_injury"] }
    expect(generateTrainingProgram(r).status).toBe("unsupported")
    r.profile.health = { status: "healthy" }
    r.profile.age = 17
    expect(generateTrainingProgram(r).status).toBe("unsupported")
    r.profile.age = 32
    r.preferences.goal = "power"
    expect(generateTrainingProgram(r).status).toBe("unsupported")
  })
  it("handles unknown/low-confidence metadata honestly and checks ancillary equipment", () => {
    const weird = inferExerciseMetadata({
      ...full.exercises[0],
      name: "uncatalogued movement",
    })
    expect(weird.exerciseType).toBe("unknown")
    expect(weird.setRoles).toEqual([])
    expect(index.byId.get("0025")!.metadata.requiredEquipment).toContain(
      "bench"
    )
    expect(
      exclusionReasons(
        index.byId.get("0025")!,
        { ...full.preferences, availableEquipment: ["barbell"] },
        DEFAULT_POLICY
      ).some((i) => i.code === "UNAVAILABLE_EQUIPMENT")
    ).toBe(true)
  })
  it("independent validator catches tampering and malformed programs", () => {
    const r = fastRequest()
    const result = generateTrainingProgram(r)
    expect("program" in result).toBe(true)
    if (!("program" in result)) return
    const i = createExerciseIndex(r.exercises)
    const mutations = [
      (p: typeof result.program) => {
        p.weeks[0].sessions[0].exercises[0].workingSets[0].targetReps.min = NaN
      },
      (p: typeof result.program) => {
        p.weeks[0].sessions[0].exercises[0].exerciseId = "missing"
      },
      (p: typeof result.program) => {
        p.weeks[0].sessions[0].exercises[0].workingSets[0].resistance = {
          type: "external_load",
          kg: 72.37,
          basis: "total",
          stationId: "A",
        }
      },
      (p: typeof result.program) => {
        p.weeks[0].sessions[0].duration.totalSeconds = 1
      },
      (p: typeof result.program) => {
        const chest = p.weeks[0].targets.find((t) => t.muscleId === "chest")!
        chest.preferred = Math.max(chest.minimum, chest.preferred - 2)
      },
      (p: typeof result.program) => {
        p.weeks[0].sessions[0].exercises[0].targetMuscles = ["forearm"]
      },
      (p: typeof result.program) => {
        p.weeks[0].sessions[0].exercises[0].progression.confidence = "high"
      },
      (p: typeof result.program) => {
        p.weeks[0].sessions[0].focus = ["forearm"]
      },
      (p: typeof result.program) => {
        p.weeks[0].phase = "reduced_volume"
      },
      (p: typeof result.program) => {
        p.diagnostics.score.total += 0.01
      },
      (p: typeof result.program) => {
        p.policy.maxSetsPerExercise += 1
      },
      (p: typeof result.program) => {
        p.weeks[0].sessions[0].exercises[0].workingSets[0].setType = "warmup"
      },
      (p: typeof result.program) => {
        p.weeks[0].sessions[0].scheduledAt = "2026-02-30T00:00:00.000Z"
      },
      (p: typeof result.program) => {
        p.weeks[0].sessions[0].exercises[0].workingSets[1] =
          p.weeks[0].sessions[0].exercises[0].workingSets[0]
      },
    ]
    for (const mutate of mutations) {
      const p = structuredClone(result.program)
      mutate(p)
      expect(validateTrainingProgram(p, r, i).valid).toBe(false)
    }
    const independent = structuredClone(result.program)
    independent.weeks[0].sessions[0].scheduledAt =
      "2026-02-30T00:00:00.000Z"
    independent.weeks[0].sessions[1].duration.totalSeconds = 1
    expect(
      validateTrainingProgram(independent, r, i).issues.some(
        (issue) => issue.path === "weeks.0.sessions.1.duration"
      )
    ).toBe(true)
    for (const v of [
      null,
      {},
      { weeks: [null] },
      { weeks: [], policy: DEFAULT_POLICY },
    ])
      expect(validateTrainingProgram(v, r, i).valid).toBe(false)
  }, 30_000)
})
