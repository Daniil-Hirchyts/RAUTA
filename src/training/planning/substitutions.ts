import type { ExerciseIndex, ProgramGenerationRequest } from "../domain/types"
import { createExerciseIndex, exclusionReasons } from "../data/exercises"
import { DEFAULT_POLICY } from "../policy"
import { compareIds } from "../numeric"
import { exerciseSimilarity, weightedScore } from "../scoring/scores"
import { rankExerciseCandidates } from "./rank"

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
  context?: { index?: ExerciseIndex; selectedExerciseIds?: readonly string[] }
) {
  const index =
    context?.index ?? createExerciseIndex(request.exercises, request.metadata)
  const source = index.byId.get(exerciseId)
  const policy = request.policy ?? DEFAULT_POLICY
  if (!source) return []
  const planningScores = new Map(
    rankExerciseCandidates(request, {
      index,
      focus: source.metadata.setRoles
        .filter((r) => r.role === "direct")
        .map((r) => r.muscleId),
      selectedExerciseIds: context?.selectedExerciseIds?.filter(
        (id) => id !== exerciseId
      ),
    }).map((item) => [item.exerciseId, item.score.total])
  )
  return [...index.byId.values()]
    .filter(
      (e) =>
        e.exercise.id !== exerciseId &&
        planningScores.has(e.exercise.id) &&
        e.metadata.setRoles.some(
          (role) =>
            role.role === "direct" &&
            source.metadata.setRoles.some(
              (original) =>
                original.role === "direct" &&
                original.muscleId === role.muscleId
            )
        ) &&
        !exclusionReasons(e, request.preferences, policy).length
    )
    .map((e) => ({
      exerciseId: e.exercise.id,
      score: weightedScore(
        {
          planning: planningScores.get(e.exercise.id) ?? 0,
          similarity: exerciseSimilarity(
            source,
            e,
            SUBSTITUTION_SIMILARITY_WEIGHTS
          ),
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
        {
          similarity: 4,
          planning: 3,
          tracking: 1,
          skill: 0.5,
          quality: 1,
          preference: 0.5,
        }
      ),
    }))
    .sort(
      (a, b) =>
        b.score.total - a.score.total || compareIds(a.exerciseId, b.exerciseId)
    )
    .slice(0, Math.max(0, Math.min(100, limit)))
}
