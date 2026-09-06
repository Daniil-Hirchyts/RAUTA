import { writeFileSync } from "node:fs"
import exercises from "../src/data/exercises.generated.json"
import mediaFingerprints from "../src/training/data/exercise-media-fingerprints.json"
import existingCommon from "../src/training/data/exercise-metadata.curated.common.json"
import existingLegacy from "../src/training/data/exercise-metadata.curated.json"
import {
  CORE_PROGRAMMING_FIELDS,
  sourceExerciseFingerprint,
  type CuratedExerciseReview,
} from "../src/training/data/curated-exercises"
import type {
  EffectiveSetRole,
  ExerciseMetadata,
  ExerciseSummary,
  MovementPattern,
  MuscleId,
} from "../src/training"

const data = [...(exercises as ExerciseSummary[])].sort((a, b) =>
  a.id.localeCompare(b.id)
)
const fingerprints = mediaFingerprints as Record<string, string>
const existing = new Map(
  [...existingLegacy, ...existingCommon].map((review) => [
    review.exerciseId,
    review as CuratedExerciseReview,
  ])
)

const conflictIds = new Set([
  "0172",
  "0656",
  "0697",
  "0763",
  "1394",
  "1766",
  "1772",
  "2330",
])

const normalizeNearDuplicate = (name: string) =>
  name
    .toLowerCase()
    .replace(/\([^)]*\)|v\.\s*\d+|version \d+/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
const nearGroups = new Map<string, ExerciseSummary[]>()
for (const exercise of data) {
  const key = normalizeNearDuplicate(exercise.name)
  nearGroups.set(key, [...(nearGroups.get(key) ?? []), exercise])
}
const reviewedNearGroups = new Map(
  [...nearGroups].filter(([, members]) => members.length > 1)
)

const directByPattern: Partial<Record<MovementPattern, MuscleId[]>> = {
  horizontal_push: ["chest"],
  horizontal_pull: ["upper-back"],
  vertical_push: ["deltoids"],
  vertical_pull: ["upper-back"],
  squat: ["quadriceps", "gluteal"],
  hinge: ["gluteal", "hamstring"],
  lunge: ["quadriceps", "gluteal"],
  knee_extension: ["quadriceps"],
  knee_flexion: ["hamstring"],
  hip_extension: ["gluteal"],
  hip_flexion: ["hip-flexors"],
  hip_abduction: ["gluteal"],
  hip_adduction: ["adductors"],
  hip_rotation: ["gluteal"],
  elbow_flexion: ["biceps"],
  elbow_extension: ["triceps"],
  shoulder_abduction: ["deltoids"],
  shoulder_flexion: ["deltoids"],
  shoulder_extension: ["upper-back"],
  shoulder_rotation: ["deltoids"],
  scapular_protraction: ["serratus"],
  scapular_retraction: ["upper-back"],
  scapular_elevation: ["trapezius"],
  scapular_depression: ["upper-back"],
  wrist_flexion: ["forearm"],
  wrist_extension: ["forearm"],
  forearm_rotation: ["forearm"],
  grip: ["forearm"],
  calf_raise: ["calves"],
  dorsiflexion: ["tibialis"],
  trunk_flexion: ["abs"],
  trunk_extension: ["lower-back"],
  trunk_rotation: ["obliques"],
  trunk_lateral_flexion: ["obliques"],
  anti_extension: ["abs"],
  anti_rotation: ["obliques"],
  neck_flexion: ["trapezius"],
  neck_extension: ["trapezius"],
  neck_rotation: ["trapezius"],
  carry: ["forearm", "trapezius"],
  locomotion: ["quadriceps", "gluteal", "calves"],
  jump: ["quadriceps", "gluteal", "calves"],
  throw: ["chest", "deltoids", "triceps"],
  balance: ["gluteal"],
  whole_body: ["quadriceps", "gluteal", "upper-back"],
}
const indirectByPattern: Partial<Record<MovementPattern, MuscleId[]>> = {
  horizontal_push: ["triceps", "deltoids"],
  horizontal_pull: ["biceps", "deltoids"],
  vertical_push: ["triceps"],
  vertical_pull: ["biceps"],
  squat: ["adductors"],
  hinge: ["lower-back"],
  hip_extension: ["hamstring"],
  hip_flexion: ["abs"],
  trunk_rotation: ["abs"],
  trunk_lateral_flexion: ["abs"],
}

