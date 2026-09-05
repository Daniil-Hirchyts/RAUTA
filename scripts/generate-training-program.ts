import exercises from "../src/data/exercises.generated.json"
import type { ExerciseSummary, ProgramGenerationRequest } from "../src/training"
import {
  createExerciseIndex,
  generateTrainingProgram,
  summarizeProgram,
  validateTrainingProgram,
} from "../src/training"
export const exampleRequest: ProgramGenerationRequest = {
  profile: {
    age: 32,
    trainingExperience: "beginner",
    health: { status: "healthy" },
  },
  preferences: {
    goal: "general_fitness",
    availableEquipment: [
      "body weight",
      "dumbbell",
      "barbell",
      "cable",
      "leverage machine",
      "bench",
      "rack",
      "pull-up bar",
      "step",
    ],
    maxSessionDurationMinutes: 45,
  },
  schedule: {
    weekStart: "2026-09-07T00:00:00.000Z",
    days: [0, 2, 4],
    durationWeeks: 4,
  },
  history: { sessions: [], coverage: "unknown" },
  now: "2026-09-05T12:00:00.000Z",
  exercises: exercises as ExerciseSummary[],
}
if (process.argv[1]?.endsWith("generate-training-program.ts")) {
  const result = generateTrainingProgram(exampleRequest)
  console.log(
    JSON.stringify(
      "program" in result
        ? {
            status: result.status,
            summary: summarizeProgram(
              result.program,
              createExerciseIndex(exampleRequest.exercises)
            ),
            validation: validateTrainingProgram(
              result.program,
              exampleRequest,
              createExerciseIndex(exampleRequest.exercises)
            ),
            diagnostics: result.program.diagnostics,
          }
        : result,
      null,
      2
    )
  )
}
