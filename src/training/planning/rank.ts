import type {
  ExerciseIndex,
  MuscleId,
  PlannedSession,
  ProgramGenerationRequest,
} from "../domain/types"
import { exclusionReasons } from "../data/exercises"
import { compareIds } from "../numeric"
import { createExerciseScorer } from "../scoring/scores"
import { preparation } from "./generate"
import { estimateSessionDuration } from "./duration"
import { prescribeExercise } from "./prescribe"

/** The planner's candidate scoring, also used when a person builds a session. */
export function rankExerciseCandidates(
  request: ProgramGenerationRequest,
  options: {
    index?: ExerciseIndex
    focus?: readonly MuscleId[]
    selectedExerciseIds?: readonly string[]
  } = {}
) {
  const input = preparation(request, undefined, options.index)
  const selected = new Set(options.selectedExerciseIds ?? [])
  const session: PlannedSession = {
    id: "selection",
    scheduledAt: request.now,
    focus: options.focus?.length
      ? [...options.focus]
      : input.targets.filter((t) => t.preferred > 0).map((t) => t.muscleId),
    exercises: [...selected].flatMap((id) => {
      const exercise = input.index.byId.get(id)
      return exercise
        ? [
            prescribeExercise(
              exercise,
              3,
              "selection",
              { total: 0, contributions: [] },
              input
            ),
          ]
        : []
    }),
    duration: estimateSessionDuration(
      { exercises: [] },
      input.index,
      input.policy
    ),
  }
  const score = createExerciseScorer(
    session,
    {
      id: "selection",
      start: request.schedule.weekStart,
      phase: "base",
      targets: input.targets,
      sessions: [session],
    },
    input
  )
  return [...input.index.byId.values()]
    .filter(
      (e) =>
        !selected.has(e.exercise.id) &&
        !exclusionReasons(e, request.preferences, input.policy).length
    )
    .map((e) => ({ exerciseId: e.exercise.id, score: score(e) }))
    .sort(
      (a, b) =>
        b.score.total - a.score.total || compareIds(a.exerciseId, b.exerciseId)
    )
}
