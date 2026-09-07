import { useMemo, useState, type FormEvent } from "react"
import { CalendarDays, ChevronLeft, ChevronRight, Plus } from "lucide-react"

import {
  AppControls,
  AppHeaderButton,
  AppScreen,
  AppShellHeader,
  AppSurface,
} from "@/components/app-shell"
import { AppImage } from "@/components/app-image"
import { AppMorph } from "@/components/app-morph"
import { LikeButton } from "@/components/like-button"
import { SortableExerciseList } from "@/components/sortable-exercise-list"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { WorkoutDatePicker } from "@/components/workout-date-picker"
import { formatDateLong, formatDateShort, toISODate } from "@/lib/date"
import { EXERCISES_BY_ID, findExerciseAlternatives } from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { titleCase } from "@/lib/text"
import {
  EXERCISE_ANIMATION_FILTER,
  EXERCISE_ANIMATION_FILTER_LIGHT,
  exerciseAnimation,
  exerciseMorphId,
} from "@/lib/visuals"
import { isPastWorkout } from "@/lib/workout-stats"
import { useFavorites } from "@/store/use-favorites"
import { useFilters } from "@/store/use-filters"
import { useWorkouts, type Workout } from "@/store/use-workouts"
import type { ExerciseSummary } from "@/types"

function todayISO() {
  return toISODate(new Date())
}

function PageBack({ label, onBack }: { label: string; onBack: () => void }) {
  return (
    <AppHeaderButton aria-label={label} onClick={onBack}>
      <ChevronLeft />
    </AppHeaderButton>
  )
}

export function ExerciseDetailPage({
  exercise,
  onBack,
}: {
  exercise: ExerciseSummary
  onBack: () => void
}) {
  const isFavorite = useFavorites((state) =>
    state.favoriteIds.includes(exercise.id)
  )
  const toggleFavorite = useFavorites((state) => state.toggleFavorite)

  return (
    <AppScreen>
      <AppSurface>
        <AppShellHeader
          left={<PageBack label="Back" onBack={onBack} />}
          right={
            <LikeButton
              aria-label={
                isFavorite
                  ? `Remove ${exercise.name} from favorites`
                  : `Add ${exercise.name} to favorites`
              }
              className="interactive-spring grid size-11 place-items-center rounded-full border border-border bg-card text-primary active:bg-card/90"
              data-haptics="off"
              iconClassName="size-5"
              liked={isFavorite}
              onClick={() => {
                triggerHaptic("selection")
                toggleFavorite(exercise.id)
              }}
            />
          }
          title={exercise.name}
          titleClassName="capitalize"
          titleMultiline
        />

        <div className="app-scroll-region min-h-0 flex-1 overflow-y-auto px-(--app-content-inset) pt-5 pb-6">
          <AppMorph
            className="isolate aspect-square w-full overflow-hidden bg-popover"
            morphId={exerciseMorphId(exercise.id)}
            radius="var(--app-card-radius)"
          >
            <AppImage
              alt={`${exercise.name} demonstration`}
              className="h-full w-full object-contain"
              decoding="async"
              draggable={false}
              fetchPriority="high"
              loading="eager"
              src={exerciseAnimation(exercise)}
              style={{ filter: EXERCISE_ANIMATION_FILTER }}
            />
          </AppMorph>
          {exercise.instructions.length > 0 ? (
            <ol className="mt-4 list-decimal space-y-2.5 pl-5 text-base text-muted-foreground marker:font-semibold marker:text-primary">
              {exercise.instructions.map((step, index) => (
                <li className="pl-1 leading-relaxed" key={index}>
                  {step}
                </li>
              ))}
            </ol>
          ) : null}
        </div>
      </AppSurface>
    </AppScreen>
  )
}

