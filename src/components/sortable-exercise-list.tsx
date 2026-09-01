import { DragDropProvider } from "@dnd-kit/react"
import { isSortable, useSortable } from "@dnd-kit/react/sortable"
import { ArrowLeftRight, GripVertical, Trash2 } from "lucide-react"
import { useState, type Ref } from "react"

import { AnimatedCheck } from "@/components/animated-check"
import { SwipeableRow } from "@/components/swipeable-row"
import type { ExerciseStatus } from "@/lib/active-workout"
import { EXERCISES_BY_ID } from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { titleCase } from "@/lib/text"
import {
  EXERCISE_ANIMATION_FILTER_LIGHT,
  exerciseAnimation,
} from "@/lib/visuals"
import type { ExerciseSummary } from "@/types"

function SortableExerciseRow({
  exercise,
  index,
  isOpen,
  onFindAlternative,
  onOpen,
  onOpenChange,
  onRemove,
  onToggleComplete,
  reorderable,
  status,
}: {
  exercise: ExerciseSummary
  index: number
  isOpen: boolean
  onFindAlternative?: (exercise: ExerciseSummary) => void
  onOpen?: (exercise: ExerciseSummary) => void
  onOpenChange: (open: boolean) => void
  onRemove?: (id: string) => void
  /** Present only while a workout is being performed. */
  onToggleComplete?: (id: string) => void
  reorderable: boolean
  status?: ExerciseStatus
}) {
  const { handleRef, isDragSource, ref } = useSortable({
    disabled: !reorderable,
    id: exercise.id,
    index,
    transition: { duration: 220, easing: "cubic-bezier(0.22, 1, 0.36, 1)" },
  })

  const row = (
    <div
      className={`mx-4 flex h-32 w-[calc(100%-2rem)] overflow-hidden rounded-[22px] border bg-card shadow-sm shadow-black/10 transition-[border-color,box-shadow,opacity] ${
        isDragSource
          ? "border-primary/70 opacity-90 shadow-xl shadow-black/30"
          : status === "active"
            ? "border-primary/60"
            : status === "completed"
              ? "border-border opacity-55"
              : "border-border"
      }`}
      data-status={status}
    >
      {onToggleComplete ? (
        <button
          aria-label={
            status === "completed"
              ? `Mark ${exercise.name} as not done`
              : `Mark ${exercise.name} as done`
          }
          aria-pressed={status === "completed"}
          className="grid w-12 shrink-0 place-items-center border-r border-border bg-muted/35 transition-colors active:bg-muted"
          onClick={() => onToggleComplete(exercise.id)}
          type="button"
        >
          <AnimatedCheck checked={status === "completed"} className="size-7" />
        </button>
      ) : (
        <div className="grid w-12 shrink-0 place-items-center border-r border-border bg-muted/35 text-base font-black text-primary tabular-nums">
          {String(index + 1).padStart(2, "0")}
        </div>
      )}
      <button
        aria-label={`Open ${exercise.name} demonstration`}
        className="isolate aspect-square h-32 shrink-0 bg-[#111113] active:bg-muted/60"
        disabled={!onOpen}
        onClick={() => onOpen?.(exercise)}
        type="button"
      >
        <img
          alt={`${exercise.name} demonstration`}
          className="h-full w-full object-contain mix-blend-screen"
          decoding="async"
          draggable={false}
          loading="lazy"
          src={exerciseAnimation(exercise)}
          style={{ filter: EXERCISE_ANIMATION_FILTER_LIGHT }}
        />
      </button>
      <div className="flex min-w-0 flex-1 flex-col justify-center px-3 py-2">
        <button
          aria-label={`View ${exercise.name} details`}
          className="min-w-0 text-left"
          disabled={!onOpen}
          onClick={() => onOpen?.(exercise)}
          type="button"
        >
          <p className="line-clamp-3 text-base leading-snug font-semibold capitalize">
            {exercise.name}
          </p>
          <p className="mt-1.5 text-sm text-muted-foreground">
            {titleCase(exercise.equipment)}
          </p>
        </button>
      </div>
      {reorderable ? (
        <button
          aria-label={`Reorder ${exercise.name}`}
          className="grid w-12 shrink-0 touch-none place-items-center text-muted-foreground transition-colors active:text-foreground"
          data-base-ui-swipe-ignore=""
          data-haptics="off"
          ref={handleRef as Ref<HTMLButtonElement>}
          type="button"
        >
          <GripVertical className="size-6" />
        </button>
      ) : null}
    </div>
  )

  return (
    <li className="touch-pan-y" ref={ref as Ref<HTMLLIElement>}>
      {onRemove ? (
        <SwipeableRow
          actionInset={16}
          revealWidth={onFindAlternative ? 148 : undefined}
          action={
            <div className="flex items-center gap-2">
              {onFindAlternative && (
                <button
                  aria-label="Find alternative"
                  className="grid size-14 place-items-center rounded-full bg-secondary text-secondary-foreground shadow-lg shadow-black/20 active:scale-90"
                  onClick={() => {
                    onOpenChange(false)
                    onFindAlternative(exercise)
                  }}
                  type="button"
                >
                  <ArrowLeftRight className="size-5" />
                </button>
              )}
              <button
                aria-label={`Remove ${exercise.name}`}
                className="text-destructive-foreground grid size-14 place-items-center rounded-full bg-destructive shadow-lg shadow-black/20 active:scale-90"
                onClick={() => onRemove(exercise.id)}
                type="button"
              >
                <Trash2 className="size-5" />
              </button>
            </div>
          }
          isOpen={isOpen}
          onOpenChange={onOpenChange}
        >
          {row}
        </SwipeableRow>
      ) : (
        row
      )}
    </li>
  )
}

export function SortableExerciseList({
  exerciseIds,
  onFindAlternative,
  onOpenExercise,
  onRemove,
  onReorder,
  onToggleComplete,
  statusOf,
}: {
  exerciseIds: string[]
  onFindAlternative?: (exercise: ExerciseSummary) => void
  onOpenExercise?: (exercise: ExerciseSummary) => void
  onRemove?: (id: string) => void
  onReorder?: (exerciseIds: string[]) => void
  /** Pass both to add check-off and status to the list of a running workout.
   *  Reordering, removing and swapping stay available either way. */
  onToggleComplete?: (id: string) => void
  statusOf?: (id: string) => ExerciseStatus
}) {
  const [openRowId, setOpenRowId] = useState<string | null>(null)
  const reorderable = Boolean(onReorder)

  return (
    <DragDropProvider
      onDragEnd={(event) => {
        if (event.canceled) return
        const { source } = event.operation
        if (!isSortable(source)) return
        const { initialIndex, index } = source
        if (initialIndex === index) return

        const next = [...exerciseIds]
        const [moved] = next.splice(initialIndex, 1)
        next.splice(index, 0, moved)
        onReorder?.(next)
        triggerHaptic("success")
      }}
      onDragStart={() => triggerHaptic("selection")}
    >
      <ul className="space-y-3">
        {exerciseIds.map((id, index) => {
          const exercise = EXERCISES_BY_ID.get(id)
          if (!exercise) return null
          return (
            <SortableExerciseRow
              exercise={exercise}
              index={index}
              isOpen={openRowId === id}
              key={id}
              onFindAlternative={onFindAlternative}
              onOpen={onOpenExercise}
              onOpenChange={(open) => setOpenRowId(open ? id : null)}
              onRemove={onRemove}
              onToggleComplete={onToggleComplete}
              reorderable={reorderable}
              status={statusOf?.(id)}
            />
          )
        })}
      </ul>
    </DragDropProvider>
  )
}
