import {
  memo,
  useCallback,
  useEffect,
  useRef,
  useState,
  type CSSProperties,
  type FormEvent,
  type PointerEvent as ReactPointerEvent,
} from "react"
import { CalendarDays, Check, GripVertical, Trash2 } from "lucide-react"

import { DeleteWorkoutConfirmation } from "@/components/delete-workout-confirmation"
import { SwipeableRow } from "@/components/swipeable-row"
import { Button } from "@/components/ui/button"
import { Calendar } from "@/components/ui/calendar"
import { Drawer, DrawerContent, DrawerTitle } from "@/components/ui/drawer"
import { formatDateLong, toISODate } from "@/lib/date"
import { EXERCISES_BY_ID } from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { titleCase } from "@/lib/text"
import {
  EXERCISE_ANIMATION_FILTER,
  EXERCISE_ANIMATION_FILTER_LIGHT,
  exerciseAnimation,
} from "@/lib/visuals"
import { useWorkouts, type Workout } from "@/store/use-workouts"
import type { ExerciseSummary } from "@/types"

function todayISO() {
  return toISODate(new Date())
}

function isoToDate(iso: string) {
  const [year, month, day] = iso.split("-").map(Number)
  return new Date(year, month - 1, day)
}

// The other drawers keep the default 96px top clearance (comfortably more
// than any notch/Dynamic Island inset), but this one goes full-height, so
// it has to reserve the safe area itself or the close/save buttons render
// underneath the status bar.
const FULL_HEIGHT_DRAWER_STYLE = {
  "--drawer-content-max-height":
    "calc(var(--app-viewport-height) - 0.5rem - env(safe-area-inset-top))",
  "--drawer-height":
    "calc(var(--app-viewport-height) - 0.5rem - env(safe-area-inset-top))",
} as CSSProperties

// Rows are pinned to a fixed height so drag-reordering can position each one
// with a plain translateY(index * stride) — no layout measuring needed, and
// the browser animates the transform for free whenever an index changes.
const ROW_HEIGHT = 96
const ROW_GAP = 12
const ROW_STRIDE = ROW_HEIGHT + ROW_GAP

// Drag-reorder needs every row addressable by index, so this list (unlike
// the exercises grid) isn't paginated — but nothing stops it from getting
// large too (bulk-select many exercises, then "Add to workout"). Past this
// size, drop the per-row SVG sharpen filter — the same crash-vector cost
// the grid was fixed for — while keeping it for the common small-list case.
const LIGHT_FILTER_THRESHOLD = 24

type DragState = {
  id: string
  pointerId: number
  startIndex: number
  currentIndex: number
  startClientY: number
  // The list's length at drag-start — reordering never changes it, so
  // this is a stable stand-in for reading exerciseIds.length, which would
  // otherwise force moveDrag to close over reactive state (see below).
  length: number
}

type ExerciseRowProps = {
  exercise: ExerciseSummary
  id: string
  imageFilter: string
  index: number
  isDragging: boolean
  isOpen: boolean
  onDragEnd: (event: ReactPointerEvent<HTMLButtonElement>) => void
  onDragMove: (event: ReactPointerEvent<HTMLButtonElement>) => void
  onDragStart: (
    id: string,
    index: number,
    event: ReactPointerEvent<HTMLButtonElement>
  ) => void
  onOpenChange: (id: string, open: boolean) => void
  onRemove: (id: string) => void
  translateY: number
}