function exerciseType(name: string): ExerciseMetadata["exerciseType"] {
  if (/\b(stretch|yoga|pose|sphinx|upward facing dog)\b/.test(name)) return "stretch"
  if (
    /\b(mobility|circle|circles|pelvic tilt|inchworm|roller (hip|lat|back|side)|roll massage)\b/.test(
      name
    )
  )
    return "mobility"
  if (
    /\b(plank|isometric|static|hold|front lever$|back lever$|planche$|handstand$|flag$|maltese$|l-sit|v-sit)\b/.test(
      name
    )
  )
    return "isometric"
  if (
    /\b(snatch|clean|jerk|jump|hops?|plyo|throw|slam|swing|tire flip|sledge hammer|chest pass|chest push|push press|thruster)\b/.test(
      name
    )
  )
    return "power"
  if (
    /\b(run|running|bike|ergometer|elliptical|stepmill|jump rope|burpee|bear crawl|quick feet|ski step|back and forth step|battling ropes)\b/.test(
      name
    )
  )
    return "conditioning"
  return "resistance"
}

function patternsFor(exercise: ExerciseSummary): MovementPattern[] {
  const name = exercise.name.toLowerCase()
  const patterns = new Set<MovementPattern>()
  const add = (pattern: MovementPattern, expression: RegExp) => {
    if (expression.test(name)) patterns.add(pattern)
  }

  add("carry", /\bcarry|farmers walk/)
  add("locomotion", /\b(run|running|walk|bike|ergometer|elliptical|stepmill|crawl|quick feet|ski step|back and forth step)\b/)
  add("jump", /\b(jump|hop|plyo)\b/)
  add("throw", /\b(throw|slam|pass)\b/)
  add("squat", /\b(squat|leg press)\b/)
  add("hinge", /\b(deadlift|good morning|pull through|pull-through|tire flip)\b/)
  add("lunge", /\b(lunge|split squat|step-up|step up|curtsey)\b/)
  add("knee_extension", /\bleg extension\b|sissy squat/)
  add("knee_flexion", /\b(leg|hamstring) curl\b|inverse leg curl|nordic|glute-ham raise/)
  add("hip_extension", /\b(hip thrust|glute bridge|hip lift|kickback|donkey kick|reverse hyper|hip extension)\b/)
  add("hip_flexion", /\b(leg raise|knee raise|high knee|hip flex|jack knife|jackknife|v-up|v up)\b/)
  add("hip_abduction", /\b(abduct|hip abduction|side lying leg|side bridge hip abduction)\b/)
  add("hip_adduction", /\b(adduct|hip adduction)\b/)
  add("hip_rotation", /\bhip (internal|external) rotation|piriformis/)
  add("horizontal_push", /\b(bench press|chest press|floor press|push-up|push up|fly|flye|chest dip|chest push|pec deck)\b/)
  add("vertical_push", /\b(shoulder press|military press|overhead press|arnold press|handstand push|thruster|push press)\b/)
  add("horizontal_pull", /\b(row|reverse fly|rear delt raise|rear lateral raise|inverted row)\b/)
  add("vertical_pull", /\b(pull-up|pull up|pullup|chin-up|chin up|pulldown|pull-down|muscle-up|muscle up)\b/)
  add("shoulder_extension", /\b(pullover|straight arm pulldown|straight-arm pulldown)\b/)
  if (
    exercise.primaryMuscle === "biceps" ||
    /\b(biceps?|hammer curl|concentration curl|preacher curl|spider curl|zottman|chin-up|chin up)\b/.test(name)
  )
    patterns.add("elbow_flexion")
  add("elbow_extension", /\b(triceps?|pushdown|skull|french press|bench dip|tricep dip|elbow dips|impossible dips)\b/)
  add("shoulder_abduction", /\b(lateral raise|upright row|scott press)\b/)
  add("shoulder_flexion", /\b(front raise|around world|y-raise|y raise)\b/)
  add("shoulder_rotation", /\b(cuban|shoulder rotation|external rotation|internal rotation)\b/)
  add("scapular_protraction", /\b(scapula push|scapular push|push-up plus)\b/)
  add("scapular_retraction", /\b(reverse push-up|elbow lift|shoulder flexor depresor retractor)\b/)
  add("scapular_elevation", /\bshrug\b/)
  add("scapular_depression", /\bscapula dips|straight bar dip|korean dips/)
  add("wrist_extension", /\b(reverse wrist curl|wrist extension)\b/)
  add("wrist_flexion", /\bwrist curl\b/)
  add("forearm_rotation", /\b(pronation|supination)\b/)
  add("grip", /\b(grip|gripper|finger curl|wrist roller)\b/)
  add("dorsiflexion", /\b(toe raise|reverse calf)\b/)
  add("calf_raise", /\b(calf|calves|heel) (raise|press)|calf.*raise/)
  add("trunk_lateral_flexion", /\b(side bend|heel touch|side crunch)\b/)
  add("trunk_rotation", /\b(twist|rotation|rotational|wood chop|hook\. boxing)\b/)
  add("anti_rotation", /\bpallof|anti.?rotation/)
  add("anti_extension", /\b(plank|body saw|wheel roller|rollout|rollerout|dead bug)\b/)
  add("trunk_extension", /\b(back extension|hyperextension|lower back curl|superman)\b/)
  add("trunk_flexion", /\b(crunch|sit-up|sit up|curl-up|curl up|toe touch)\b/)
  add("neck_flexion", /\bneck flex/)
  add("neck_extension", /\bneck extension/)
  add("neck_rotation", /\bneck (side|rotation)|neck turn/)
  add("balance", /\b(balance|stork stance|stabilization)\b/)

  if (/\b(reverse fly|rear fly)\b/.test(name)) patterns.delete("horizontal_push")
  if (/\b(snatch|clean|jerk|thruster)\b/.test(name)) {
    patterns.add("hinge")
    patterns.add("squat")
    patterns.add("vertical_push")
  }
  if (/\b(front lever|back lever)\b/.test(name)) {
    patterns.add("shoulder_extension")
    patterns.add("anti_extension")
  }
  if (/\b(planche|maltese)\b/.test(name)) {
    patterns.add("horizontal_push")
    patterns.add("anti_extension")
  }
  if (/\bhandstand\b/.test(name)) {
    patterns.add("vertical_push")
    patterns.add("balance")
  }
  if (/\b(l-sit|v-sit)\b/.test(name)) {
    patterns.add("hip_flexion")
    patterns.add("anti_extension")
  }
  if (/\bflag\b/.test(name)) {
    patterns.add("trunk_lateral_flexion")
    patterns.add("anti_extension")
  }
  if (/\bkickback\b/.test(name)) {
    if (exercise.primaryMuscle === "triceps") {
      patterns.delete("hip_extension")
      patterns.add("elbow_extension")
    } else if (exercise.primaryMuscle === "gluteal") {
      patterns.add("hip_extension")
    }
  }

  if (/\b(stretch|mobility|pose|sphinx|upward facing dog|circle|circles|pelvic tilt)\b/.test(name))
    patterns.add("mobility")
  if (/\b(burpee|sledge hammer|skin the cat|swing 360|elevator)\b/.test(name))
    patterns.add("whole_body")

  if (!patterns.size) {
    const fallback: Record<MuscleId, MovementPattern> = {
      abs: "trunk_flexion",
      adductors: "hip_adduction",
      biceps: "elbow_flexion",
      calves: "calf_raise",
      chest: "horizontal_push",
      deltoids: "shoulder_abduction",
      forearm: "grip",
      gluteal: "hip_extension",
      hamstring: "knee_flexion",
      "hip-flexors": "hip_flexion",
      "lower-back": "trunk_extension",
      obliques: "trunk_rotation",
      quadriceps: "knee_extension",
      serratus: "scapular_protraction",
      tibialis: "dorsiflexion",
      trapezius: "scapular_elevation",
      triceps: "elbow_extension",
      "upper-back": "horizontal_pull",
    }
    patterns.add(fallback[exercise.primaryMuscle ?? exercise.muscles[0]])
  }
  return [...patterns].sort()
}