export function WorkoutDestinationPage({
  exerciseIds,
  onAddToExisting,
  onBack,
  onCreateNew,
  preferredWorkoutId,
}: {
  exerciseIds: string[]
  onAddToExisting: (workoutId: string) => void
  onBack: () => void
  onCreateNew: () => void
  preferredWorkoutId?: string | null
}) {
  const workouts = useWorkouts((state) => state.workouts)
  const sorted = useMemo(
    () =>
      [...workouts]
        .filter((workout) => !isPastWorkout(workout))
        .sort((left, right) => {
          if (left.id === preferredWorkoutId) return -1
          if (right.id === preferredWorkoutId) return 1
          return right.date.localeCompare(left.date)
        }),
    [preferredWorkoutId, workouts]
  )

  return (
    <AppScreen>
      <AppSurface>
        <AppShellHeader
          left={<PageBack label="Back to exercises" onBack={onBack} />}
          title={`Add ${exerciseIds.length} exercise${exerciseIds.length === 1 ? "" : "s"}`}
        />
        <div className="app-scroll-region min-h-0 flex-1 overflow-y-auto px-(--app-content-inset) pt-5 pb-6">
          <p className="text-sm text-muted-foreground">
            Start fresh or add them to a workout you already use.
          </p>
          <button
            className="interactive-spring mt-5 flex w-full items-center gap-3 rounded-2xl border border-primary/45 bg-[color-mix(in_oklch,var(--card),var(--primary)_10%)] p-4 text-left active:border-primary"
            onClick={onCreateNew}
            type="button"
          >
            <span className="grid size-11 shrink-0 place-items-center rounded-full bg-primary-gradient text-primary-foreground shadow-xs">
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

          {sorted.length > 0 ? (
            <div className="mt-5">
              <p className="mb-2 px-1 text-xs font-bold tracking-[0.13em] text-muted-foreground uppercase">
                Existing workouts
              </p>
              <div className="space-y-2">
                {sorted.map((workout) => (
                  <button
                    className={`interactive-spring flex w-full items-center gap-3 rounded-2xl border p-3.5 text-left active:bg-muted/80 ${
                      workout.id === preferredWorkoutId
                        ? "border-primary/50 bg-card"
                        : "border-border bg-card"
                    }`}
                    key={workout.id}
                    onClick={() => onAddToExisting(workout.id)}
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
          ) : null}
        </div>
      </AppSurface>
    </AppScreen>
  )
}

export function WorkoutFormPage({
  initialExerciseIds,
  onBack,
  onSaved,
  workout,
}: {
  initialExerciseIds?: string[]
  onBack: () => void
  onSaved: (workoutId: string) => void
  workout?: Workout | null
}) {
  const createWorkout = useWorkouts((state) => state.createWorkout)
  const updateWorkout = useWorkouts((state) => state.updateWorkout)
  const [date, setDate] = useState(workout?.date ?? todayISO)
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
    onSaved(id)
  }

  return (
    <AppScreen bottomControls>
      <AppSurface>
        <AppShellHeader
          left={<PageBack label="Back" onBack={onBack} />}
          title={isEdit ? "Edit workout" : "New workout"}
        />
        <form
          className="app-scroll-region flex min-h-0 flex-1 flex-col overflow-y-auto px-(--app-content-inset) pt-5 pb-6"
          id="workout-form"
          onSubmit={submit}
        >
          <WorkoutDatePicker
            className="flex h-14 w-full shrink-0 items-center gap-2.5 rounded-2xl bg-input px-4 text-left text-lg font-bold"
            date={date}
            onSelect={setDate}
          >
            <CalendarDays className="size-5 text-muted-foreground" />
            <span className="truncate">{formatDateLong(date)}</span>
          </WorkoutDatePicker>

          <div className="relative -mx-(--app-content-inset) mt-2 min-h-0 flex-1">
            <div className="app-scroll-content h-full overflow-y-auto pt-2 pb-3">
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
          </div>
        </form>
      </AppSurface>
      <AppControls transitionKey={`workout-form:${canSave}`}>
        <Button
          className="w-full"
          disabled={!canSave}
          form="workout-form"
          size="cta"
          type="submit"
        >
          {isEdit ? "Save workout" : "Create workout"}
        </Button>
      </AppControls>
    </AppScreen>
  )
}

export function EquipmentPresetPage({
  onBack,
  onSaved,
}: {
  onBack: () => void
  onSaved: () => void
}) {
  const [name, setName] = useState("")
  const selectedEquipment = useFilters((state) => state.selectedEquipment)
  const savePreset = useFilters((state) => state.saveEquipmentPreset)
  const canSave = Boolean(name.trim()) && selectedEquipment.length > 0

  const submit = (event: FormEvent) => {
    event.preventDefault()
    if (!canSave) return
    savePreset(name)
    triggerHaptic("success")
    onSaved()
  }

  return (
    <AppScreen bottomControls>
      <AppSurface>
        <AppShellHeader
          left={<PageBack label="Back to equipment" onBack={onBack} />}
          title="Save preset"
        />
        <form
          className="app-scroll-region min-h-0 flex-1 overflow-y-auto px-(--app-content-inset) pt-5 pb-6"
          id="equipment-preset-form"
          onSubmit={submit}
        >
          <p className="mb-4 text-sm text-muted-foreground">
            Save the current {selectedEquipment.length}-item equipment
            selection.
          </p>
          <Input
            aria-label="Preset name"
            autoFocus
            maxLength={30}
            onChange={(event) => setName(event.target.value)}
            placeholder="Preset name"
            value={name}
          />
          <div className="mt-5 flex flex-wrap gap-2">
            {selectedEquipment.map((equipment) => (
              <span
                className="rounded-full border border-border bg-card px-3 py-2 text-sm font-semibold text-muted-foreground"
                key={equipment}
              >
                {titleCase(equipment)}
              </span>
            ))}
          </div>
        </form>
      </AppSurface>
      <AppControls transitionKey={`preset:${canSave}`}>
        <Button
          className="w-full"
          disabled={!canSave}
          form="equipment-preset-form"
          size="cta"
          type="submit"
        >
          Save preset
        </Button>
      </AppControls>
    </AppScreen>
  )
}

export function ExerciseAlternativesPage({
  alternativeExerciseIds,
  excludedExerciseIds,
  exercise,
  onBack,
  onSwap,
}: {
  alternativeExerciseIds?: readonly string[]
  excludedExerciseIds: string[]
  exercise: ExerciseSummary
  onBack: () => void
  onSwap: (replacement: ExerciseSummary) => string | null | void
}) {
  const [equipment, setEquipment] = useState<string | null>(null)
  const [swapIssue, setSwapIssue] = useState<string | null>(null)
  const alternatives = useMemo(() => {
    if (alternativeExerciseIds === undefined)
      return findExerciseAlternatives(exercise, excludedExerciseIds)

    const excluded = new Set([exercise.id, ...excludedExerciseIds])
    return alternativeExerciseIds.flatMap((exerciseId) => {
      const alternative = EXERCISES_BY_ID.get(exerciseId)
      return alternative && !excluded.has(exerciseId) ? [alternative] : []
    })
  }, [alternativeExerciseIds, excludedExerciseIds, exercise])
  const equipmentOptions = useMemo(
    () => [...new Set(alternatives.map((item) => item.equipment))],
    [alternatives]
  )
  const visibleAlternatives = equipment
    ? alternatives.filter((item) => item.equipment === equipment)
    : alternatives

  return (
    <AppScreen>
      <AppSurface>
        <AppShellHeader
          left={<PageBack label="Back to workout" onBack={onBack} />}
          title="Find alternative"
        />
        <div className="app-scroll-region min-h-0 flex-1 overflow-y-auto px-(--app-content-inset) pt-5 pb-6">
          <div className="flex items-center gap-3 rounded-2xl border border-border bg-card p-3">
            <div className="isolate size-16 shrink-0 overflow-hidden rounded-2xl bg-card">
              <AppImage
                alt=""
                className="h-full w-full object-contain"
                draggable={false}
                fetchPriority="high"
                loading="eager"
                src={exerciseAnimation(exercise)}
                style={{ filter: EXERCISE_ANIMATION_FILTER_LIGHT }}
              />
            </div>
            <div className="min-w-0 flex-1">
              <p className="line-clamp-2 font-semibold capitalize">
                {exercise.name}
              </p>
              <p className="mt-1 text-xs text-muted-foreground">
                {alternativeExerciseIds === undefined
                  ? "Same muscles, different equipment."
                  : "Fits this workout and your current equipment."}
              </p>
            </div>
          </div>

          {swapIssue ? (
            <p
              className="mt-4 rounded-2xl border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm font-semibold text-foreground"
              role="alert"
            >
              {swapIssue}
            </p>
          ) : null}

          {equipmentOptions.length > 1 ? (
            <div className="-mx-(--app-content-inset) mt-4 flex gap-2 overflow-x-auto px-(--app-content-inset) pb-1">
              {[null, ...equipmentOptions].map((option) => (
                <button
                  aria-pressed={equipment === option}
                  className={`shrink-0 rounded-full border px-3.5 py-2 text-sm font-semibold ${
                    equipment === option
                      ? "border-primary/80 bg-primary-gradient text-primary-foreground shadow-xs"
                      : "border-border bg-card text-muted-foreground"
                  }`}
                  key={option ?? "all"}
                  onClick={() => setEquipment(option)}
                  type="button"
                >
                  {option ? titleCase(option) : "All available"}
                </button>
              ))}
            </div>
          ) : null}

          <div className="mt-4 space-y-2.5">
            {visibleAlternatives.length === 0 ? (
              <p className="rounded-2xl border border-border bg-card px-5 py-8 text-center text-sm leading-relaxed text-muted-foreground">
                {alternativeExerciseIds === undefined
                  ? "Nothing else works the same muscles on the equipment you have. Pick a different filter above, or keep the exercise you are on."
                  : "No other exercise fits this planned slot with your current equipment. Keep the current exercise."}
              </p>
            ) : (
              visibleAlternatives.map((alternative, alternativeIndex) => (
                <button
                  aria-label={`Swap to ${alternative.name}`}
                  className="interactive-spring flex w-full items-center gap-3 overflow-hidden rounded-2xl border border-border bg-card p-2.5 text-left active:bg-card/90"
                  key={alternative.id}
                  onClick={() => {
                    const issue = onSwap(alternative)
                    if (typeof issue === "string" && issue) {
                      setSwapIssue(issue)
                      triggerHaptic("warning")
                    } else {
                      setSwapIssue(null)
                    }
                  }}
                  type="button"
                >
                  <span className="isolate size-20 shrink-0 overflow-hidden rounded-lg bg-card">
                    <AppImage
                      alt=""
                      className="h-full w-full object-contain"
                      draggable={false}
                      fetchPriority={alternativeIndex < 3 ? "high" : "low"}
                      loading={alternativeIndex < 3 ? "eager" : "lazy"}
                      src={exerciseAnimation(alternative)}
                      style={{ filter: EXERCISE_ANIMATION_FILTER_LIGHT }}
                    />
                  </span>
                  <span className="min-w-0 flex-1 py-1">
                    <span className="line-clamp-2 text-sm leading-snug font-semibold capitalize">
                      {alternative.name}
                    </span>
                    <span className="mt-1 block text-xs font-medium text-primary">
                      Use {titleCase(alternative.equipment)}
                    </span>
                  </span>
                </button>
              ))
            )}
          </div>
        </div>
      </AppSurface>
    </AppScreen>
  )
}
