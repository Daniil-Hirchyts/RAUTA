import type {
  ExerciseIndex,
  PlannedSession,
  SessionDurationEstimate,
  TrainingPolicy,
  TrainingProgram,
} from "../domain/types"
export function estimateSessionDuration(
  session: Pick<PlannedSession, "exercises">,
  index: ExerciseIndex,
  policy: TrainingPolicy
): SessionDurationEstimate {
  let specificWarmupSeconds = 0
  let workingSetSeconds = 0
  let restSeconds = 0
  let transitionSeconds = 0
  for (const p of session.exercises) {
    const m = index.byId.get(p.exerciseId)?.metadata
    const sides =
      m?.laterality === "unilateral" || m?.laterality === "alternating" ? 2 : 1
    specificWarmupSeconds += p.warmupSets.reduce(
      (n, s) =>
        n +
        s.targetReps.max * policy.secondsPerRep * sides +
        policy.warmupRestSeconds,
      0
    )
    workingSetSeconds += p.workingSets.reduce(
      (n, s) => n + s.targetReps.max * policy.secondsPerRep * sides,
      0
    )
    restSeconds += Math.max(0, p.workingSets.length - 1) * p.restSeconds
    transitionSeconds += m?.setupSeconds ?? 60
  }
  transitionSeconds +=
    Math.max(0, session.exercises.length - 1) * policy.transitionSeconds
  const generalWarmupSeconds = session.exercises.length
    ? policy.generalWarmupSeconds
    : 0
  return {
    generalWarmupSeconds,
    specificWarmupSeconds,
    workingSetSeconds,
    restSeconds,
    transitionSeconds,
    totalSeconds:
      generalWarmupSeconds +
      specificWarmupSeconds +
      workingSetSeconds +
      restSeconds +
      transitionSeconds,
    confidence: "low",
  }
}
export function estimateProgramDuration(
  program: TrainingProgram,
  index: ExerciseIndex
) {
  return program.weeks.map((w) => ({
    weekId: w.id,
    seconds: w.sessions.reduce(
      (n, s) =>
        n + estimateSessionDuration(s, index, program.policy).totalSeconds,
      0
    ),
  }))
}