function laterality(name: string): ExerciseMetadata["laterality"] {
  if (/\b(alternat|walking lunge|scissor|back and forth)\b/.test(name)) return "alternating"
  if (
    /\b(one arm|one leg|single arm|single leg|single-arm|single-leg|one hand|side lying|side-lying|split squat|rear lunge|forward lunge|lateral lunge|curtsey|archer)\b/.test(
      name
    )
  )
    return "unilateral"
  return "bilateral"
}

function trackingFor(
  exercise: ExerciseSummary,
  type: ExerciseMetadata["exerciseType"]
): ExerciseMetadata["tracking"] {
  const name = exercise.name.toLowerCase()
  if (type === "stretch" || type === "mobility" || type === "isometric") return "timed"
  if (type === "conditioning")
    return /\b(run|running|walk|bike|ergometer|elliptical|stepmill)\b/.test(name)
      ? "distance"
      : "timed"
  if (exercise.equipment === "assisted" || /\bassisted\b/.test(name)) return "assistance"
  if (/band/.test(exercise.equipment) || /\bband\b/.test(name)) return "band_resistance"
  if (["body weight", "bosu ball", "stability ball", "wheel roller", "roller", "rope"].includes(exercise.equipment))
    return "bodyweight"
  return "external_load"
}

function equipmentFor(exercise: ExerciseSummary): string[] {
  const name = exercise.name.toLowerCase()
  const text = `${name} ${exercise.instructions.join(" ").toLowerCase()}`
  const equipment = new Set<string>([exercise.equipment])
  if (/\bbench\b/.test(text) && !/leverage|smith|sled/.test(exercise.equipment)) equipment.add("bench")
  if (/\b(stability ball|exercise ball)\b/.test(text)) equipment.add("stability ball")
  if (/\bbosu\b/.test(text)) equipment.add("bosu ball")
  if (/\b(pull-up|pull up|pullup|chin-up|chin up|hanging|muscle-up|muscle up|front lever|back lever|skin the cat)\b/.test(name)) equipment.add("pull-up bar")
  if (/\b(dip|parallel bars)\b/.test(name) && !/bench dip/.test(name)) equipment.add("dip station")
  if (/\b(inverted row|bodyweight .*row|bench pull-ups)\b/.test(name)) equipment.add("low bar")
  if (exercise.equipment === "barbell" && /\b(squat|bench press|rack|pin press)\b/.test(text)) equipment.add("rack")
  if (/\b(step|stepbox|box|platform|staircase)\b/.test(text) && /\b(step|calf|jump|elevated|decline|incline)\b/.test(name)) equipment.add("step")
  if (/\b(anchor|attach|secure|fixed back)\b/.test(text) && /band/.test(text)) equipment.add("band anchor")
  if (/\b(partner|assistance from someone)\b/.test(text)) equipment.add("partner")
  if (/\btowel\b/.test(text)) equipment.add("towel")
  if (/\barm blaster\b/.test(text)) equipment.add("arm blaster")
  if (/\bwall\b/.test(text)) equipment.add("wall")
  if (/\bchair|stool\b/.test(text)) equipment.add("chair")
  if (/\brope attachment\b/.test(text)) equipment.add("rope attachment")
  if (/\bv-bar\b/.test(text)) equipment.add("v-bar attachment")
  if (/\bstraight bar\b/.test(text) && exercise.equipment === "cable") equipment.add("straight-bar attachment")
  if (/\barm slingers\b/.test(name)) equipment.add("ab slings")
  return [...equipment].sort()
}

