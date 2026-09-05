import { MUSCLE_IDS } from "../../types"
import type {
  CompletedSet,
  ExerciseIndex,
  IndexedExercise,
  MuscleId,
  MuscleVolume,
  PlannedSession,
  TrainingHistory,
  TrainingPolicy,
  TrainingProgram,
} from "../domain/types"
export const emptyVolume = (): Record<MuscleId, MuscleVolume> =>
  Object.fromEntries(
    MUSCLE_IDS.map((m) => [m, { direct: 0, indirect: 0, effective: 0 }])
  ) as Record<MuscleId, MuscleVolume>
export function effectiveSetCredit(
  e: IndexedExercise,
  muscle: MuscleId,
  policy: TrainingPolicy
): MuscleVolume {
  const role = e.metadata.setRoles.find((r) => r.muscleId === muscle)?.role
  const direct = role === "direct" ? 1 : 0
  const indirect = role === "indirect" ? policy.indirectCredit : 0
  return { direct, indirect, effective: direct + indirect }
}
export function isWorkingSet(s: CompletedSet): boolean {
  return (
    s.completed &&
    s.reps > 0 &&
    (s.setType === "working" || s.setType === "backoff")
  )
}
export function addExerciseVolume(
  volume: Record<MuscleId, MuscleVolume>,
  e: IndexedExercise,
  count: number,
  policy: TrainingPolicy
) {
  for (const r of e.metadata.setRoles) {
    const credit =
      r.role === "direct"
        ? count
        : r.role === "indirect"
          ? count * policy.indirectCredit
          : 0
    if (r.role === "direct") volume[r.muscleId].direct += credit
    if (r.role === "indirect") volume[r.muscleId].indirect += credit
    volume[r.muscleId].effective += credit
  }
}
export function calculateHistoryVolume(
  history: TrainingHistory,
  index: ExerciseIndex,
  policy: TrainingPolicy,
  from: number,
  to: number,
  inclusiveStart = false
) {
  const volume = emptyVolume()
  for (const session of history.sessions)
    for (const performed of session.exercises) {
      const e = index.byId.get(performed.exerciseId)
      if (!e) continue
      for (const set of performed.sets) {
        const time = Date.parse(set.timestamp ?? session.completedAt)
        if (
          isWorkingSet(set) &&
          (inclusiveStart ? time >= from : time > from) &&
          time <= to
        )
          addExerciseVolume(volume, e, set.side === "both" ? 1 : 0.5, policy)
      }
    }
  return volume
}
export function calculateSessionVolume(
  session: Pick<PlannedSession, "exercises">,
  index: ExerciseIndex,
  policy: TrainingPolicy
) {
  const volume = emptyVolume()
  for (const p of session.exercises) {
    const e = index.byId.get(p.exerciseId)
    if (e)
      addExerciseVolume(
        volume,
        e,
        p.workingSets.filter((s) => s.setType !== "warmup").length,
        policy
      )
  }
  return volume
}
export function calculateProgramVolume(
  program: TrainingProgram,
  index: ExerciseIndex
) {
  return program.weeks.map((week) => {
    const v = emptyVolume()
    for (const session of week.sessions) {
      const sv = calculateSessionVolume(session, index, program.policy)
      for (const m of MUSCLE_IDS)
        for (const k of ["direct", "indirect", "effective"] as const)
          v[m][k] += sv[m][k]
    }
    return { weekId: week.id, muscles: v }
  })
}
export function calculateProgramFrequency(
  program: TrainingProgram,
  index: ExerciseIndex
) {
  return program.weeks.map((w) => ({
    weekId: w.id,
    muscles: Object.fromEntries(
      MUSCLE_IDS.map((m) => [
        m,
        w.sessions.filter(
          (s) =>
            calculateSessionVolume(s, index, program.policy)[m].effective >=
            program.policy.meaningfulExposureSets
        ).length,
      ])
    ) as Record<MuscleId, number>,
  }))
}

/** Paired muscle-group set units; distinct left/right records each contribute half. */
export function completedWorkingSetUnits(set: CompletedSet): number {
  return isWorkingSet(set) ? (set.side === "both" ? 1 : 0.5) : 0
}
export function completedPairs(sets: CompletedSet[]): number {
  const working = sets.filter(isWorkingSet)
  const both = working.filter((s) => s.side === "both").length
  return (
    both +
    Math.min(
      working.filter((s) => s.side === "left").length,
      working.filter((s) => s.side === "right").length
    )
  )
}
