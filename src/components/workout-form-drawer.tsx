import { useState, type FormEvent } from "react"
import { CalendarDays, Check } from "lucide-react"

import { SortableExerciseList } from "@/components/sortable-exercise-list"
import { Button } from "@/components/ui/button"
import { Calendar } from "@/components/ui/calendar"
import { Drawer, DrawerContent, DrawerTitle } from "@/components/ui/drawer"
import { FULL_HEIGHT_DRAWER_STYLE } from "@/components/ui/drawer-style"
import { formatDateLong, toISODate } from "@/lib/date"
import { triggerHaptic } from "@/lib/haptics"
import { useWorkouts, type Workout } from "@/store/use-workouts"

function todayISO() {
  return toISODate(new Date())
}

function todayStart() {
  const today = new Date()
  return new Date(today.getFullYear(), today.getMonth(), today.getDate())
}

function isoToDate(iso: string) {
  const [year, month, day] = iso.split("-").map(Number)
  return new Date(year, month - 1, day)
}

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
  const [date, setDate] = useState(workout?.date ?? todayISO)
  const [datePickerOpen, setDatePickerOpen] = useState(false)
  const [exerciseIds, setExerciseIds] = useState(
    workout?.exerciseIds ?? initialExerciseIds ?? []
  )
  const [submitting, setSubmitting] = useState(false)
  const isEdit = Boolean(workout)
  const canSave = exerciseIds.length > 0 && Boolean(date) && !submitting

  const submit = (event: FormEvent) => {
    event.preventDefault()
    if (!canSave) return
    setSubmitting(true)
    const id = workout
      ? (updateWorkout(workout.id, { date, exerciseIds }), workout.id)
      : createWorkout({ name: "", date, exerciseIds })
    triggerHaptic("success")
    onSaved?.(id)
    onOpenChange(false)
  }

  return (
    <>
      <DrawerTitle className="sr-only">
        {isEdit ? "Edit workout" : "New workout"}
      </DrawerTitle>
      <form
        className="flex min-h-0 flex-1 flex-col px-4 pt-16 pb-6"
        id="workout-form"
        onSubmit={submit}
      >
        {isEdit && (
          <button
            aria-label="Save changes"
            className="interactive-spring absolute top-3 right-3 z-30 grid size-11 place-items-center rounded-full border border-primary bg-card text-primary shadow-lg shadow-black/20 disabled:border-border disabled:bg-muted disabled:text-muted-foreground"
            disabled={!canSave}
            type="submit"
          >
            <Check className="size-5" strokeWidth={3} />
          </button>
        )}

        <button
          aria-controls="workout-date-calendar"
          aria-expanded={datePickerOpen}
          aria-haspopup="dialog"
          className="flex h-14 w-full shrink-0 items-center gap-2.5 rounded-2xl bg-input px-4 text-left text-lg font-bold"
          onClick={() => setDatePickerOpen((value) => !value)}
          type="button"
        >
          <CalendarDays className="size-5 text-muted-foreground" />
          <span className="truncate">{formatDateLong(date)}</span>
        </button>

        {datePickerOpen ? (
          <div
            aria-label="Choose workout date"
            className="mt-4 min-h-0 flex-1 overflow-y-auto rounded-2xl border border-border bg-card p-3"
            id="workout-date-calendar"
            role="dialog"
          >
            <Calendar
              className="w-full overflow-hidden rounded-xl bg-background [--cell-size:clamp(2.5rem,11vw,3rem)]"
              disabled={{ before: todayStart() }}
              mode="single"
              onSelect={(selected) => {
                if (!selected) return
                setDate(toISODate(selected))
                setDatePickerOpen(false)
              }}
              selected={isoToDate(date)}
            />
          </div>
        ) : (
          <div className="-mx-4 mt-4 min-h-0 flex-1 overflow-y-auto pb-3">
            <SortableExerciseList
              exerciseIds={exerciseIds}
              onRemove={(id) =>
                setExerciseIds((ids) =>
                  ids.filter((exerciseId) => exerciseId !== id)
                )
              }
              onReorder={setExerciseIds}
            />
          </div>
        )}

        <DrawerControls>
          <Button
            className="w-full"
            disabled={!canSave}
            form="workout-form"
            size="cta"
            type="submit"
          >
            {isEdit ? "Save workout" : "Create workout"}
          </Button>
        </DrawerControls>
      </form>
    </>
  )
}

export function WorkoutFormDrawer({
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
    <Drawer
      disablePointerDismissal
      onOpenChange={onOpenChange}
      open={open}
      swipeDirection="down"
    >
      <DrawerContent
        className="mx-auto max-w-[430px]"
        style={FULL_HEIGHT_DRAWER_STYLE}
      >
        <WorkoutForm
          initialExerciseIds={initialExerciseIds}
          onOpenChange={onOpenChange}
          onSaved={onSaved}
          workout={workout}
        />
      </DrawerContent>
    </Drawer>
  )
}