// Memoized so a reorder drag — which updates translateY on every
// pointermove — only re-renders the one row actually being dragged,
// instead of reconciling the whole (potentially long) list on every move.
// This only pays off because every prop below is either a primitive (value
// equality is exactly what we want) or a stable callback ref — see the
// useCallback-wrapped handlers in WorkoutForm.
const WorkoutExerciseRow = memo(function WorkoutExerciseRow({
  exercise,
  id,
  imageFilter,
  index,
  isDragging,
  isOpen,
  onDragEnd,
  onDragMove,
  onDragStart,
  onOpenChange,
  onRemove,
  translateY,
}: ExerciseRowProps) {
  return (
    <li
      className="absolute inset-x-0 top-0 will-change-transform"
      style={{
        transform: `translateY(${translateY}px)`,
        transition: isDragging
          ? "none"
          : "transform 220ms var(--ease-smooth-out)",
        zIndex: isDragging ? 10 : 1,
      }}
    >
      <SwipeableRow
        actionInset={16}
        action={
          <button
            aria-label={`Remove ${exercise.name}`}
            className="text-destructive-foreground grid size-14 shrink-0 place-items-center rounded-full bg-destructive shadow-lg shadow-black/20 transition-transform duration-150 active:scale-90"
            data-haptics="off"
            onClick={() => {
              triggerHaptic("warning")
              onRemove(id)
            }}
            type="button"
          >
            <Trash2 className="size-5" />
          </button>
        }
        isOpen={isOpen}
        onOpenChange={(open) => onOpenChange(id, open)}
      >
        <div
          className={`workout-exercise-card mx-4 flex h-24 w-[calc(100%-2rem)] overflow-hidden rounded-[20px] border border-border bg-card shadow-sm shadow-black/10 ${isDragging ? "is-dragging" : ""}`}
        >
          <div className="isolate aspect-square w-24 shrink-0 bg-[#111113]">
            <img
              alt={`${exercise.name} demonstration`}
              className="h-full w-full object-contain mix-blend-screen"
              decoding="async"
              draggable={false}
              loading="lazy"
              src={exerciseAnimation(exercise)}
              style={{ filter: imageFilter }}
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
              className="grid size-9 shrink-0 touch-none place-items-center text-muted-foreground transition-colors active:text-foreground"
              data-base-ui-swipe-ignore=""
              data-haptics="off"
              onPointerCancel={onDragEnd}
              onPointerDown={(event) => onDragStart(id, index, event)}
              onPointerMove={onDragMove}
              onPointerUp={onDragEnd}
              type="button"
            >
              <GripVertical className="size-4" />
            </button>
          </div>
        </div>
      </SwipeableRow>
    </li>
  )
})

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
  const imageFilter =
    exerciseIds.length > LIGHT_FILTER_THRESHOLD
      ? EXERCISE_ANIMATION_FILTER_LIGHT
      : EXERCISE_ANIMATION_FILTER
  const [openRowId, setOpenRowId] = useState<string | null>(null)
  const [dragId, setDragId] = useState<string | null>(null)
  const [dragStartIndex, setDragStartIndex] = useState(0)
  const [dragDeltaY, setDragDeltaY] = useState(0)
  const dragRef = useRef<DragState | null>(null)
  // The drawer stays mounted and tappable through its ~450ms close
  // animation, so a fast double-tap on Create/Save can re-enter submit()
  // before onOpenChange(false) actually removes it — this blocks that.
  const [submitting, setSubmitting] = useState(false)

  const isEdit = Boolean(workout)
  const canSave = exerciseIds.length > 0 && Boolean(date) && !submitting

  // Every handler below is useCallback-wrapped (mostly with empty deps —
  // reading only stable setters and dragRef, never exerciseIds directly)
  // so their identity never changes across renders. That's what lets
  // WorkoutExerciseRow's memo() actually skip re-rendering rows a drag
  // gesture doesn't touch, instead of every row seeing "new callback prop"
  // on every single pointermove.

  const removeExercise = useCallback((id: string) => {
    setExerciseIds((ids) => ids.filter((exerciseId) => exerciseId !== id))
  }, [])

  const handleRowOpenChange = useCallback((id: string, open: boolean) => {
    setOpenRowId(open ? id : null)
  }, [])

  const startDrag = useCallback(
    (
      id: string,
      index: number,
      event: ReactPointerEvent<HTMLButtonElement>
    ) => {
      event.stopPropagation()
      try {
        event.currentTarget.setPointerCapture?.(event.pointerId)
      } catch {
        // A pointer some environments consider inactive can reject capture
        // — the drag still works fine via normal move/up bubbling.
      }
      dragRef.current = {
        id,
        pointerId: event.pointerId,
        startIndex: index,
        currentIndex: index,
        startClientY: event.clientY,
        length: exerciseIds.length,
      }
      setDragId(id)
      setDragStartIndex(index)
      setDragDeltaY(0)
      triggerHaptic("selection")
    },
    [exerciseIds.length]
  )

  const moveDrag = useCallback(
    (event: ReactPointerEvent<HTMLButtonElement> | globalThis.PointerEvent) => {
      const drag = dragRef.current
      if (!drag || event.pointerId !== drag.pointerId) return
      // stopPropagation matters on every event in the gesture, not just
      // pointerdown — each pointermove is its own dispatch, and without this
      // it keeps bubbling to SwipeableRow's own pointer handlers on the
      // ancestor row, which can read it as a horizontal swipe and reveal the
      // delete action *while* the row is being dragged to reorder.
      event.stopPropagation()
      event.preventDefault()
      const deltaY = event.clientY - drag.startClientY
      setDragDeltaY(deltaY)

      const targetIndex = Math.min(
        drag.length - 1,
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
    },
    []
  )

  const finishDrag = useCallback((pointerId?: number) => {
    const drag = dragRef.current
    if (!drag || (pointerId !== undefined && pointerId !== drag.pointerId)) {
      return
    }
    dragRef.current = null
    setDragId(null)
    setDragDeltaY(0)
  }, [])

  const endDrag = useCallback(
    (event: ReactPointerEvent<HTMLButtonElement>) => {
      event.stopPropagation()
      finishDrag(event.pointerId)
    },
    [finishDrag]
  )

  // Pointer capture is not fully reliable in iOS Safari when a finger moves
  // beyond the small drag handle. Window-level fallbacks keep the row moving
  // and guarantee cleanup even if WebKit silently drops capture.
  useEffect(() => {
    if (!dragId) return

    const handleMove = (event: globalThis.PointerEvent) => moveDrag(event)
    const handleEnd = (event: globalThis.PointerEvent) =>
      finishDrag(event.pointerId)
    const handleBlur = () => finishDrag()

    window.addEventListener("pointermove", handleMove, { passive: false })
    window.addEventListener("pointerup", handleEnd)
    window.addEventListener("pointercancel", handleEnd)
    window.addEventListener("blur", handleBlur)

    return () => {
      window.removeEventListener("pointermove", handleMove)
      window.removeEventListener("pointerup", handleEnd)
      window.removeEventListener("pointercancel", handleEnd)
      window.removeEventListener("blur", handleBlur)
    }
  }, [dragId, finishDrag, moveDrag])

  const submit = (event: FormEvent) => {
    event.preventDefault()
    if (!canSave) return
    setSubmitting(true)

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
        className="flex min-h-0 flex-1 flex-col px-4 pt-16"
        onSubmit={submit}
      >
        {isEdit && (
          <button
            aria-label="Save changes"
            className="absolute top-3 right-3 z-30 grid size-11 place-items-center rounded-full border border-primary bg-primary text-primary-foreground shadow-lg shadow-black/20 transition-colors duration-250 active:bg-[color-mix(in_oklch,var(--primary),black_10%)] active:scale-90 disabled:border-border disabled:bg-muted disabled:text-muted-foreground"
            data-haptics="off"
            disabled={!canSave}
            type="submit"
          >
            <Check className="size-5" strokeWidth={3} />
          </button>
        )}

        <div className="shrink-0">
          <button
            aria-controls="workout-date-calendar"
            aria-expanded={datePickerOpen}
            aria-haspopup="dialog"
            className="flex h-14 w-full items-center gap-2.5 rounded-2xl border border-transparent bg-input px-4 text-left text-lg font-bold"
            data-base-ui-swipe-ignore=""
            data-haptics="off"
            onClick={() => setDatePickerOpen((isOpen) => !isOpen)}
            type="button"
          >
            <CalendarDays className="size-5 shrink-0 text-muted-foreground" />
            <span className="min-w-0 truncate">{formatDateLong(date)}</span>
          </button>
        </div>

        {datePickerOpen ? (
          <div
            aria-label="Choose workout date"
            className="mt-4 min-h-0 flex-1 overflow-y-auto rounded-[20px] border border-border bg-card p-3"
            data-base-ui-swipe-ignore=""
            id="workout-date-calendar"
            role="dialog"
          >
            <Calendar
              className="w-full overflow-hidden rounded-[16px] bg-background [--cell-size:clamp(2.5rem,11vw,3rem)]"
              classNames={{
                root: "w-full",
              }}
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
          /* -mx-4 cancels the form's own px-4 for this element specifically,
              so it spans the drawer's true edge-to-edge width — otherwise
              overflow-y-auto forces overflow-x to clip too, and nothing
              (the swipe-reveal, the drag lift) could ever reach past the
              form's padding no matter how it was positioned. */
          <div className="-mx-4 mt-4 min-h-0 flex-1 overflow-y-auto pb-3">
            <ul
              className="relative"
              style={{
                height: Math.max(
                  0,
                  exerciseIds.length * ROW_STRIDE - ROW_GAP
                ),
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
                  <WorkoutExerciseRow
                    exercise={exercise}
                    id={id}
                    imageFilter={imageFilter}
                    index={index}
                    isDragging={isDragging}
                    isOpen={openRowId === id}
                    key={id}
                    onDragEnd={endDrag}
                    onDragMove={moveDrag}
                    onDragStart={startDrag}
                    onOpenChange={handleRowOpenChange}
                    onRemove={removeExercise}
                    translateY={translateY}
                  />
                )
              })}
            </ul>
          </div>
        )}

        <div className="bottom-controls-scrim -mx-4 shrink-0 px-4 pt-4 pb-[calc(1rem+env(safe-area-inset-bottom))] [--bottom-controls-color:var(--popover)]">
          {!isEdit && (
            <Button
              className="h-12 w-full rounded-2xl text-base font-semibold"
              disabled={!canSave}
              type="submit"
            >
              Create workout
            </Button>
          )}

          {isEdit && workout && (
            <Button
              className="h-12 w-full rounded-2xl text-base"
              onClick={() => setDeleteOpen(true)}
              type="button"
              variant="destructive"
            >
              Delete workout
            </Button>
          )}
        </div>
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
