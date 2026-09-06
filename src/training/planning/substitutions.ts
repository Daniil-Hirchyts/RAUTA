import type { ExerciseIndex, ProgramGenerationRequest } from "../domain/types"
import { createExerciseIndex, exclusionReasons } from "../data/exercises"
import { DEFAULT_POLICY } from "../policy"
import { compareIds } from "../numeric"
import { exerciseSimilarity, weightedScore } from "../scoring/scores"

const SUBSTITUTION_SIMILARITY_WEIGHTS = {
  family: 0.2,
  patterns: 0.25,
  directMuscles: 0.25,
  mechanics: 0.1,
  tracking: 0.1,
  laterality: 0.05,
  equipment: 0.05,
} as const

export function findExerciseSubstitutions(
  exerciseId: string,
  request: ProgramGenerationRequest,
  limit = 10,
  context?: { index?: ExerciseIndex }
) {
  const index =
    context?.index ?? createExerciseIndex(request.exercises, request.metadata)
  const source = index.byId.get(exerciseId)
  const policy = request.policy ?? DEFAULT_POLICY
  if (!source) return []
  return [...index.byId.values()]
    .filter(
      (e) =>
        e.exercise.id !== exerciseId &&
        !exclusionReasons(e, request.preferences, policy).length
    )
    .map((e) => ({
      exerciseId: e.exercise.id,
      score: weightedScore(
        {
          similarity: exerciseSimilarity(source, e, SUBSTITUTION_SIMILARITY_WEIGHTS),
          tracking: Number(e.metadata.tracking === source.metadata.tracking),
          skill: Number(e.metadata.skill === source.metadata.skill),
          quality: e.metadata.classificationConfidence,
          preference: request.preferences.preferredExerciseIds?.includes(
            e.exercise.id
          )
            ? 1
            : request.preferences.dislikedExerciseIds?.includes(e.exercise.id)
              ? 0
              : 0.5,
        },
        { similarity: 4, tracking: 1, skill: 0.5, quality: 1, preference: 0.5 }
      ),
    }))
    .sort(
      (a, b) =>
        b.score.total - a.score.total || compareIds(a.exerciseId, b.exerciseId)
    )
    .slice(0, Math.max(0, Math.min(100, limit)))
}
