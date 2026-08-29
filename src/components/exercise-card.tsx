import { Badge } from "@/components/ui/badge"
import { MUSCLE_LABELS } from "@/lib/muscles"
import { titleCase } from "@/lib/text"
import type { ExerciseSummary, MuscleId } from "@/types"

function orderedMuscles(exercise: ExerciseSummary) {
  const muscles: MuscleId[] = []
  if (exercise.primaryMuscle) muscles.push(exercise.primaryMuscle)
  exercise.muscles.forEach((muscle) => {
    if (!muscles.includes(muscle)) muscles.push(muscle)
  })
  return muscles
}

export function ExerciseCard({ exercise }: { exercise: ExerciseSummary }) {
  const muscles = orderedMuscles(exercise)
  const visibleMuscles = muscles.slice(0, 3)
  const remaining = muscles.length - visibleMuscles.length

  return (
    <article className="rounded-2xl border border-border bg-card px-4 py-3.5 shadow-sm shadow-black/10">
      <h3 className="text-[15px] font-medium tracking-[-0.015em] capitalize">
        {exercise.name}
      </h3>
      <div className="mt-2.5 flex flex-wrap gap-1.5">
        <Badge className="bg-primary/12 text-primary" variant="secondary">
          {titleCase(exercise.equipment)}
        </Badge>
        {visibleMuscles.map((muscle) => (
          <Badge key={muscle} variant="outline">
            {MUSCLE_LABELS[muscle]}
          </Badge>
        ))}
        {remaining > 0 && <Badge variant="outline">+{remaining}</Badge>}
      </div>
    </article>
  )
}
