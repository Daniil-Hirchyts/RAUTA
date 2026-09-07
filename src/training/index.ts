export type * from "./domain/types"
export {
  PLANNER_SUPPORTED_TRACKING,
  plannerSupportsExercise,
  plannerSupportsTracking,
} from "./domain/capabilities"
export { DEFAULT_POLICY, ENGINE_VERSION } from "./policy"
export {
  createExerciseIndex,
  inferExerciseMetadata,
  resolveExerciseMetadata,
  validateExerciseData,
  validateMetadata,
} from "./data/exercises"
export {
  generateTrainingProgram,
  evaluateTrainingProgram,
} from "./planning/generate"
export { analyzeTrainingState } from "./analysis/state"
export {
  calculateProgramVolume,
  calculateProgramFrequency,
  calculateHistoryVolume,
  effectiveSetCredit,
} from "./analysis/volume"
export {
  epleyEstimator,
  brzyckiEstimator,
  observedRir,
} from "./analysis/strength"
export {
  estimateSessionDuration,
  estimateProgramDuration,
} from "./planning/duration"
export {
  recommendProgression,
  doubleProgression,
  repProgression,
  roundLoad,
} from "./progression/progression"
export { validateTrainingProgram } from "./validation/program"
export { validateGenerationRequest } from "./validation/input"
export { findExerciseSubstitutions } from "./planning/substitutions"
export { SPLIT_MUSCLE_GROUPS } from "./planning/optimizer"
export { adaptTrainingProgram } from "./planning/adapt"
export type { AdaptationRequest } from "./planning/adapt"
export { summarizeProgram } from "./summary"
export { adaptLegacyWorkout } from "./data/legacy"
