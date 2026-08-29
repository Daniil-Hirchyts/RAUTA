import { CalendarDays, ChevronLeft, ChevronRight } from "lucide-react"

import { Button } from "@/components/ui/button"
import { formatDateShort } from "@/lib/date"
import { useWorkouts, type Workout } from "@/store/use-workouts"

export function WorkoutsPage({
  onBack,
  onSelect,
}: {
  onBack: () => void
  onSelect: (workout: Workout) => void
}) {
  const workouts = useWorkouts((state) => state.workouts)
  const sorted = [...workouts].sort((left, right) =>
    left.date.localeCompare(right.date)
  )

  return (
    <>
      <header className="shrink-0 border-b border-white/[0.05] bg-background/80 px-5 pt-4 pb-4 backdrop-blur-xl">
        <div className="flex items-center gap-3">
          <Button
            aria-label="Back"
            className="shrink-0 rounded-full"
            onClick={onBack}
            size="icon"
            variant="secondary"
          >
            <ChevronLeft />
          </Button>
          <h1 className="bg-gradient-to-r from-foreground to-foreground/75 bg-clip-text text-[26px] font-black tracking-[-0.03em] text-transparent">
            My workouts
          </h1>
        </div>
      </header>

      <div className="flex min-h-0 flex-1 flex-col overflow-y-auto px-5 py-5">
        {sorted.length === 0 ? (
          <div className="flex flex-1 flex-col items-center justify-center gap-3 text-center">
            <CalendarDays className="size-7 text-muted-foreground/60" />
            <p className="max-w-[24rem] text-base text-muted-foreground">
              No workouts yet. Select exercises on the Exercises step and tap
              "Add to workout".
            </p>
          </div>
        ) : (
          <ul className="space-y-3">
            {sorted.map((workout) => (
              <li key={workout.id}>
                <button
                  className="flex w-full items-center justify-between gap-3 rounded-2xl border border-border bg-card/80 p-4 text-left backdrop-blur-sm transition-transform duration-150 active:scale-[0.98]"
                  onClick={() => onSelect(workout)}
                  type="button"
                >
                  <div className="min-w-0">
                    <p className="text-lg font-bold tracking-[-0.01em]">
                      {formatDateShort(workout.date)}
                    </p>
                    <p className="mt-0.5 text-sm font-medium text-muted-foreground">
                      {workout.exerciseIds.length} exercise
                      {workout.exerciseIds.length === 1 ? "" : "s"}
                    </p>
                  </div>
                  <ChevronRight className="size-5 shrink-0 text-muted-foreground" />
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </>
  )
}
