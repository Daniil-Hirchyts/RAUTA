import { Share } from "@capacitor/share"

import { formatDateLong } from "@/lib/date"
import { EXERCISES_BY_ID } from "@/lib/exercises"
import { titleCase } from "@/lib/text"
import type { Workout } from "@/store/use-workouts"

export function workoutShareContent(workout: Workout) {
  const date = formatDateLong(workout.date)
  const exercises = workout.exerciseIds.flatMap((id, index) => {
    const exercise = EXERCISES_BY_ID.get(id)
    if (!exercise) return []
    return [
      `${index + 1}. ${titleCase(exercise.name)}`,
      `   ${titleCase(exercise.equipment)}`,
    ]
  })

  return {
    title: `RAUTA workout — ${date}`,
    text: [date, "", ...exercises, "", "Shared from RAUTA"].join("\n"),
  }
}

export async function shareWorkout(workout: Workout) {
  const content = workoutShareContent(workout)
  const { value: canShare } = await Share.canShare()

  if (canShare) {
    await Share.share({
      ...content,
      dialogTitle: "Share workout",
    })
    return "shared" as const
  }

  await navigator.clipboard.writeText(content.text)
  return "copied" as const
}
