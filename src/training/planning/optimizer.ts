import type {
  IndexedExercise,
  MuscleId,
  OptimizationInput,
  OptimizationResult,
  PlannedSession,
  ProgramOptimizer,
  TrainingWeek,
} from "../domain/types"
import { addDays, compareIds } from "../numeric"
import { exclusionReasons } from "../data/exercises"
import { estimateSessionDuration } from "./duration"
import { prescribeExercise } from "./prescribe"
import {
  createExerciseScorer,
  orderExercises,
  scoreWeek,
  weekVolume,
} from "../scoring/scores"
const UPPER: MuscleId[] = [
  "chest",
  "upper-back",
  "deltoids",
  "biceps",
  "triceps",
  "trapezius",
  "forearm",
  "serratus",
]
const PUSH: MuscleId[] = ["chest", "deltoids", "triceps", "serratus"]
const PULL: MuscleId[] = ["upper-back", "biceps", "trapezius", "forearm"]
export function generateSplitCandidates(input: OptimizationInput) {
  const all = input.targets
    .filter((t) => t.preferred > 0)
    .map((t) => t.muscleId)
  const lower = all.filter((m) => !UPPER.includes(m))
  const upper = all.filter((m) => UPPER.includes(m))
  const days = [...input.request.schedule.days].sort((a, b) => a - b)
  const structures = [
    { name: "full_body", groups: [all] },
    ...(days.length >= 2
      ? [{ name: "upper_lower", groups: [upper, lower] }]
      : []),
    ...(days.length >= 3
      ? [
          {
            name: "push_pull_legs",
            groups: [
              all.filter((m) => PUSH.includes(m)),
              all.filter((m) => PULL.includes(m)),
              lower,
            ],
          },
        ]
      : []),
  ]
  return structures.map(({ name, groups }) => ({
    name,
    sessions: days.map((day, i): PlannedSession => ({
      id: `week-0/day-${day}`,
      scheduledAt: addDays(input.request.schedule.weekStart, day),
      focus: groups[i % groups.length],
      exercises: [],
      duration: estimateSessionDuration(
        { exercises: [] },
        input.index,
        input.policy
      ),
    })),
  }))
}
export function allocationForSplit(
  sessions: PlannedSession[],
  input: OptimizationInput
) {
  return sessions.map((s) => ({
    sessionId: s.id,
    muscles: Object.fromEntries(
      s.focus.map((m) => [
        m,
        (input.targets.find((t) => t.muscleId === m)?.preferred ?? 0) /
          Math.max(1, sessions.filter((s) => s.focus.includes(m)).length),
      ])
    ),
  }))
}
function weekKey(week: TrainingWeek) {
  return week.sessions
    .map((s) =>
      s.exercises
        .map((e) => e.exerciseId + ":" + e.workingSets.length)
        .join(",")
    )
    .join("|")
}
export function hardConstructionChecks(
  week: TrainingWeek,
  input: OptimizationInput,
  requireNonempty = false
): boolean {
  if (requireNonempty && week.sessions.some((s) => !s.exercises.length))
    return false
  if (
    week.sessions.some(
      (s) =>
        estimateSessionDuration(s, input.index, input.policy).totalSeconds >
        input.request.preferences.maxSessionDurationMinutes * 60
    )
  )
    return false
  const sets = week.sessions.reduce(
    (n, s) => n + s.exercises.reduce((n, e) => n + e.workingSets.length, 0),
    0
  )
  if (sets > (input.request.preferences.maxWeeklyWorkingSets ?? Infinity))
    return false
  const volume = weekVolume(week, input)
  return !(input.request.preferences.muscleVolumeBounds ?? []).some(
    (b) =>
      volume[b.muscleId] > (b.maximum ?? Infinity) + 1e-6 ||
      (requireNonempty && volume[b.muscleId] < (b.minimum ?? 0) - 1e-6)
  )
}
function poolForSession(
  session: PlannedSession,
  input: OptimizationInput,
  valid: Set<string>
): IndexedExercise[] {
  const map = new Map<string, IndexedExercise>()
  for (const m of session.focus)
    for (const e of input.index.byMuscle.get(m) ?? [])
      if (valid.has(e.exercise.id)) map.set(e.exercise.id, e)
  return [...map.values()].sort((a, b) =>
    compareIds(a.exercise.id, b.exercise.id)
  )
}
function improveWeek(
  initial: TrainingWeek,
  input: OptimizationInput,
  pools: IndexedExercise[][]
): { week: TrainingWeek; iterations: number } {
  let best = initial
  let score = scoreWeek(best, input).total
  let iterations = 0
  // Coordinate descent: reduce unnecessary sets or swap one exercise, retaining feasibility.
  for (let pass = 0; pass < input.policy.localIterations; pass++) {
    let improved = false
    for (let si = 0; si < best.sessions.length && !improved; si++)
      for (
        let ei = 0;
        ei < best.sessions[si].exercises.length && !improved;
        ei++
      ) {
        const original = best.sessions[si].exercises[ei]
        const scorer = createExerciseScorer(best.sessions[si], best, input)
        const swaps = pools[si]
          .filter(
            (e) =>
              !best.sessions[si].exercises.some(
                (p) => p.exerciseId === e.exercise.id
              )
          )
          .map((e) => ({ e, score: scorer(e) }))
          .sort(
            (a, b) =>
              b.score.total - a.score.total ||
              compareIds(a.e.exercise.id, b.e.exercise.id)
          )
          .slice(0, 2)
        const mutations = [
          ...(original.workingSets.length > 1
            ? [
                prescribeExercise(
                  input.index.byId.get(original.exerciseId)!,
                  original.workingSets.length - 1,
                  best.sessions[si].id,
                  original.rationale,
                  input
                ),
              ]
            : []),
          ...swaps.map((x) =>
            prescribeExercise(
              x.e,
              original.workingSets.length,
              best.sessions[si].id,
              x.score,
              input
            )
          ),
        ]
        for (const replacement of mutations) {
          iterations++
          const candidate: TrainingWeek = {
            ...best,
            sessions: best.sessions.map((s, i) =>
              i !== si
                ? s
                : {
                    ...s,
                    exercises: s.exercises.map((p, j) =>
                      j === ei ? replacement : p
                    ),
                  }
            ),
          }
          if (!hardConstructionChecks(candidate, input, true)) continue
          const next = scoreWeek(candidate, input).total
          if (next > score + 1e-8) {
            best = candidate
            score = next
            improved = true
            break
          }
        }
      }
    if (!improved) break
  }
  return { week: best, iterations }
}
export const beamOptimizer: ProgramOptimizer = {
  optimize(input): OptimizationResult {
    const valid = new Set(
      [...input.index.byId.values()]
        .filter(
          (e) =>
            exclusionReasons(e, input.request.preferences, input.policy)
              .length === 0
        )
        .map((e) => e.exercise.id)
    )
    const candidates = generateSplitCandidates(input)
    const results: {
      name: string
      week: TrainingWeek
      score: number
      valid: boolean
    }[] = []
    let iterations = 0
    for (const split of candidates) {
      const pools = split.sessions.map((s) => poolForSession(s, input, valid))
      let beam: TrainingWeek[] = [
        {
          id: "week-0",
          start: input.request.schedule.weekStart,
          phase: "base",
          sessions: split.sessions,
          targets: input.targets,
        },
      ]
      for (
        let depth = 0;
        depth < input.policy.maxExercisesPerSession * split.sessions.length;
        depth++
      ) {
        const si = depth % split.sessions.length
        const expansions: TrainingWeek[] = []
        for (const week of beam) {
          const session = week.sessions[si]
          if (session.exercises.length) expansions.push(week)
          const scorer = createExerciseScorer(session, week, input)
          const ranked = pools[si]
            .filter(
              (e) =>
                !session.exercises.some((p) => p.exerciseId === e.exercise.id)
            )
            .map((e) => ({ e, score: scorer(e) }))
            .sort(
              (a, b) =>
                b.score.total - a.score.total ||
                compareIds(a.e.exercise.id, b.e.exercise.id)
            )
            .slice(0, input.policy.candidateLimit)
          for (const { e, score } of ranked)
            for (const count of Array.from(
              { length: input.policy.maxSetsPerExercise },
              (_, index) => index + 1
            )) {
              iterations++
              const prescribed = prescribeExercise(
                e,
                count,
                session.id,
                score,
                input
              )
              const updated = {
                ...session,
                exercises: [
                  ...session.exercises,
                  { ...prescribed, order: session.exercises.length },
                ],
              }
              const next = {
                ...week,
                sessions: week.sessions.map((s, i) => (i === si ? updated : s)),
              }
              if (hardConstructionChecks(next, input)) expansions.push(next)
            }
        }
        if (!expansions.length) break
        const seen = new Set<string>()
        beam = expansions
          .map((week) => ({
            week,
            score: scoreWeek(week, input).total,
            key: weekKey(week),
          }))
          .sort((a, b) => b.score - a.score || compareIds(a.key, b.key))
          .filter((x) => {
            if (seen.has(x.key)) return false
            seen.add(x.key)
            return true
          })
          .slice(0, input.policy.beamWidth)
          .map((x) => x.week)
      }
      const eligible = beam.filter((w) =>
        hardConstructionChecks(w, input, true)
      )
      const selected = eligible[0] ?? beam[0]
      const improved = hardConstructionChecks(selected, input, true)
        ? improveWeek(selected, input, pools)
        : { week: selected, iterations: 0 }
      iterations += improved.iterations
      const week = {
        ...improved.week,
        sessions: improved.week.sessions.map((s) => {
          const ordered = {
            ...s,
            exercises: orderExercises(s.exercises, input),
          }
          return {
            ...ordered,
            duration: estimateSessionDuration(
              ordered,
              input.index,
              input.policy
            ),
          }
        }),
      }
      results.push({
        name: split.name,
        week,
        score: scoreWeek(week, input).total,
        valid: hardConstructionChecks(week, input, true),
      })
    }
    const best = results
      .filter((r) => r.valid)
      .sort((a, b) => b.score - a.score || compareIds(a.name, b.name))[0]
    return {
      week: best?.week,
      split: best?.name ?? "none",
      candidates: valid.size,
      iterations,
      splits: results.map((r) => ({
        name: r.name,
        score: r.score,
        valid: r.valid,
      })),
    }
  },
}