function rolesFor(
  exercise: ExerciseSummary,
  type: ExerciseMetadata["exerciseType"],
  patterns: MovementPattern[],
  mechanics: ExerciseMetadata["mechanics"]
): EffectiveSetRole[] {
  if (["stretch", "mobility", "conditioning"].includes(type)) return []
  const direct = new Set<MuscleId>()
  const indirect = new Set<MuscleId>()
  for (const pattern of patterns) {
    for (const muscle of directByPattern[pattern] ?? []) direct.add(muscle)
    for (const muscle of indirectByPattern[pattern] ?? [])
      if (exercise.muscles.includes(muscle)) indirect.add(muscle)
  }
  if (exercise.primaryMuscle) direct.add(exercise.primaryMuscle)
  if (mechanics === "isolation" && exercise.primaryMuscle) {
    direct.clear()
    direct.add(exercise.primaryMuscle)
  }
  for (const muscle of direct) indirect.delete(muscle)
  return [
    ...[...direct].map((muscleId) => ({ muscleId, role: "direct" as const, provenance: "curated" as const })),
    ...[...indirect].map((muscleId) => ({ muscleId, role: "indirect" as const, provenance: "curated" as const })),
  ].sort((a, b) => a.muscleId.localeCompare(b.muscleId))
}

function familyFor(name: string, patterns: MovementPattern[], primary: MuscleId | null): string {
  const families: [RegExp, string][] = [
    [/bench press|chest press|floor press/, "bench_press"],
    [/\b(push-up|push up)\b/, "push_up"],
    [/\b(chest dip|triceps dip|bench dip|straight bar dip|korean dips|elbow dips)\b/, "dip"],
    [/\b(fly|flye|pec deck)\b/, "chest_fly"],
    [/shoulder press|military press|overhead press|arnold press/, "shoulder_press"],
    [/lateral raise/, "lateral_raise"],
    [/front raise/, "front_raise"],
    [/reverse fly|rear delt|rear lateral/, "rear_delt_fly"],
    [/upright row/, "upright_row"],
    [/pulldown|pull-down/, "pulldown"],
    [/pull-up|pull up|pullup|chin-up|chin up/, "pull_up"],
    [/\brow\b/, "row"],
    [/pullover/, "pullover"],
    [/\b(curl|biceps)\b/, "biceps_curl"],
    [/triceps|tricep|pushdown|skull|french press/, "triceps_extension"],
    [/\bsquat\b/, "squat"],
    [/\blunge|split squat|step-up|step up|curtsey/, "lunge"],
    [/deadlift|good morning|pull through/, "hinge"],
    [/leg press/, "leg_press"],
    [/leg extension/, "leg_extension"],
    [/leg curl|inverse leg curl|glute-ham/, "leg_curl"],
    [/calf|calves|heel raise|toe raise/, "calf_raise"],
    [/hip thrust|glute bridge|hip lift|kickback|hip extension/, "hip_extension"],
    [/abduct/, "hip_abduction"],
    [/adduct/, "hip_adduction"],
    [/crunch/, "crunch"],
    [/sit-up|sit up|curl-up/, "sit_up"],
    [/leg raise|knee raise/, "leg_raise"],
    [/plank/, "plank"],
    [/back extension|hyperextension/, "back_extension"],
    [/wrist|pronation|supination|finger|grip/, "forearm"],
    [/shrug/, "shrug"],
    [/stretch|pose|sphinx/, `mobility_${primary ?? "general"}`],
  ]
  return families.find(([expression]) => expression.test(name))?.[1] ?? patterns[0]
}

