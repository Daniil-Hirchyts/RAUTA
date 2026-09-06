import { MUSCLE_IDS } from "../../types"
import type {
  ExerciseSummary,
  ExerciseMetadata,
  ExerciseIndex,
  IndexedExercise,
  MovementPattern,
  MuscleId,
  PlanningIssue,
  PlanningPreferences,
  TrainingPolicy,
} from "../domain/types"
import { compareIds, fingerprint, finite, isRecord } from "../numeric"
import {
  CURATION_VERSION,
  getCuratedExerciseReview,
  isFullyCuratedReview,
} from "./curated-exercises"

const RULE_VERSION = "1.2.0"
type PatternRule = {
  match: RegExp
  exclude?: RegExp
  pattern: MovementPattern
  direct: MuscleId[]
  indirect: MuscleId[]
  compound?: boolean
  familyId?: string
}
/** Roles are explicit anatomical programming approximations, independent of source weights. */
const RULES: PatternRule[] = [
  {
    match: /\b(calf|calves|heel) (raise|press)|calf.*raise/,
    pattern: "calf_raise",
    direct: ["calves"],
    indirect: [],
  },
  {
    match: /\b(leg|hamstring) curl\b/,
    pattern: "knee_flexion",
    direct: ["hamstring"],
    indirect: [],
  },
  {
    match: /\bleg extension\b/,
    pattern: "knee_extension",
    direct: ["quadriceps"],
    indirect: [],
  },
  {
    match: /\b(hip|thigh).*abduct/,
    pattern: "hip_abduction",
    direct: ["gluteal"],
    indirect: [],
  },
  {
    match: /\b(hip|thigh).*adduct/,
    pattern: "hip_adduction",
    direct: ["adductors"],
    indirect: [],
  },
  {
    match: /\b(deadlift|good morning)\b/,
    pattern: "hinge",
    direct: ["gluteal", "hamstring"],
    indirect: ["lower-back"],
    compound: true,
  },
  {
    match: /\b(lunge|split squat|step-up)\b/,
    pattern: "lunge",
    direct: ["quadriceps", "gluteal"],
    indirect: [],
    compound: true,
  },
  {
    match: /\b(squat|leg press)\b/,
    pattern: "squat",
    direct: ["quadriceps", "gluteal"],
    indirect: ["adductors"],
    compound: true,
  },
  {
    match: /\b(hip thrusts?|glute bridges?|kickback)\b/,
    pattern: "hip_extension",
    direct: ["gluteal"],
    indirect: ["hamstring"],
  },
  {
    match: /\b(bench press|chest press|push-up|push up|floor press)\b/,
    pattern: "horizontal_push",
    direct: ["chest"],
    indirect: ["triceps", "deltoids"],
    compound: true,
    familyId: "horizontal_press",
  },
  {
    match: /\b(shoulder press|military press|overhead press|arnold press)\b/,
    pattern: "vertical_push",
    direct: ["deltoids"],
    indirect: ["triceps"],
    compound: true,
  },
  {
    match: /\b(pulldown|pull-down|pull-up|chin-up)\b/,
    pattern: "vertical_pull",
    direct: ["upper-back"],
    indirect: ["biceps"],
    compound: true,
  },
  {
    match: /\brow\b/,
    pattern: "horizontal_pull",
    direct: ["upper-back"],
    indirect: ["biceps", "deltoids"],
    compound: true,
  },
  {
    match: /\b(reverse fly|rear delt)\b/,
    pattern: "horizontal_pull",
    direct: ["deltoids"],
    indirect: ["upper-back"],
    familyId: "rear_delt_fly",
  },
  {
    match: /\b(fly|flye)\b/,
    exclude: /\b(reverse fly|rear delt)\b/,
    pattern: "horizontal_push",
    direct: ["chest"],
    indirect: [],
    familyId: "chest_fly",
  },
  {
    match: /\b(triceps|tricep|pushdown|skull crusher)\b/,
    pattern: "elbow_extension",
    direct: ["triceps"],
    indirect: [],
  },
  {
    match:
      /\b(biceps|bicep|hammer curl|concentration curl|preacher curl)\b|^(barbell|dumbbell|cable|band|ez barbell) (standing |seated )?curl\b/,
    pattern: "elbow_flexion",
    direct: ["biceps"],
    indirect: [],
  },
  {
    match: /\blateral raise\b/,
    pattern: "shoulder_abduction",
    direct: ["deltoids"],
    indirect: [],
  },
  {
    match: /\b(crunch|sit-up|sit up)\b/,
    pattern: "trunk_flexion",
    direct: ["abs"],
    indirect: [],
  },
  {
    match: /\b(back extension|hyperextension)\b/,
    pattern: "trunk_extension",
    direct: ["lower-back"],
    indirect: ["gluteal"],
  },
  {
    match: /\b(russian twist|wood chop)\b/,
    pattern: "trunk_rotation",
    direct: ["obliques"],
    indirect: ["abs"],
  },
]
export function validateExerciseData(value: unknown): PlanningIssue[] {
  if (!Array.isArray(value)) return [{ code: "INVALID_EXERCISE_DATA" }]
  const ids = new Set<string>()
  return value.flatMap((e: unknown, i): PlanningIssue[] => {
    if (
      !isRecord(e) ||
      typeof e.id !== "string" ||
      !e.id ||
      typeof e.name !== "string" ||
      !e.name.trim() ||
      typeof e.equipment !== "string" ||
      !e.equipment ||
      !Array.isArray(e.muscles) ||
      !Array.isArray(e.muscleWeights) ||
      !Array.isArray(e.instructions)
    )
      return [{ code: "INVALID_EXERCISE_DATA", path: `exercises.${i}` }]
    const invalid =
      ids.has(e.id) ||
      e.muscles.length !== e.muscleWeights.length ||
      new Set(e.muscles).size !== e.muscles.length ||
      e.muscles.some((m) => !MUSCLE_IDS.includes(m as MuscleId)) ||
      e.muscleWeights.some((w) => !finite(w, 0, 1)) ||
      e.instructions.some((s) => typeof s !== "string") ||
      (e.primaryMuscle !== null && !e.muscles.includes(e.primaryMuscle))
    ids.add(e.id)
    return invalid
      ? [
          {
            code: "INVALID_EXERCISE_DATA",
            path: `exercises.${i}`,
            context: { exerciseId: e.id },
          },
        ]
      : []
  })
}
export function inferExerciseMetadata(e: ExerciseSummary): ExerciseMetadata {
  const name = e.name.toLowerCase()
  const instructions = e.instructions.join(" ").toLowerCase()
  const text = name + " " + instructions
  const detectedType = /\bstretch/.test(name)
    ? "stretch"
    : /\b(isometric|static hold|hold)\b|\bplank\b/.test(name)
      ? "isometric"
      : /\b(snatch|clean|jerk|jump|plyo|throw)\b/.test(name)
        ? "power"
    : /\b(run|running|bike|elliptical|stepmill|skierg|burpee|jumping jack|walk)\b/.test(
          name
        ) && e.primaryMuscle !== "abs"
      ? "conditioning"
      : /\b(mobility|roll massage|foam roll)\b/.test(name)
        ? "mobility"
        : "unknown"
  const complex =
    /\b(snatch|clean|jerk|jump|plyo|kipping|handstand|clap|pistol|bosu|throw|muscle-up|swing|zercher|jefferson|overhead squat|on knees|speed squat)\b/.test(
      name
    )
  const ambiguous =
    /\b(stretch|isometric|hold|static|assisted stretch|neck|wrist|finger|reverse grip curl|upright row|squat row|squatting row|pullover|sissy|behind neck)\b/.test(
      name
    )
  const partialRom = /\bpartial|\bhalf|\bquarter|3\/4/.test(name)
  const rules = RULES.filter(
    (rule) => rule.match.test(name) && !rule.exclude?.test(name)
  )
  // A primary-muscle mismatch is reviewable data, never silently overridden.
  const matchesMuscle =
    rules.length > 0 &&
    !!e.primaryMuscle &&
    rules.some((rule) =>
      [...rule.direct, ...rule.indirect].includes(e.primaryMuscle!)
    )
  const ruleSupported =
    detectedType === "unknown" &&
    rules.length > 0 &&
    matchesMuscle &&
    e.instructions.length >= 2
  const exerciseType = ruleSupported ? "resistance" : detectedType
  const equipment = new Set([e.equipment])
  if (/bench/.test(text) && !/leverage|smith|sled/.test(e.equipment))
    equipment.add("bench")
  if (/\brack\b/.test(text) && e.equipment === "barbell") equipment.add("rack")
  if (
    /pull-up|chin-up|pull up bar|chin up bar/.test(text) &&
    e.equipment === "body weight"
  )
    equipment.add("pull-up bar")
  if (/inverted row/.test(name)) equipment.add("low bar")
  if (/\b(stability ball|exercise ball)\b/.test(text))
    equipment.add("stability ball")
  if (/\b(chair|stool)\b/.test(text)) equipment.add("chair")
  if (
    /\b(step|box|platform)\b/.test(text) &&
    /step-up|calf|elevated/.test(name)
  )
    equipment.add("step")
  if (/\b(anchor|attach|secure)\b/.test(text) && /band/.test(e.equipment))
    equipment.add("band anchor")
  if (/\b(partner|assistance from someone)\b/.test(text))
    equipment.add("partner")
  if (/\b(towel|straps)\b/.test(name))
    equipment.add(name.includes("towel") ? "towel" : "suspension straps")
  const tracking =
    exerciseType === "isometric"
      ? "timed"
      : exerciseType === "conditioning" && /\b(run|running|walk)\b/.test(name)
        ? "distance"
        : /\bband\b/.test(e.equipment)
          ? "band_resistance"
    : e.equipment === "body weight"
      ? "bodyweight"
      : e.equipment === "assisted" ||
          (e.equipment === "leverage machine" && /\bassisted\b/.test(name))
        ? "assistance"
        : /^(barbell|dumbbell|cable|leverage machine|smith machine|sled machine|kettlebell|ez barbell|trap bar)$/.test(
              e.equipment
            )
          ? "external_load"
          : "unknown"
  const roleByMuscle = new Map<
    MuscleId,
    { muscleId: MuscleId; role: "direct" | "indirect"; provenance: "rule" }
  >()
  if (ruleSupported)
    for (const rule of rules) {
      for (const muscleId of rule.indirect)
        if (!roleByMuscle.has(muscleId))
          roleByMuscle.set(muscleId, {
            muscleId,
            role: "indirect",
            provenance: "rule",
          })
      for (const muscleId of rule.direct)
        roleByMuscle.set(muscleId, {
          muscleId,
          role: "direct",
          provenance: "rule",
        })
    }
  const patterns = ruleSupported
    ? [...new Set(rules.map((rule) => rule.pattern))].sort(compareIds)
    : (["unknown"] as MovementPattern[])
  const families = ruleSupported
    ? [...new Set(rules.map((rule) => rule.familyId ?? rule.pattern))]
    : []
  const familyId = families.length === 1 ? families[0] : undefined
  const automaticProgramming =
    exerciseType !== "resistance" || !ruleSupported || ambiguous || tracking === "unknown"
      ? "manual_only"
      : complex || partialRom
        ? "specialized_only"
        : "allowed"
  return {
    exerciseId: e.id,
    exerciseType,
    movementPatterns: patterns,
    mechanics: ruleSupported
      ? rules.some((rule) => rule.compound)
        ? "compound"
        : "isolation"
      : "unknown",
    laterality:
      /one arm|one leg|single arm|single leg|single-arm|single-leg|split squat/.test(
        name
      )
        ? "unilateral"
        : /alternat|lunge/.test(name)
          ? "alternating"
          : "bilateral",
    tracking,
    requiredEquipment: [...equipment].sort(compareIds),
    setRoles: [...roleByMuscle.values()].sort((a, b) =>
      compareIds(a.muscleId, b.muscleId)
    ),
    classificationConfidence:
      exerciseType === "resistance"
        ? ambiguous
          ? 0.45
          : complex || partialRom
            ? 0.6
            : 0.75
        : detectedType !== "unknown"
        ? 0.9
        : 0.2,
    skill: complex ? "complex" : ruleSupported ? "basic" : "unknown",
    setupSeconds: tracking === "external_load" ? 60 : 30,
    tags: [
      ...(!matchesMuscle && rules.length ? ["primary_mismatch"] : []),
      ...(complex ? ["complex_unreviewed"] : []),
      ...(partialRom ? ["partial_rom"] : []),
      ...(patterns.length > 1 ? ["multi_pattern"] : []),
    ],
    automaticProgramming,
    familyId,
    provenance: "rule",
    reviewStatus: "rule_only",
    reviewedFields: [],
    ruleVersion: RULE_VERSION,
  }
}

