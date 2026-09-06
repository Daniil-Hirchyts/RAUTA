import type {
  Experience,
  IndexedExercise,
  MuscleId,
  OptimizationInput,
  PlannedExercise,
  PlannedSession,
  Score,
  TrainingWeek,
} from "../domain/types"
import { DEFAULT_POLICY } from "../policy"
import { clamp, mean } from "../numeric"
import {
  calculateSessionVolume,
  effectiveSetCredit,
  emptyVolume,
} from "../analysis/volume"
import { estimateSessionDuration } from "../planning/duration"

export function skillSuitability(
  experience: Experience,
  skill: IndexedExercise["metadata"]["skill"],
  explicitlyPreferred = false,
  strengthSpecific = false
): number {
  if (strengthSpecific) return 1
  if (explicitlyPreferred) return 0.95
  if (experience === "advanced") return skill === "unknown" ? 0.85 : 1
  if (experience === "intermediate")
    return skill === "complex" ? 0.9 : skill === "unknown" ? 0.75 : 1
  return skill === "complex" ? 0.25 : skill === "unknown" ? 0.6 : 1
}

export function weightedScore(
  values: Record<string, number>,
  weights: Record<string, number>
): Score {
  const contributions = Object.entries(values).map(([factor, value]) => {
    const rawValue = clamp(value)
    const weight = weights[factor] ?? 0
    return { factor, rawValue, weight, contribution: rawValue * weight }
  })
  const denominator = Object.values(weights).reduce(
    (sum, w) => sum + Math.abs(w),
    0
  )
  return {
    total: denominator
      ? contributions.reduce((sum, c) => sum + c.contribution, 0) / denominator
      : 0,
    contributions,
  }
}
function jaccard(a: string[], b: string[]) {
  const union = new Set([...a, ...b])
  return union.size ? a.filter((x) => b.includes(x)).length / union.size : 0
}
export function exerciseSimilarity(
  a: IndexedExercise,
  b: IndexedExercise,
  weights = DEFAULT_POLICY.similarityWeights
): number {
  if (a.exercise.id === b.exercise.id) return 1
  return (
    weights.family *
      Number(
        !!a.metadata.familyId && a.metadata.familyId === b.metadata.familyId
      ) +
    weights.patterns *
      jaccard(a.metadata.movementPatterns, b.metadata.movementPatterns) +
    weights.directMuscles *
      jaccard(
        a.metadata.setRoles
          .filter((r) => r.role === "direct")
          .map((r) => r.muscleId),
        b.metadata.setRoles
          .filter((r) => r.role === "direct")
          .map((r) => r.muscleId)
      ) +
    weights.mechanics * Number(a.metadata.mechanics === b.metadata.mechanics) +
    weights.tracking * Number(a.metadata.tracking === b.metadata.tracking) +
    weights.laterality * Number(a.metadata.laterality === b.metadata.laterality) +
    weights.equipment * Number(a.exercise.equipment === b.exercise.equipment)
  )
}
export function volumeUtility(
  volume: number,
  preferred: number,
  upper: number
): number {
  if (!preferred) return volume <= upper ? 1 : 0
  return volume <= preferred
    ? clamp(volume / preferred)
    : clamp(1 - (volume - preferred) / Math.max(1, upper - preferred))
}
export function scoreExercise(
  e: IndexedExercise,
  session: PlannedSession,
  week: TrainingWeek,
  input: OptimizationInput
): Score {
  return createExerciseScorer(session, week, input)(e)
}
export function createExerciseScorer(
  session: PlannedSession,
  week: TrainingWeek,
  input: OptimizationInput
): (e: IndexedExercise) => Score {
  const { index, policy, targets, request, state } = input
  const sessionVolume = calculateSessionVolume(session, index, policy)
  const allocated = emptyVolume()
  for (const s of week.sessions) {
    const v = calculateSessionVolume(s, index, policy)
    for (const target of targets)
      allocated[target.muscleId].effective += v[target.muscleId].effective
  }
  const relevant = targets.filter(
    (t) => session.focus.includes(t.muscleId) && t.preferred > 0
  )
  const existing = session.exercises.flatMap((p) => {
    const e = index.byId.get(p.exerciseId)
    return e ? [e] : []
  })
  const usedPatterns = existing.flatMap((e) => e.metadata.movementPatterns)
  return (e: IndexedExercise): Score => {
    const coverage =
      relevant.reduce((sum, t) => {
        const weekly =
          allocated[t.muscleId].effective +
          (input.baselineVolume?.[t.muscleId] ?? 0)
        const exposureSlots = week.sessions.filter((s) =>
          s.focus.includes(t.muscleId)
        ).length
        const quota = t.preferred / Math.max(1, exposureSlots)
        return (
          sum +
          effectiveSetCredit(e, t.muscleId, policy).effective *
            t.importance *
            Math.min(
              clamp((t.preferred - weekly) / Math.max(1, t.preferred)),
              clamp(
                (quota - sessionVolume[t.muscleId].effective) /
                  Math.max(1, quota)
              )
            )
        )
      }, 0) / Math.max(1, relevant.reduce((n, t) => n + t.importance, 0) / 3)
    const specificity = request.preferences.strengthExerciseIds?.includes(
      e.exercise.id
    )
      ? 1
      : e.metadata.tracking === "external_load" &&
          e.metadata.mechanics === "compound"
        ? 0.5
        : 0
    const continuity =
      input.continuityIds?.includes(e.exercise.id) ||
      state.exercises[e.exercise.id]?.exposureCount
        ? 1
        : 0
    const preference = request.preferences.dislikedExerciseIds?.includes(
      e.exercise.id
    )
      ? 0
      : request.preferences.preferredExerciseIds?.includes(e.exercise.id)
        ? 1
        : 0.5
    const skillFit = skillSuitability(
      request.profile.trainingExperience,
      e.metadata.skill,
      request.preferences.preferredExerciseIds?.includes(e.exercise.id),
      request.preferences.strengthExerciseIds?.includes(e.exercise.id)
    )
    const muscles = e.metadata.setRoles
      .filter((r) => r.role === "direct")
      .map((r) => r.muscleId)
    const workload = mean(
      muscles.map(
        (m) =>
          clamp(
            state.muscles[m].decayedWorkload / policy.sessionMuscleGuideline
          ) +
          (request.readiness?.soreness?.some(
            (s) => s.muscleId === m && s.level === "high"
          )
            ? 1
            : 0)
      )
    )
    const goal =
      policy.goals[
        request.preferences.goal === "power"
          ? "general_fitness"
          : request.preferences.goal
      ]
    return weightedScore(
      {
        coverage,
        specificity,
        continuity,
        preference,
        skillSuitability: skillFit,
        patternNeed: e.metadata.movementPatterns.some(
          (p) => !usedPatterns.includes(p)
        )
          ? 1
          : 0,
        quality: e.metadata.classificationConfidence,
        redundancy: existing.length
          ? Math.max(
              ...existing.map((x) =>
                exerciseSimilarity(e, x, input.policy.similarityWeights)
              )
            )
          : 0,
        workload,
        duration:
          e.metadata.setupSeconds /
          (request.preferences.maxSessionDurationMinutes * 60),
      },
      {
        ...policy.exerciseWeights,
        specificity: goal.specificityWeight,
        continuity:
          policy.exerciseWeights.continuity *
          (input.continuityIds?.length ? 2 : 1),
      }
    )
  }
}

