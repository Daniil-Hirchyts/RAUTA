import {
  useRef,
  useState,
  type CSSProperties,
  type FormEvent,
  type PointerEvent,
} from "react"
import { CalendarDays, Check, GripVertical, Trash2 } from "lucide-react"

import { DeleteWorkoutConfirmation } from "@/components/delete-workout-confirmation"
import { SwipeableRow } from "@/components/swipeable-row"
import { Button } from "@/components/ui/button"
import { Calendar } from "@/components/ui/calendar"
import { Drawer, DrawerContent, DrawerTitle } from "@/components/ui/drawer"
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover"
import { formatDateLong, toISODate } from "@/lib/date"
import { EXERCISES_BY_ID } from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { titleCase } from "@/lib/text"
import { cn } from "@/lib/utils"
import { EXERCISE_ANIMATION_FILTER, exerciseAnimation } from "@/lib/visuals"
import { useWorkouts, type Workout } from "@/store/use-workouts"

function todayISO() {
  return toISODate(new Date())
}

function isoToDate(iso: string) {
  const [year, month, day] = iso.split("-").map(Number)
  return new Date(year, month - 1, day)
}

const FULL_HEIGHT_DRAWER_STYLE = {
  "--drawer-content-max-height": "calc(100dvh - 1rem)",
  "--drawer-height": "calc(100dvh - 1rem)",
} as CSSProperties

// Rows are pinned to a fixed height so drag-reordering can position each one
// with a plain translateY(index * stride) — no layout measuring needed, and
// the browser animates the transform for free whenever an index changes.
const ROW_HEIGHT = 96
const ROW_GAP = 12
const ROW_STRIDE = ROW_HEIGHT + ROW_GAP

