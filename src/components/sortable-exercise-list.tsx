import { DragDropProvider } from "@dnd-kit/react"
import { isSortable, useSortable } from "@dnd-kit/react/sortable"
import { GripVertical, Trash2 } from "lucide-react"
import { useState, type Ref } from "react"

import { SwipeableRow } from "@/components/swipeable-row"
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
  onOpen,
  onOpenChange,
  onRemove,
}: {
  exercise: ExerciseSummary
  index: number
  isOpen: boolean
  onOpen?: (exercise: ExerciseSummary) => void
  onOpenChange: (open: boolean) => void
  onRemove?: (id: string) => void
}) {
  const { handleRef, isDragSource, ref } = useSortable({
    id: exercise.id,
    index,
    transition: { duration: 220, easing: "cubic-bezier(0.22, 1, 0.36, 1)" },
  })

  const row = (
    <div
      className={`mx-4 flex h-32 w-[calc(100%-2rem)] overflow-hidden rounded-[22px] border bg-card shadow-sm shadow-black/10 transition-[border-color,box-shadow,opacity] ${
        isDragSource
          ? "border-primary/70 opacity-90 shadow-xl shadow-black/30"
          : "border-border"
      }`}
    >
      <div className="grid w-12 shrink-0 place-items-center border-r border-border bg-muted/35 text-base font-black text-primary tabular-nums">
        {String(index + 1).padStart(2, "0")}
      </div>
      <button
        aria-label={`View ${exercise.name} details`}
        className="flex min-w-0 flex-1 items-center text-left active:bg-muted/60"
        disabled={!onOpen}
        onClick={() => onOpen?.(exercise)}
        type="button"
      >
        <div className="isolate aspect-square h-32 shrink-0 bg-[#111113]">
          <img
            alt={`${exercise.name} demonstration`}
            className="h-full w-full object-contain mix-blend-screen"
            decoding="async"
            draggable={false}
            loading="lazy"
            src={exerciseAnimation(exercise)}
            style={{ filter: EXERCISE_ANIMATION_FILTER_LIGHT }}
          />
        </div>
        <div className="min-w-0 flex-1 px-3 py-3">
          <p className="line-clamp-3 text-base leading-snug font-semibold capitalize">
            {exercise.name}
          </p>
          <p className="mt-1.5 text-sm text-muted-foreground">
            {titleCase(exercise.equipment)}
          </p>
        </div>
      </button>
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
    </div>
  )

  return (
    <li className="touch-pan-y" ref={ref as Ref<HTMLLIElement>}>
      {onRemove ? (
        <SwipeableRow
          actionInset={16}
          action={
            <button
              aria-label={`Remove ${exercise.name}`}
              className="text-destructive-foreground grid size-14 place-items-center rounded-full bg-destructive shadow-lg shadow-black/20 active:scale-90"
              onClick={() => onRemove(exercise.id)}
              type="button"
            >
              <Trash2 className="size-5" />
            </button>
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
  onOpenExercise,
  onRemove,
  onReorder,
}: {
  exerciseIds: string[]
  onOpenExercise?: (exercise: ExerciseSummary) => void
  onRemove?: (id: string) => void
  onReorder: (exerciseIds: string[]) => void
}) {
  const [openRowId, setOpenRowId] = useState<string | null>(null)

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
        onReorder(next)
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
              onOpen={onOpenExercise}
              onOpenChange={(open) => setOpenRowId(open ? id : null)}
              onRemove={onRemove}
            />
          )
        })}
      </ul>
    </DragDropProvider>
  )
}
