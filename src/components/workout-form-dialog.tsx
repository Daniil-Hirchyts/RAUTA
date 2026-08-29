import { useState, type FormEvent } from "react"
import { CalendarDays, Trash2, X } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Calendar } from "@/components/ui/calendar"
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogTitle,
} from "@/components/ui/dialog"
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover"
import { EXERCISES_BY_ID } from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { formatDateLong, toISODate } from "@/lib/date"
import { useWorkouts, type Workout } from "@/store/use-workouts"

function todayISO() {
  return toISODate(new Date())
}

function isoToDate(iso: string) {
  const [year, month, day] = iso.split("-").map(Number)
  return new Date(year, month - 1, day)
}

/**
 * The parent gives this component a fresh React `key` every time a new
 * workout (or a new exercise selection) is opened, so local form state
 * always starts clean without needing an effect to re-sync it from props.
 *
 * There's no separate "name" field — the date a workout is scheduled for
 * is its title, both here and everywhere a workout is listed.
 */
function WorkoutForm({
  initialExerciseIds,
  onOpenChange,
  onSaved,
  workout,
}: {
  initialExerciseIds?: string[]
  onOpenChange: (open: boolean) => void
  onSaved?: (workoutId: string) => void
  workout?: Workout | null
}) {
  const createWorkout = useWorkouts((state) => state.createWorkout)
  const updateWorkout = useWorkouts((state) => state.updateWorkout)
  const deleteWorkout = useWorkouts((state) => state.deleteWorkout)

  const [date, setDate] = useState(workout?.date ?? todayISO)
  const [datePickerOpen, setDatePickerOpen] = useState(false)
  const [exerciseIds, setExerciseIds] = useState<string[]>(
    workout?.exerciseIds ?? initialExerciseIds ?? []
  )

  const isEdit = Boolean(workout)

  const removeExercise = (id: string) =>
    setExerciseIds((ids) => ids.filter((exerciseId) => exerciseId !== id))

  const submit = (event: FormEvent) => {
    event.preventDefault()
    if (exerciseIds.length === 0 || !date) return

    if (workout) {
      updateWorkout(workout.id, { date, exerciseIds })
      onSaved?.(workout.id)
    } else {
      const id = createWorkout({ name: "", date, exerciseIds })
      onSaved?.(id)
    }
    triggerHaptic("success")
    onOpenChange(false)
  }

  return (
    <>
      <DialogTitle className="sr-only">
        {isEdit ? "Edit workout" : "New workout"}
      </DialogTitle>
      <form className="space-y-5" onSubmit={submit}>
        <Popover onOpenChange={setDatePickerOpen} open={datePickerOpen}>
          <PopoverTrigger
            render={
              <button
                className="flex h-14 w-full items-center gap-2.5 rounded-2xl border border-transparent bg-input/50 px-4 text-left text-lg font-bold"
                type="button"
              />
            }
          >
            <CalendarDays className="size-5 shrink-0 text-muted-foreground" />
            <span className="min-w-0 truncate">{formatDateLong(date)}</span>
          </PopoverTrigger>
          <PopoverContent align="start" className="w-auto p-2">
            <Calendar
              mode="single"
              onSelect={(selected) => {
                if (!selected) return
                setDate(toISODate(selected))
                setDatePickerOpen(false)
              }}
              selected={isoToDate(date)}
            />
          </PopoverContent>
        </Popover>

        {exerciseIds.length > 0 && (
          <ul className="max-h-48 space-y-2 overflow-y-auto">
            {exerciseIds.map((id) => {
              const exercise = EXERCISES_BY_ID.get(id)
              if (!exercise) return null
              return (
                <li
                  className="flex items-center gap-2 rounded-2xl bg-secondary/60 py-2 pr-2 pl-3.5 backdrop-blur-sm"
                  key={id}
                >
                  <span className="min-w-0 flex-1 truncate text-sm font-medium capitalize">
                    {exercise.name}
                  </span>
                  <button
                    aria-label={`Remove ${exercise.name}`}
                    className="grid size-8 shrink-0 place-items-center rounded-full text-muted-foreground transition-transform duration-150 hover:bg-muted hover:text-foreground active:scale-90"
                    onClick={() => removeExercise(id)}
                    type="button"
                  >
                    <X className="size-4" />
                  </button>
                </li>
              )
            })}
          </ul>
        )}

        <DialogFooter className="flex-col gap-2.5 sm:flex-col">
          <Button
            className="h-12 w-full rounded-2xl text-base font-semibold"
            disabled={exerciseIds.length === 0 || !date}
            type="submit"
          >
            {isEdit ? "Save changes" : "Create workout"}
          </Button>
          {isEdit && workout && (
            <Button
              className="h-12 w-full rounded-2xl text-base"
              onClick={() => {
                triggerHaptic("warning")
                deleteWorkout(workout.id)
                onOpenChange(false)
              }}
              type="button"
              variant="destructive"
            >
              <Trash2 data-icon="inline-start" />
              Delete workout
            </Button>
          )}
        </DialogFooter>
      </form>
    </>
  )
}

export function WorkoutFormDialog({
  initialExerciseIds,
  onOpenChange,
  onSaved,
  open,
  workout,
}: {
  initialExerciseIds?: string[]
  onOpenChange: (open: boolean) => void
  onSaved?: (workoutId: string) => void
  open: boolean
  workout?: Workout | null
}) {
  return (
    <Dialog onOpenChange={onOpenChange} open={open}>
      <DialogContent>
        <WorkoutForm
          initialExerciseIds={initialExerciseIds}
          onOpenChange={onOpenChange}
          onSaved={onSaved}
          workout={workout}
        />
      </DialogContent>
    </Dialog>
  )
}
