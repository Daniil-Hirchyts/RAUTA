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

const RULE_VERSION = "1.0.0"
type PatternRule = {
  match: RegExp
  pattern: MovementPattern
  direct: MuscleId[]
  indirect: MuscleId[]
  compound?: boolean
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
    match: /\b(hip thrust|glute bridge|kickback)\b/,
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
  },
  {
    match: /\b(fly|flye)\b/,
    pattern: "horizontal_push",
    direct: ["chest"],
    indirect: [],
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
  const type = /\bstretch/.test(name)
    ? "stretch"
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
  const rule = RULES.find((r) => r.match.test(name))
  // A primary-muscle mismatch is reviewable data, never silently overridden.
  const matchesMuscle =
    !!rule &&
    !!e.primaryMuscle &&
    [...rule.direct, ...rule.indirect].includes(e.primaryMuscle)
  const classified =
    type === "unknown" &&
    !!rule &&
    matchesMuscle &&
    !complex &&
    !ambiguous &&
    e.instructions.length >= 2
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
    e.equipment === "body weight"
      ? "bodyweight"
      : e.equipment === "assisted"
        ? "assistance"
        : /^(barbell|dumbbell|cable|leverage machine|smith machine|sled machine|kettlebell|ez barbell|trap bar)$/.test(
              e.equipment
            )
          ? "external_load"
          : "unknown"
  return {
    exerciseId: e.id,
    exerciseType: classified ? "resistance" : type,
    movementPatterns: classified && rule ? [rule.pattern] : ["unknown"],
    mechanics:
      classified && rule
        ? rule.compound
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
    setRoles:
      classified && rule
        ? [
            ...rule.direct.map((muscleId) => ({
              muscleId,
              role: "direct" as const,
              provenance: "rule" as const,
            })),
            ...rule.indirect.map((muscleId) => ({
              muscleId,
              role: "indirect" as const,
              provenance: "rule" as const,
            })),
          ]
        : [],
    classificationConfidence: classified
      ? 0.75
      : type !== "unknown"
        ? 0.9
        : 0.2,
    skill: complex ? "complex" : classified ? "basic" : "unknown",
    setupSeconds: tracking === "external_load" ? 60 : 30,
    tags: [
      ...(!matchesMuscle && rule ? ["primary_mismatch"] : []),
      ...(complex ? ["complex_unreviewed"] : []),
      ...(/\bpartial|\bhalf|\bquarter|3\/4/.test(name) ? ["partial_rom"] : []),
    ],
    provenance: "rule",
    ruleVersion: RULE_VERSION,
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
    ["resistance", "stretch", "mobility", "conditioning", "unknown"].includes(
      m.exerciseType
    ) &&
    ["compound", "isolation", "unknown"].includes(m.mechanics) &&
    ["bilateral", "unilateral", "alternating", "unknown"].includes(
      m.laterality
    ) &&
    ["external_load", "assistance", "bodyweight", "unknown"].includes(
      m.tracking
    ) &&
    finite(m.classificationConfidence, 0, 1) &&
    finite(m.setupSeconds, 0, 600) &&
    Array.isArray(m.requiredEquipment) &&
    m.requiredEquipment.includes(e.equipment) &&
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
    ["rule", "curated"].includes(m.provenance) &&
    typeof m.ruleVersion === "string" &&
    !!m.ruleVersion &&
    (m.exerciseType !== "resistance" ||
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
  const byPrimaryMuscle = new Map<MuscleId, IndexedExercise[]>()
  const byEquipment = new Map<string, IndexedExercise[]>()
  const byMovementPattern = new Map<MovementPattern, IndexedExercise[]>()
  const byExerciseType = new Map<
    ExerciseMetadata["exerciseType"],
    IndexedExercise[]
  >()
  const result = {
    byId,
    byMuscle,
    byPrimaryMuscle,
    byEquipment,
    byMovementPattern,
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
  const append = <K>(
    map: Map<K, IndexedExercise[]>,
    key: K,
    item: IndexedExercise
  ) => map.set(key, [...(map.get(key) ?? []), item])
  for (const source of [...exercises].sort((a, b) => compareIds(a.id, b.id))) {
    const exercise = structuredClone(source)
    const m = structuredClone(
      metadata.get(exercise.id) ?? inferExerciseMetadata(exercise)
    )
    const item = {
      exercise,
      metadata: m,
      participation: exercise.muscles.map((muscleId, i) => ({
        muscleId,
        relativeInvolvement: exercise.muscleWeights[i],
      })),
    }
    byId.set(exercise.id, item)
    for (const role of m.setRoles)
      if (role.role !== "incidental") append(byMuscle, role.muscleId, item)
    if (exercise.primaryMuscle)
      append(byPrimaryMuscle, exercise.primaryMuscle, item)
    for (const eq of m.requiredEquipment) append(byEquipment, eq, item)
    for (const pattern of m.movementPatterns)
      append(byMovementPattern, pattern, item)
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
  if (
    e.metadata.exerciseType !== "resistance" ||
    e.metadata.classificationConfidence <
      policy.minimumClassificationConfidence ||
    e.metadata.tags.includes("partial_rom") ||
    e.metadata.skill === "complex" ||
    e.metadata.movementPatterns.some((pattern) =>
      p.excludedPatterns?.includes(pattern)
    )
  )
    issues.push({ code: "UNSUPPORTED_EXERCISE", context })
  return issues
}