function curatedProvenance(
  reviewedFrom: readonly string[]
): ExerciseMetadata["provenance"] {
  const video = reviewedFrom.includes("video")
  const sampledFrames = reviewedFrom.includes("sampled_frames")
  const text = reviewedFrom.includes("name") || reviewedFrom.includes("instructions")
  if (video) return text ? "curated_video_and_text" : "curated_video"
  if (sampledFrames)
    return text ? "curated_sampled_frames_and_text" : "curated_sampled_frames"
  return "curated_text"
}

export function resolveExerciseMetadata(e: ExerciseSummary): ExerciseMetadata {
  const inferred = inferExerciseMetadata(e)
  const review = getCuratedExerciseReview(e.id)
  if (!review) return inferred
  const fullyReviewed = isFullyCuratedReview(review)
  return {
    ...inferred,
    ...review.metadata,
    exerciseId: e.id,
    tags: [
      ...new Set([...(inferred.tags ?? []), ...(review.metadata.tags ?? [])]),
    ].sort(compareIds),
    provenance: fullyReviewed
      ? curatedProvenance(review.reviewedFrom)
      : "curated",
    reviewStatus: fullyReviewed ? "fully_reviewed" : "partially_reviewed",
    reviewedFields: [...(review.reviewedFields ?? [])].sort(compareIds),
    ruleVersion: `${RULE_VERSION}+curation-${CURATION_VERSION}`,
  }
}
export function validateMetadata(
  m: ExerciseMetadata,
  e?: ExerciseSummary
): PlanningIssue[] {
  const valid =
    isRecord(m) &&
    !!e &&
    m.exerciseId === e.id &&
    [
      "resistance",
      "isometric",
      "stretch",
      "mobility",
      "conditioning",
      "power",
      "unknown",
    ].includes(m.exerciseType) &&
    ["compound", "isolation", "unknown"].includes(m.mechanics) &&
    ["bilateral", "unilateral", "alternating", "unknown"].includes(
      m.laterality
    ) &&
    [
      "external_load",
      "assistance",
      "bodyweight",
      "band_resistance",
      "repetition_only",
      "timed",
      "distance",
      "unknown",
    ].includes(m.tracking) &&
    finite(m.classificationConfidence, 0, 1) &&
    finite(m.setupSeconds, 0, 600) &&
    Array.isArray(m.requiredEquipment) &&
    (m.provenance !== "rule" || m.requiredEquipment.includes(e.equipment)) &&
    m.requiredEquipment.every((x) => typeof x === "string" && x.length > 0) &&
    Array.isArray(m.setRoles) &&
    m.setRoles.every(
      (r) =>
        isRecord(r) &&
        MUSCLE_IDS.includes(r.muscleId as MuscleId) &&
        ["direct", "indirect", "incidental"].includes(String(r.role)) &&
        ["rule", "curated"].includes(String(r.provenance))
    ) &&
    new Set(m.setRoles.map((r) => r.muscleId)).size === m.setRoles.length &&
    Array.isArray(m.movementPatterns) &&
    m.movementPatterns.length > 0 &&
    m.movementPatterns.every((p) =>
      [
        ...RULES.map((r) => r.pattern),
        "anti_extension",
        "carry",
        "unknown",
      ].includes(p)
    ) &&
    Array.isArray(m.tags) &&
    m.tags.every((t) => typeof t === "string") &&
    ["basic", "complex", "unknown"].includes(m.skill) &&
    ["allowed", "specialized_only", "manual_only"].includes(
      m.automaticProgramming
    ) &&
    (m.familyId === undefined ||
      (typeof m.familyId === "string" && m.familyId.length > 0)) &&
    (m.variantOf === undefined ||
      (typeof m.variantOf === "string" &&
        m.variantOf.length > 0 &&
        m.variantOf !== m.exerciseId)) &&
    (m.duplicateOf === undefined ||
      (typeof m.duplicateOf === "string" &&
        m.duplicateOf.length > 0 &&
        m.duplicateOf !== m.exerciseId)) &&
    [
      "rule",
      "curated",
      "curated_text",
      "curated_video",
      "curated_video_and_text",
      "curated_sampled_frames",
      "curated_sampled_frames_and_text",
    ].includes(m.provenance) &&
    typeof m.ruleVersion === "string" &&
    !!m.ruleVersion &&
    (m.reviewStatus === undefined ||
      ["rule_only", "partially_reviewed", "fully_reviewed"].includes(
        m.reviewStatus
      )) &&
    (m.reviewedFields === undefined ||
      (Array.isArray(m.reviewedFields) &&
        m.reviewedFields.every((field) => typeof field === "string"))) &&
    (m.exerciseType !== "resistance" ||
      m.automaticProgramming === "manual_only" ||
      (m.setRoles.some((r) => r.role === "direct") &&
        !m.movementPatterns.includes("unknown") &&
        m.mechanics !== "unknown"))
  return valid
    ? []
    : [{ code: "INVALID_EXERCISE_DATA", context: { metadata: true } }]
}
export function createExerciseIndex(
  exercises: ExerciseSummary[],
  overrides: ExerciseMetadata[] = []
): ExerciseIndex {
  const issues = validateExerciseData(exercises)
  const byId = new Map<string, IndexedExercise>()
  const byMuscle = new Map<MuscleId, IndexedExercise[]>()
  const byDirectMuscle = new Map<MuscleId, IndexedExercise[]>()
  const byPrimaryMuscle = new Map<MuscleId, IndexedExercise[]>()
  const byEquipment = new Map<string, IndexedExercise[]>()
  const byMovementPattern = new Map<MovementPattern, IndexedExercise[]>()
  const byFamily = new Map<string, IndexedExercise[]>()
  const byAutomaticProgramming = new Map<
    ExerciseMetadata["automaticProgramming"],
    IndexedExercise[]
  >()
  const byTracking = new Map<ExerciseMetadata["tracking"], IndexedExercise[]>()
  const byMechanics = new Map<ExerciseMetadata["mechanics"], IndexedExercise[]>()
  const byExerciseType = new Map<
    ExerciseMetadata["exerciseType"],
    IndexedExercise[]
  >()
  const result = {
    byId,
    byMuscle,
    byDirectMuscle,
    byPrimaryMuscle,
    byEquipment,
    byMovementPattern,
    byFamily,
    byAutomaticProgramming,
    byTracking,
    byMechanics,
    byExerciseType,
    issues,
    fingerprint: "",
  }
  if (issues.length) return result
  const metadata = new Map<string, ExerciseMetadata>()
  for (const m of overrides) {
    issues.push(
      ...validateMetadata(
        m,
        exercises.find((e) => e.id === m.exerciseId)
      )
    )
    if (metadata.has(m.exerciseId))
      issues.push({
        code: "INVALID_EXERCISE_DATA",
        context: { duplicateMetadata: m.exerciseId },
      })
    metadata.set(m.exerciseId, m)
  }
  if (issues.length) return result
  const exerciseIds = new Set(exercises.map((exercise) => exercise.id))
  const effectiveMetadata = new Map<string, ExerciseMetadata>()
  for (const exercise of exercises) {
    const explicit = metadata.get(exercise.id)
    const m = structuredClone(explicit ?? resolveExerciseMetadata(exercise))
    // Built-in catalogue relationships may point outside a caller-supplied subset.
    // Keep the local index self-contained while requiring explicit overrides to be valid.
    if (!explicit) {
      if (m.variantOf && !exerciseIds.has(m.variantOf)) delete m.variantOf
      if (m.duplicateOf && !exerciseIds.has(m.duplicateOf)) delete m.duplicateOf
    }
    issues.push(...validateMetadata(m, exercise))
    effectiveMetadata.set(exercise.id, m)
  }
  if (issues.length) return result
  for (const m of effectiveMetadata.values()) {
    for (const relationship of [m.variantOf, m.duplicateOf])
      if (relationship && !exerciseIds.has(relationship))
        issues.push({
          code: "INVALID_EXERCISE_DATA",
          context: {
            exerciseId: m.exerciseId,
            invalidRelationship: relationship,
          },
        })
  }
  const state = new Map<string, "visiting" | "visited">()
  const stack: string[] = []
  let relationshipCycle: string[] | undefined
  const visitRelationship = (exerciseId: string): boolean => {
    if (state.get(exerciseId) === "visiting") {
      const start = stack.indexOf(exerciseId)
      relationshipCycle = [...stack.slice(start), exerciseId]
      return true
    }
    if (state.get(exerciseId) === "visited") return false
    state.set(exerciseId, "visiting")
    stack.push(exerciseId)
    const current = effectiveMetadata.get(exerciseId)
    for (const target of [current?.variantOf, current?.duplicateOf])
      if (target && visitRelationship(target)) return true
    stack.pop()
    state.set(exerciseId, "visited")
    return false
  }
  for (const exerciseId of [...exerciseIds].sort(compareIds)) {
    if (visitRelationship(exerciseId)) break
  }
  if (relationshipCycle)
    issues.push({
      code: "INVALID_EXERCISE_DATA",
      context: { relationshipCycle },
    })
  if (issues.length) return result
  const append = <K>(
    map: Map<K, IndexedExercise[]>,
    key: K,
    item: IndexedExercise
  ) => map.set(key, [...(map.get(key) ?? []), item])
  for (const source of [...exercises].sort((a, b) => compareIds(a.id, b.id))) {
    const exercise = structuredClone(source)
    const m = structuredClone(effectiveMetadata.get(exercise.id)!)
    const item = {
      exercise,
      metadata: m,
      participation: exercise.muscles.map((muscleId, i) => ({
        muscleId,
        relativeInvolvement: exercise.muscleWeights[i],
      })),
    }
    byId.set(exercise.id, item)
    for (const role of m.setRoles) {
      if (role.role !== "incidental") append(byMuscle, role.muscleId, item)
      if (role.role === "direct") append(byDirectMuscle, role.muscleId, item)
    }
    if (exercise.primaryMuscle)
      append(byPrimaryMuscle, exercise.primaryMuscle, item)
    for (const eq of m.requiredEquipment) append(byEquipment, eq, item)
    for (const pattern of m.movementPatterns)
      append(byMovementPattern, pattern, item)
    if (m.familyId) append(byFamily, m.familyId, item)
    append(byAutomaticProgramming, m.automaticProgramming, item)
    append(byTracking, m.tracking, item)
    append(byMechanics, m.mechanics, item)
    append(byExerciseType, m.exerciseType, item)
  }
  result.fingerprint = fingerprint([...byId.values()])
  return result
}
export function exclusionReasons(
  e: IndexedExercise,
  p: PlanningPreferences,
  policy: TrainingPolicy
): PlanningIssue[] {
  const context = { exerciseId: e.exercise.id }
  const issues: PlanningIssue[] = []
  if (p.excludedExerciseIds?.includes(e.exercise.id))
    issues.push({ code: "EXCLUDED_EXERCISE", context })
  const missing = e.metadata.requiredEquipment.filter(
    (eq) => eq !== "body weight" && !p.availableEquipment.includes(eq)
  )
  if (missing.length)
    issues.push({
      code: "UNAVAILABLE_EQUIPMENT",
      context: { ...context, missing },
    })
  const explicitlyRequested =
    p.preferredExerciseIds?.includes(e.exercise.id) ||
    p.strengthExerciseIds?.includes(e.exercise.id)
  const automaticProgrammingBlocked =
    e.metadata.automaticProgramming === "manual_only" ||
    (e.metadata.automaticProgramming === "specialized_only" &&
      !explicitlyRequested)
  const lowConfidenceRule =
    e.metadata.provenance === "rule" &&
    e.metadata.classificationConfidence <
      (e.metadata.automaticProgramming === "specialized_only"
        ? policy.minimumSpecializedClassificationConfidence
        : policy.minimumAutomaticClassificationConfidence)
  if (
    e.metadata.exerciseType !== "resistance" ||
    automaticProgrammingBlocked ||
    lowConfidenceRule ||
    e.metadata.movementPatterns.some((pattern) =>
      p.excludedPatterns?.includes(pattern)
    )
  )
    issues.push({ code: "UNSUPPORTED_EXERCISE", context })
  return issues
}