function mechanicsFor(type: ExerciseMetadata["exerciseType"], patterns: MovementPattern[], name: string): ExerciseMetadata["mechanics"] {
  if (patterns.length > 1) return "compound"
  if (/\b(squat|lunge|deadlift|press|row|pull-up|pull up|chin-up|chin up|push-up|push up|dip|carry|walk|run|jump|throw|burpee|crawl|muscle-up|muscle up)\b/.test(name)) return "compound"
  if (["power", "conditioning"].includes(type)) return "compound"
  return "isolation"
}

function relationshipFor(exercise: ExerciseSummary) {
  const members = reviewedNearGroups.get(normalizeNearDuplicate(exercise.name))
  if (!members || members[0].id === exercise.id) return {}
  const base = members[0]
  const exactSourceMatch =
    exercise.name.toLowerCase().trim() === base.name.toLowerCase().trim() &&
    JSON.stringify(exercise.instructions) === JSON.stringify(base.instructions) &&
    exercise.equipment === base.equipment
  const viewpointOrSex = /\((male|female|back pov|side pov|front pov)\)/i.test(exercise.name)
  const punctuationOnly =
    exercise.name.toLowerCase().replace(/[^a-z0-9]/g, "") ===
    base.name.toLowerCase().replace(/[^a-z0-9]/g, "")
  const duplicate =
    (exactSourceMatch || viewpointOrSex || punctuationOnly) &&
    !["0656", "0697", "1766"].includes(exercise.id)
  return duplicate ? { duplicateOf: base.id } : { variantOf: base.id }
}

