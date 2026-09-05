import type { ProgramGenerationRequest } from "../domain/types"
import { createExerciseIndex, exclusionReasons } from "../data/exercises"
import { DEFAULT_POLICY } from "../policy"
import { compareIds } from "../numeric"
import { exerciseSimilarity, weightedScore } from "../scoring/scores"
export function findExerciseSubstitutions(
  exerciseId: string,
  request: ProgramGenerationRequest,
  limit = 10
) {
  const index = createExerciseIndex(request.exercises, request.metadata)
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
          similarity: exerciseSimilarity(source, e, policy.similarityWeights),
          tracking: Number(e.metadata.tracking === source.metadata.tracking),
          quality: e.metadata.classificationConfidence,
          preference: request.preferences.preferredExerciseIds?.includes(
            e.exercise.id
          )
            ? 1
            : request.preferences.dislikedExerciseIds?.includes(e.exercise.id)
              ? 0
              : 0.5,
        },
        { similarity: 4, tracking: 1, quality: 1, preference: 0.5 }
      ),
    }))
    .sort(
      (a, b) =>
        b.score.total - a.score.total || compareIds(a.exerciseId, b.exerciseId)
    )
    .slice(0, Math.max(0, Math.min(100, limit)))
}
