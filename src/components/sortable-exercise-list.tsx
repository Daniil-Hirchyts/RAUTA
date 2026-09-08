import { DragDropProvider } from "@dnd-kit/react"
import { isSortable, useSortable } from "@dnd-kit/react/sortable"
import { ArrowLeftRight, GripVertical, Trash2 } from "lucide-react"
import { useState, type ReactNode, type Ref } from "react"

import { AnimatedCheck } from "@/components/animated-check"
import { AppGrain } from "@/components/app-grain"
import { AppImage } from "@/components/app-image"
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
  below,
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
  /** Rendered under the row, inside the same item: the set log of a workout
   *  being performed belongs to its exercise, not to a screen of its own. */
  below?: ReactNode
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
      className={`relative isolate mx-(--app-content-inset) flex h-32 w-[calc(100%_-_2_*_var(--app-content-inset))] overflow-hidden rounded-3xl border bg-card shadow-sm shadow-black/10 transition-[border-color,box-shadow,opacity] ${
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
          className="interactive-spring grid w-9 shrink-0 place-items-center border-r border-border bg-card active:bg-muted/80 min-[360px]:w-12"
          onClick={() => onToggleComplete(exercise.id)}
          type="button"
        >
          <AnimatedCheck checked={status === "completed"} className="size-7" />
        </button>
      ) : (
        <div className="grid w-9 shrink-0 place-items-center border-r border-border bg-card text-base font-black text-primary tabular-nums min-[360px]:w-12 min-[360px]:text-lg">
          {String(index + 1).padStart(2, "0")}
        </div>
      )}
      <button
        aria-label={`Open ${exercise.name} demonstration`}
        className="interactive-spring isolate aspect-square h-24 shrink-0 bg-card min-[360px]:h-32"
        disabled={!onOpen}
        onClick={() => onOpen?.(exercise)}
        type="button"
      >
        <AppImage
          alt={`${exercise.name} demonstration`}
          className="h-full w-full object-contain"
          decoding="async"
          draggable={false}
          fetchPriority={index < 3 ? "high" : "low"}
          loading={index < 3 ? "eager" : "lazy"}
          src={exerciseAnimation(exercise)}
          style={{ filter: EXERCISE_ANIMATION_FILTER_LIGHT }}
        />
      </button>
      {/* The picture and the two rails are fixed widths; on a 320px phone they
          would leave the name too little to break a word in, so they give some
          of it back below the width where that starts to bite. */}
      <div className="flex min-w-0 flex-1 flex-col justify-center px-2.5 py-2 min-[360px]:px-3">
        <button
          aria-label={`View ${exercise.name} details`}
          className="min-w-0 text-left"
          disabled={!onOpen}
          onClick={() => onOpen?.(exercise)}
          type="button"
        >
          <p className="line-clamp-3 text-[17px] leading-snug font-semibold capitalize">
            {exercise.name}
          </p>
          <p className="mt-1.5 text-sm font-medium text-muted-foreground">
            {titleCase(exercise.equipment)}
          </p>
        </button>
      </div>
      {reorderable ? (
        <button
          aria-label={`Reorder ${exercise.name}`}
          className="interactive-spring grid w-9 shrink-0 touch-none place-items-center text-primary min-[360px]:w-12"
          data-base-ui-swipe-ignore=""
          data-haptics="off"
          ref={handleRef as Ref<HTMLButtonElement>}
          type="button"
        >
          <GripVertical className="size-6" />
        </button>
      ) : null}
      {isDragSource ? <AppGrain className="app-drag-grain" /> : null}
    </div>
  )

  const swipeable =
    onRemove || onFindAlternative ? (
      <SwipeableRow
        actionInset={16}
        revealWidth={onFindAlternative && onRemove ? 148 : undefined}
        action={
          <div className="flex items-center gap-2">
            {onFindAlternative && (
              <button
                aria-label="Find alternative"
                className="interactive-spring grid size-14 place-items-center rounded-full border border-border bg-card text-primary shadow-lg shadow-black/20 active:bg-card/90 active:text-white"
                onClick={() => {
                  onOpenChange(false)
                  onFindAlternative(exercise)
                }}
                type="button"
              >
                <ArrowLeftRight className="size-5" />
              </button>
            )}
            {onRemove ? (
              <button
                aria-label={`Remove ${exercise.name}`}
                className="interactive-spring grid size-14 place-items-center rounded-full border border-primary bg-card text-primary shadow-lg shadow-black/20"
                onClick={() => onRemove(exercise.id)}
                type="button"
              >
                <Trash2 className="size-5" />
              </button>
            ) : null}
          </div>
        }
        isOpen={isOpen}
        onOpenChange={onOpenChange}
      >
        {row}
      </SwipeableRow>
    ) : (
      row
    )

  return (
    <li className="touch-pan-y" ref={ref as Ref<HTMLLIElement>}>
      {swipeable}
      {below}
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
  renderBelow,
  statusOf,
}: {
  exerciseIds: string[]
  onFindAlternative?: (exercise: ExerciseSummary) => void
  onOpenExercise?: (exercise: ExerciseSummary) => void
  onRemove?: (id: string) => void
  onReorder?: (exerciseIds: string[], movedExerciseId: string) => void
  /** Pass both to add check-off and status to the list of a running workout.
   *  Reordering, removing and swapping stay available either way. */
  onToggleComplete?: (id: string) => void
  /** Extra content for each exercise, kept inside its list item. */
  renderBelow?: (exerciseId: string) => ReactNode
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
        onReorder?.(next, moved)
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
              below={renderBelow?.(id)}
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