export function orderExercises(
  exercises: PlannedExercise[],
  input: OptimizationInput
): PlannedExercise[] {
  const importance = (p: PlannedExercise) => {
    const e = input.index.byId.get(p.exerciseId)!
    const explicit = input.request.preferences.strengthExerciseIds?.includes(
      p.exerciseId
    )
      ? input.policy.orderingWeights.specific
      : 0
    const priority = Math.max(
      ...e.metadata.setRoles
        .filter((r) => r.role === "direct")
        .map(
          (r) =>
            input.targets.find((t) => t.muscleId === r.muscleId)?.importance ??
            1
        ),
      0
    )
    return (
      explicit +
      priority * input.policy.orderingWeights.priority +
      Number(e.metadata.mechanics === "compound") *
        input.policy.orderingWeights.compound
    )
  }
  return [...exercises]
    .sort((a, b) => importance(b) - importance(a) || a.order - b.order)
    .map((e, order) => ({ ...e, order }))
}
export function scoreSession(
  session: PlannedSession,
  input: OptimizationInput
): Score {
  const volume = calculateSessionVolume(session, input.index, input.policy)
  const list = session.exercises.flatMap((p) => {
    const e = input.index.byId.get(p.exerciseId)
    return e ? [e] : []
  })
  const pairs = list.flatMap((e, i) =>
    list
      .slice(i + 1)
      .map((x) => exerciseSimilarity(e, x, input.policy.similarityWeights))
  )
  const duration = estimateSessionDuration(
    session,
    input.index,
    input.policy
  ).totalSeconds
  const ideal =
    (input.request.preferences.preferredSessionDurationMinutes ??
      input.request.preferences.maxSessionDurationMinutes) * 60
  const coverage =
    session.focus.filter((m) => volume[m].effective > 0).length /
    Math.max(1, session.focus.length)
  const concentration = mean(
    input.targets
      .filter((t) => t.preferred)
      .map((t) =>
        clamp(
          (volume[t.muscleId].effective - input.policy.sessionMuscleGuideline) /
            input.policy.sessionMuscleGuideline
        )
      )
  )
  return weightedScore(
    {
      coverage,
      duration: duration <= ideal ? 1 : clamp(ideal / duration),
      quality: mean(list.map((e) => e.metadata.classificationConfidence)),
      redundancy: mean(pairs),
      concentration,
      nonempty: Number(list.length > 0),
    },
    input.policy.sessionWeights
  )
}
export function scoreWeek(week: TrainingWeek, input: OptimizationInput): Score {
  const { index, policy, targets, request } = input
  const volumes = week.sessions.map((s) =>
    calculateSessionVolume(s, index, policy)
  )
  const targeted = targets.filter((t) => t.preferred > 0)
  const denom = targeted.reduce((n, t) => n + t.importance, 0)
  const volume =
    targeted.reduce(
      (n, t) =>
        n +
        t.importance *
          volumeUtility(
            volumes.reduce(
              (sum, v) => sum + v[t.muscleId].effective,
              input.baselineVolume?.[t.muscleId] ?? 0
            ),
            t.preferred,
            t.upperGuideline
          ),
      0
    ) / Math.max(1, denom)
  const frequency = mean(
    targeted.map((t) =>
      clamp(
        volumes.filter(
          (v) => v[t.muscleId].effective >= policy.meaningfulExposureSets
        ).length / Math.max(1, t.preferredExposures)
      )
    )
  )
  const selected = week.sessions
    .flatMap((s) => s.exercises)
    .flatMap((p) => {
      const e = index.byId.get(p.exerciseId)
      return e ? [e] : []
    })
  const patterns = new Set(selected.flatMap((e) => e.metadata.movementPatterns))
  const families: string[][] = [
    ["horizontal_push", "vertical_push"],
    ["horizontal_pull", "vertical_pull"],
    ["squat", "lunge"],
    ["hinge", "knee_flexion", "hip_extension"],
    ["trunk_flexion", "trunk_rotation"],
  ]
  const balance =
    families.filter((f) => f.some((p) => patterns.has(p as never))).length /
    families.length
  const redundancies = week.sessions.map((s) => {
    const list = s.exercises
      .map((p) => index.byId.get(p.exerciseId)!)
      .filter(Boolean)
    return mean(
      list.flatMap((e, i) =>
        list
          .slice(i + 1)
          .map((x) => exerciseSimilarity(e, x, input.policy.similarityWeights))
      )
    )
  })
  const preferredMinutes =
    request.preferences.preferredSessionDurationMinutes ??
    request.preferences.maxSessionDurationMinutes
  const duration = mean(
    week.sessions.map((s) => {
      const d = estimateSessionDuration(s, index, policy).totalSeconds
      return d <= preferredMinutes * 60 ? 1 : clamp((preferredMinutes * 60) / d)
    })
  )
  const recoveryConflicts: number[] = []
  for (let i = 0; i < week.sessions.length; i++) {
    const next = (i + 1) % week.sessions.length
    const gap =
      ((Date.parse(week.sessions[next].scheduledAt) -
        Date.parse(week.sessions[i].scheduledAt)) /
        3_600_000 +
        168) %
        168 || 168
    if (gap < policy.workloadHalfLifeHours)
      recoveryConflicts.push(
        mean(
          targeted.map(
            (t) =>
              Math.min(
                volumes[i][t.muscleId].effective,
                volumes[next][t.muscleId].effective
              ) / policy.sessionMuscleGuideline
          )
        ) *
          (1 - gap / policy.workloadHalfLifeHours)
      )
  }
  const specificIds = request.preferences.strengthExerciseIds ?? []
  const goal =
    policy.goals[
      request.preferences.goal === "power"
        ? "general_fitness"
        : request.preferences.goal
    ]
  const specificity = specificIds.length
    ? specificIds.filter((id) => selected.some((e) => e.exercise.id === id))
        .length / specificIds.length
    : mean(
        selected.map((e) =>
          Number(
            e.metadata.tracking === "external_load" &&
              e.metadata.mechanics === "compound"
          )
        )
      )
  return weightedScore(
    {
      volume,
      specificity,
      frequency,
      balance,
      quality: mean(selected.map((e) => e.metadata.classificationConfidence)),
      continuity: mean(
        selected.map((e) =>
          Number(
            !!input.state.exercises[e.exercise.id]?.exposureCount ||
              !!input.continuityIds?.includes(e.exercise.id)
          )
        )
      ),
      duration,
      preference: mean(
        selected.map((e) =>
          request.preferences.dislikedExerciseIds?.includes(e.exercise.id)
            ? 0
            : request.preferences.preferredExerciseIds?.includes(e.exercise.id)
              ? 1
              : 0.5
        )
      ),
      redundancy: mean(redundancies),
      recovery: mean(recoveryConflicts),
      session: mean(
        week.sessions.map((s) => Math.max(0, scoreSession(s, input).total))
      ),
    },
    {
      ...policy.programWeights,
      specificity: policy.programWeights.specificity * goal.specificityWeight,
    }
  )
}
export function weekVolume(
  week: TrainingWeek,
  input: OptimizationInput
): Record<MuscleId, number> {
  const v = emptyVolume()
  for (const s of week.sessions) {
    const current = calculateSessionVolume(s, input.index, input.policy)
    for (const t of input.targets)
      v[t.muscleId].effective += current[t.muscleId].effective
  }
  return Object.fromEntries(
    input.targets.map((t) => [
      t.muscleId,
      v[t.muscleId].effective + (input.baselineVolume?.[t.muscleId] ?? 0),
    ])
  ) as Record<MuscleId, number>
}
