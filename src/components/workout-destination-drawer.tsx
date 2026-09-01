import { CalendarDays, ChevronRight, Plus } from "lucide-react"

import { Drawer, DrawerContent, DrawerTitle } from "@/components/ui/drawer"
import { formatDateShort } from "@/lib/date"
import { triggerHaptic } from "@/lib/haptics"
import { isPastWorkout } from "@/lib/workout-stats"
import { useWorkouts } from "@/store/use-workouts"

export function WorkoutDestinationDrawer({
  exerciseIds,
  onAddToExisting,
  onCreateNew,
  onOpenChange,
  open,
  preferredWorkoutId,
}: {
  exerciseIds: string[]
  onAddToExisting: (workoutId: string) => void
  onCreateNew: () => void
  onOpenChange: (open: boolean) => void
  open: boolean
  preferredWorkoutId?: string | null
}) {
  const workouts = useWorkouts((state) => state.workouts)
  const sorted = workouts
    .filter((workout) => !isPastWorkout(workout))
    .sort((left, right) => {
      if (left.id === preferredWorkoutId) return -1
      if (right.id === preferredWorkoutId) return 1
      return right.date.localeCompare(left.date)
    })

  return (
    <Drawer onOpenChange={onOpenChange} open={open} swipeDirection="down">
      <DrawerContent className="mx-auto max-w-[430px] [--drawer-inset:0px]">
        <div className="px-5 pt-16 pb-[calc(1.25rem+env(safe-area-inset-bottom))]">
          <DrawerTitle className="text-2xl font-black tracking-[-0.025em]">
            Add {exerciseIds.length} exercise
            {exerciseIds.length === 1 ? "" : "s"}
          </DrawerTitle>
          <p className="mt-1 text-sm text-muted-foreground">
            Start fresh or add them to a workout you already use.
          </p>

          <button
            className="interactive-spring mt-5 flex w-full items-center gap-3 rounded-[20px] border border-primary/45 bg-[color-mix(in_oklch,var(--card),var(--primary)_10%)] p-4 text-left active:bg-[color-mix(in_oklch,var(--card),var(--primary)_24%)] active:border-primary"
            onClick={() => {
              triggerHaptic("medium")
              onCreateNew()
            }}
            type="button"
          >
            <span className="grid size-11 shrink-0 place-items-center rounded-2xl bg-primary text-primary-foreground">
              <Plus className="size-5" />
            </span>
            <span className="min-w-0 flex-1">
              <span className="block text-base font-bold">New workout</span>
              <span className="mt-0.5 block text-sm text-muted-foreground">
                Pick a date and review the order
              </span>
            </span>
            <ChevronRight className="size-5 text-muted-foreground" />
          </button>

          {sorted.length > 0 && (
            <div className="mt-5">
              <p className="mb-2 px-1 text-xs font-bold tracking-[0.13em] text-muted-foreground uppercase">
                Existing workouts
              </p>
              <div className="max-h-[42vh] space-y-2 overflow-y-auto">
                {sorted.map((workout) => (
                  <button
                    className={`interactive-spring flex w-full items-center gap-3 rounded-[18px] border p-3.5 text-left active:bg-muted/80 ${
                      workout.id === preferredWorkoutId
                        ? "border-primary/50 bg-card"
                        : "border-border bg-card"
                    }`}
                    key={workout.id}
                    onClick={() => {
                      triggerHaptic("success")
                      onAddToExisting(workout.id)
                    }}
                    type="button"
                  >
                    <span className="grid size-10 shrink-0 place-items-center rounded-2xl bg-muted text-muted-foreground">
                      <CalendarDays className="size-5" />
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="block font-bold">
                        {formatDateShort(workout.date)}
                      </span>
                      <span className="text-sm text-muted-foreground">
                        {workout.exerciseIds.length} exercise
                        {workout.exerciseIds.length === 1 ? "" : "s"}
                        {workout.id === preferredWorkoutId ? " · Current" : ""}
                      </span>
                    </span>
                    <ChevronRight className="size-5 text-muted-foreground" />
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>
      </DrawerContent>
    </Drawer>
  )
}