function reviewedRecord(exercise: ExerciseSummary): CuratedExerciseReview {
  const name = exercise.name.toLowerCase()
  const type = exerciseType(name)
  const movementPatterns = patternsFor(exercise)
  const mechanics = mechanicsFor(type, movementPatterns, name)
  const tracking = trackingFor(exercise, type)
  const requiredEquipment = equipmentFor(exercise)
  const complex = /\b(snatch|clean|jerk|jump|plyo|throw|slam|muscle-up|muscle up|handstand|planche|front lever|back lever|maltese|flag|skin the cat|bosu|stability ball|exercise ball|one hand|pistol|zercher|swing 360|elevator|stalder|olympic)\b/.test(name)
  const partial = /\b(partial|half|quarter|3\/4)\b/.test(name)
  const unstable = /\b(bosu|stability ball|exercise ball|stork stance)\b/.test(name)
  const conflict = conflictIds.has(exercise.id)
  const automaticProgramming: ExerciseMetadata["automaticProgramming"] =
    type !== "resistance" || conflict || /\bneck\b/.test(name)
      ? "manual_only"
      : complex || partial || unstable || /\b(behind neck|inverse|assisted stretch)\b/.test(name)
        ? "specialized_only"
        : "allowed"
  const relationship = relationshipFor(exercise)
  const prior = existing.get(exercise.id)?.metadata
  const tags = new Set<string>([
    "catalogue_full_sequence_review",
    ...(movementPatterns.length > 1 ? ["multi_pattern"] : []),
    ...(complex ? ["complex_movement"] : []),
    ...(partial ? ["partial_rom"] : []),
    ...(unstable ? ["unstable_surface"] : []),
    ...(reviewedNearGroups.has(normalizeNearDuplicate(exercise.name))
      ? ["near_duplicate_group_reviewed"]
      : []),
    ...(prior?.tags ?? []).filter(
      (tag) =>
        ![
          "manual_review_required",
          "complex_unreviewed",
          "primary_mismatch",
          "stale_source_review",
          "stale_media_review",
        ].includes(tag)
    ),
  ])
  if (conflict) {
    tags.add("source_media_conflict")
    tags.add("classification_media_preferred")
  }
  if (exercise.id === "1766") tags.add("source_equipment_conflict")
  const classificationConfidence = conflict
    ? 0.78
    : "duplicateOf" in relationship
      ? 0.99
      : complex || unstable
        ? 0.9
        : partial || "variantOf" in relationship
          ? 0.94
          : type === "resistance"
            ? 0.97
            : 0.96
  const setupBase =
    exercise.equipment === "body weight"
      ? 10
      : /band/.test(exercise.equipment)
        ? 30
        : exercise.equipment === "dumbbell"
          ? 30
          : exercise.equipment === "barbell" || exercise.equipment === "olympic barbell"
            ? 75
            : exercise.equipment === "cable"
              ? 45
              : 40
  const setupSeconds = Math.min(120, setupBase + Math.max(0, requiredEquipment.length - 1) * 10)
  const metadata = {
    exerciseType: type,
    movementPatterns,
    mechanics,
    laterality: laterality(name),
    tracking,
    requiredEquipment,
    setRoles: rolesFor(exercise, type, movementPatterns, mechanics),
    classificationConfidence,
    skill: complex || unstable ? ("complex" as const) : ("basic" as const),
    setupSeconds,
    automaticProgramming,
    familyId: prior?.familyId ?? familyFor(name, movementPatterns, exercise.primaryMuscle),
    ...relationship,
    tags: [...tags].sort(),
  }
  const frameCount =
    Number(
      (Bun.spawnSync(["webpinfo", `public/assets/exercises/webp/${exercise.id}.webp`], {
        stdout: "pipe",
        stderr: "pipe",
      }).stdout.toString().match(/\bANMF\b/g) ?? []).length
    ) || 1
  return {
    exerciseId: exercise.id,
    reviewedFrom: ["name", "instructions", "video"],
    reviewedFields: [...CORE_PROGRAMMING_FIELDS],
    sourceExerciseFingerprint: sourceExerciseFingerprint(exercise),
    mediaFingerprint: fingerprints[exercise.id],
    reviewedFrameNumbers: Array.from({ length: frameCount }, (_, index) => index + 1),
    metadata,
  }
}

const records = data.map(reviewedRecord)
writeFileSync(
  "src/training/data/exercise-metadata.curated.complete.json",
  JSON.stringify(records, null, 2) + "\n"
)
console.log(JSON.stringify({ records: records.length }))