type DragState = {
  id: string
  startIndex: number
  currentIndex: number
  startClientY: number
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
  const deleteWorkout = useWorkouts((state) => state.deleteWorkout)

  const [date, setDate] = useState(workout?.date ?? todayISO)
  const [datePickerOpen, setDatePickerOpen] = useState(false)
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [exerciseIds, setExerciseIds] = useState<string[]>(
    workout?.exerciseIds ?? initialExerciseIds ?? []
  )
  const [openRowId, setOpenRowId] = useState<string | null>(null)
  const [dragId, setDragId] = useState<string | null>(null)
  const [dragStartIndex, setDragStartIndex] = useState(0)
  const [dragDeltaY, setDragDeltaY] = useState(0)
  const dragRef = useRef<DragState | null>(null)

  const isEdit = Boolean(workout)
  const canSave = exerciseIds.length > 0 && Boolean(date)

  const removeExercise = (id: string) =>
    setExerciseIds((ids) => ids.filter((exerciseId) => exerciseId !== id))

  const startDrag =
    (id: string, index: number) => (event: PointerEvent<HTMLButtonElement>) => {
      event.stopPropagation()
      try {
        event.currentTarget.setPointerCapture?.(event.pointerId)
      } catch {
        // A pointer some environments consider inactive can reject capture
        // — the drag still works fine via normal move/up bubbling.
      }
      dragRef.current = {
        id,
        startIndex: index,
        currentIndex: index,
        startClientY: event.clientY,
      }
      setDragId(id)
      setDragStartIndex(index)
      setDragDeltaY(0)
      triggerHaptic("selection")
    }

  const moveDrag = (event: PointerEvent<HTMLButtonElement>) => {
    const drag = dragRef.current
    if (!drag) return
    event.preventDefault()
    const deltaY = event.clientY - drag.startClientY
    setDragDeltaY(deltaY)

    const targetIndex = Math.min(
      exerciseIds.length - 1,
      Math.max(0, Math.round(drag.startIndex + deltaY / ROW_STRIDE))
    )
    // Capture the source index now — setExerciseIds's updater runs later
    // (deferred, and twice under StrictMode), by which point the
    // `drag.currentIndex = targetIndex` mutation below would already have
    // landed if the updater read the ref directly instead of this const.
    const sourceIndex = drag.currentIndex
    if (targetIndex !== sourceIndex) {
      setExerciseIds((ids) => {
        const next = [...ids]
        const [moved] = next.splice(sourceIndex, 1)
        next.splice(targetIndex, 0, moved)
        return next
      })
      drag.currentIndex = targetIndex
      triggerHaptic("selection")
    }
  }

  const endDrag = () => {
    dragRef.current = null
    setDragId(null)
    setDragDeltaY(0)
  }

  const submit = (event: FormEvent) => {
    event.preventDefault()
    if (!canSave) return

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
      <DrawerTitle className="sr-only">
        {isEdit ? "Edit workout" : "New workout"}
      </DrawerTitle>
      <form
        className="flex min-h-0 flex-1 flex-col px-4 pt-16 pb-[calc(1rem+env(safe-area-inset-bottom))]"
        onSubmit={submit}
      >
        {isEdit && (
          <button
            aria-label="Save changes"
            className="absolute top-3 right-3 z-30 grid size-11 place-items-center rounded-full border border-primary bg-primary text-primary-foreground shadow-lg shadow-black/20 transition-colors duration-250 hover:bg-[color-mix(in_oklch,var(--primary),black_10%)] disabled:border-border disabled:bg-muted disabled:text-muted-foreground"
            disabled={!canSave}
            type="submit"
          >
            <Check className="size-5" strokeWidth={3} />
          </button>
        )}

        <Popover onOpenChange={setDatePickerOpen} open={datePickerOpen}>
          <PopoverTrigger
            render={
              <button
                className="flex h-14 w-full shrink-0 items-center gap-2.5 rounded-2xl border border-transparent bg-input px-4 text-left text-lg font-bold"
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

        {/* -mx-4 cancels the form's own px-4 for this element specifically,
            so it spans the drawer's true edge-to-edge width — otherwise
            overflow-y-auto forces overflow-x to clip too, and nothing
            (the swipe-reveal, the drag lift) could ever reach past the
            form's padding no matter how it was positioned. */}
        <div className="-mx-4 mt-4 min-h-0 flex-1 overflow-y-auto pb-3">
          <ul
            className="relative"
            style={{
              height: Math.max(0, exerciseIds.length * ROW_STRIDE - ROW_GAP),
            }}
          >
            {exerciseIds.map((id, index) => {
              const exercise = EXERCISES_BY_ID.get(id)
              if (!exercise) return null
              const isDragging = dragId === id
              const translateY = isDragging
                ? dragStartIndex * ROW_STRIDE + dragDeltaY
                : index * ROW_STRIDE

              return (
                <li
                  className={cn(
                    "absolute inset-x-0 top-0 rounded-[20px] transition-shadow duration-200",
                    isDragging && "shadow-lg shadow-black/30"
                  )}
                  key={id}
                  style={{
                    transform: `translateY(${translateY}px)`,
                    transition: isDragging
                      ? "none"
                      : "transform 220ms var(--ease-smooth-out)",
                    zIndex: isDragging ? 10 : 1,
                  }}
                >
                  <SwipeableRow
                    action={
                      <button
                        aria-label={`Remove ${exercise.name}`}
                        className="grid size-14 shrink-0 place-items-center rounded-full bg-destructive text-destructive-foreground shadow-lg shadow-black/20 transition-transform duration-150 active:scale-90"
                        onClick={() => {
                          triggerHaptic("warning")
                          removeExercise(id)
                        }}
                        type="button"
                      >
                        <Trash2 className="size-5" />
                      </button>
                    }
                    isOpen={openRowId === id}
                    onOpenChange={(open) => setOpenRowId(open ? id : null)}
                  >
                    <div className="workout-exercise-card ml-4 flex h-24 w-[calc(100%-1rem)] overflow-hidden rounded-[20px] border border-border bg-card shadow-sm shadow-black/10">
                      <div className="isolate aspect-square w-24 shrink-0 bg-[#111113]">
                        <img
                          alt={`${exercise.name} demonstration`}
                          className="h-full w-full object-contain mix-blend-screen"
                          decoding="async"
                          draggable={false}
                          loading="lazy"
                          src={exerciseAnimation(exercise)}
                          style={{ filter: EXERCISE_ANIMATION_FILTER }}
                        />
                      </div>
                      <div className="flex min-w-0 flex-1 items-center gap-2 py-3 pr-2 pl-3">
                        <div className="min-w-0 flex-1">
                          <p className="line-clamp-2 text-sm leading-snug font-semibold capitalize">
                            {exercise.name}
                          </p>
                          <p className="mt-1 text-xs text-muted-foreground">
                            {titleCase(exercise.equipment)}
                          </p>
                        </div>
                        <button
                          aria-label={`Reorder ${exercise.name}`}
                          className="grid size-9 shrink-0 touch-none place-items-center rounded-full bg-secondary text-muted-foreground active:bg-muted active:text-foreground"
                          onPointerCancel={endDrag}
                          onPointerDown={startDrag(id, index)}
                          onPointerMove={moveDrag}
                          onPointerUp={endDrag}
                          type="button"
                        >
                          <GripVertical className="size-4" />
                        </button>
                      </div>
                    </div>
                  </SwipeableRow>
                </li>
              )
            })}
          </ul>
        </div>

        {!isEdit && (
          <Button
            className="h-12 w-full shrink-0 rounded-2xl text-base font-semibold"
            disabled={!canSave}
            type="submit"
          >
            Create workout
          </Button>
        )}

        {isEdit && workout && (
          <Button
            className="h-12 w-full shrink-0 rounded-2xl text-base"
            onClick={() => setDeleteOpen(true)}
            type="button"
            variant="destructive"
          >
            Delete workout
          </Button>
        )}
      </form>

      {workout && (
        <DeleteWorkoutConfirmation
          onConfirm={() => {
            deleteWorkout(workout.id)
            onOpenChange(false)
          }}
          onOpenChange={setDeleteOpen}
          open={deleteOpen}
        />
      )}
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
    <Drawer onOpenChange={onOpenChange} open={open} swipeDirection="down">
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
