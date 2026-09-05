import type { ExerciseIndex, TrainingProgram } from "./domain/types"
import {
  calculateProgramVolume,
  calculateProgramFrequency,
} from "./analysis/volume"
import { estimateProgramDuration } from "./planning/duration"
export function summarizeProgram(
  program: TrainingProgram,
  index: ExerciseIndex
) {
  const volume = calculateProgramVolume(program, index)
  const frequency = calculateProgramFrequency(program, index)
  const duration = estimateProgramDuration(program, index)
  return {
    id: program.id,
    goal: program.goal,
    split: program.diagnostics.selectedSplit,
    score: program.diagnostics.score.total,
    weeks: program.weeks.map((w, i) => ({
      weekId: w.id,
      phase: w.phase,
      minutes: Math.round(duration[i].seconds / 60),
      sessions: w.sessions.map((s) => ({
        id: s.id,
        scheduledAt: s.scheduledAt,
        minutes: Math.round(s.duration.totalSeconds / 60),
        exercises: s.exercises.map((e) => ({
          id: e.exerciseId,
          name: index.byId.get(e.exerciseId)?.exercise.name,
          sets: e.workingSets.length,
          reps: e.workingSets[0].targetReps,
          rir: e.workingSets[0].targetRir,
          resistance: e.workingSets[0].resistance,
        })),
      })),
      volume: volume[i].muscles,
      frequency: frequency[i].muscles,
    })),
  }
}
