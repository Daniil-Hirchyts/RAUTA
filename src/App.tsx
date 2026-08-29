import { useEffect, useMemo, useRef, useState } from "react"
import {
  CalendarDays,
  Check,
  ChevronLeft,
  ChevronRight,
  Heart,
  ListPlus,
  RotateCcw,
  SearchX,
  X,
} from "lucide-react"

import { AnimatedNumber } from "@/components/animated-number"
import { BodyMap } from "@/components/body-map"
import { EquipmentPresets } from "@/components/equipment-presets"
import { ExerciseCard } from "@/components/exercise-card"
import { ExerciseDetailDialog } from "@/components/exercise-detail-dialog"
import { SvgFilterDefs } from "@/components/svg-filters"
import { Button } from "@/components/ui/button"
import { WorkoutDetailPage } from "@/components/workout-detail-page"
import { WorkoutFormDialog } from "@/components/workout-form-dialog"
import { WorkoutsPage } from "@/components/workouts-page"
import { EQUIPMENT_OPTIONS, EXERCISES, filterExercises } from "@/lib/exercises"
import { titleCase } from "@/lib/text"
import { equipmentImage } from "@/lib/visuals"
import { useFavorites } from "@/store/use-favorites"
import { useFilters } from "@/store/use-filters"
import type { Workout } from "@/store/use-workouts"
import type { ExerciseSummary } from "@/types"

type Stage = 1 | 2 | 3

type View =
  | { type: "flow" }
  | { type: "workouts" }
  | { type: "workout-detail"; workoutId: string }

const STAGE_LABELS: Record<Stage, string> = {
  1: "Muscles",
  2: "Equipment",
  3: "Exercises",
}

function StageHeading({ stage }: { stage: Stage }) {
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const element = ref.current
    if (!element) return
    element.classList.remove("is-shown")
    void element.offsetHeight
    const frame = requestAnimationFrame(() => element.classList.add("is-shown"))
    return () => cancelAnimationFrame(frame)
  }, [stage])

  return (
    <div className="t-stagger" ref={ref}>
      <p className="t-stagger-line t-stagger-line--1 text-xs font-bold tracking-[0.16em] text-muted-foreground uppercase">
        {stage} / 3
      </p>
      <h1 className="t-stagger-line t-stagger-line--2 mt-0.5 bg-gradient-to-r from-foreground to-foreground/75 bg-clip-text text-[32px] leading-[1.05] font-black tracking-[-0.03em] text-transparent">
        {STAGE_LABELS[stage]}
      </h1>
    </div>
  )
}

export function App() {
  const [view, setView] = useState<View>({ type: "flow" })
  const [stage, setStage] = useState<Stage>(1)
  const selectedMuscles = useFilters((state) => state.selectedMuscles)
  const selectedEquipment = useFilters((state) => state.selectedEquipment)
  const toggleMuscle = useFilters((state) => state.toggleMuscle)
  const toggleEquipment = useFilters((state) => state.toggleEquipment)
  const reset = useFilters((state) => state.reset)
  const favoriteIds = useFavorites((state) => state.favoriteIds)

  const [favoritesOnly, setFavoritesOnly] = useState(false)
  const [selectMode, setSelectMode] = useState(false)
  const [selectedIds, setSelectedIds] = useState<string[]>([])

  const [detailExercise, setDetailExercise] = useState<ExerciseSummary | null>(
    null
  )
  const [detailOpen, setDetailOpen] = useState(false)

  const [workoutFormOpen, setWorkoutFormOpen] = useState(false)
  // Bumped on every "open the workout form" action so the dialog remounts
  // with clean local state instead of reusing whatever was left over from
  // the previous time it was open (see WorkoutFormDialog).
  const [workoutFormGeneration, setWorkoutFormGeneration] = useState(0)
  const [workoutFormSeed, setWorkoutFormSeed] = useState<{
    workout?: Workout | null
    exerciseIds?: string[]
  }>({})

  const exercises = useMemo(
    () => filterExercises(EXERCISES, selectedMuscles, selectedEquipment),
    [selectedMuscles, selectedEquipment]
  )

  const visibleExercises = useMemo(
    () =>
      favoritesOnly
        ? exercises.filter((exercise) => favoriteIds.includes(exercise.id))
        : exercises,
    [exercises, favoritesOnly, favoriteIds]
  )

  const canContinue =
    stage === 1 ? selectedMuscles.length > 0 : selectedEquipment.length > 0
  const hasFilters = selectedMuscles.length > 0 || selectedEquipment.length > 0

  const goForward = () =>
    setStage((current) => Math.min(3, current + 1) as Stage)
  const goBack = () => setStage((current) => Math.max(1, current - 1) as Stage)
  const resetFlow = () => {
    reset()
    setStage(1)
  }

  const openDetail = (exercise: ExerciseSummary) => {
    setDetailExercise(exercise)
    setDetailOpen(true)
  }

  const toggleSelected = (id: string) =>
    setSelectedIds((ids) =>
      ids.includes(id) ? ids.filter((current) => current !== id) : [...ids, id]
    )

  const cancelSelectMode = () => {
    setSelectMode(false)
    setSelectedIds([])
  }

  const openWorkoutForm = (seed: {
    workout?: Workout | null
    exerciseIds?: string[]
  }) => {
    setWorkoutFormSeed(seed)
    setWorkoutFormGeneration((generation) => generation + 1)
    setWorkoutFormOpen(true)
  }

  const addSelectionToWorkout = () => {
    if (selectedIds.length === 0) return
    openWorkoutForm({ exerciseIds: selectedIds })
  }

  const addExerciseToWorkout = (exercise: ExerciseSummary) => {
    setDetailOpen(false)
    openWorkoutForm({ exerciseIds: [exercise.id] })
  }

  const editWorkout = (workout: Workout) => openWorkoutForm({ workout })

  return (
    <div className="min-h-svh bg-[#0e0e0f] text-foreground">
      <SvgFilterDefs />
      <main className="relative mx-auto flex h-svh w-full max-w-[430px] flex-col overflow-hidden border-x border-white/[0.04] bg-background pt-[env(safe-area-inset-top)] shadow-2xl shadow-black/40">
        {view.type === "workouts" && (
          <WorkoutsPage
            onBack={() => setView({ type: "flow" })}
            onSelect={(workout) =>
              setView({ type: "workout-detail", workoutId: workout.id })
            }
          />
        )}

        {view.type === "workout-detail" && (
          <WorkoutDetailPage
            onBack={() => setView({ type: "workouts" })}
            onDeleted={() => setView({ type: "workouts" })}
            onDuplicated={() => setView({ type: "workouts" })}
            onEdit={editWorkout}
            onOpenExercise={openDetail}
            workoutId={view.workoutId}
          />
        )}

        {view.type === "flow" && (
          <>
            <header className="shrink-0 border-b border-white/[0.05] bg-background/80 px-5 pt-4 pb-3 backdrop-blur-xl">
              <div className="mb-5 flex items-center justify-between">
                <div
                  aria-label={`Step ${stage} of 3`}
                  aria-valuemax={3}
                  aria-valuemin={1}
                  aria-valuenow={stage}
                  className="flex items-center gap-2.5"
                  role="progressbar"
                >
                  {[1, 2, 3].map((step) => (
                    <span
                      aria-hidden="true"
                      className={`h-2 rounded-full transition-[width,background-color] duration-250 ${
                        step === stage
                          ? "w-9 bg-primary"
                          : step < stage
                            ? "w-5 bg-primary/35"
                            : "w-5 bg-white/10"
                      }`}
                      key={step}
                    />
                  ))}
                </div>
                <div className="flex items-center gap-1.5">
                  <Button
                    aria-label="My workouts"
                    className="rounded-full text-muted-foreground hover:text-foreground"
                    onClick={() => setView({ type: "workouts" })}
                    size="icon"
                    variant="ghost"
                  >
                    <CalendarDays />
                  </Button>
                  {hasFilters && (
                    <Button
                      aria-label="Reset selections"
                      className="rounded-full text-muted-foreground hover:text-foreground"
                      onClick={resetFlow}
                      size="icon"
                      variant="ghost"
                    >
                      <RotateCcw />
                    </Button>
                  )}
                </div>
              </div>
              <div className="flex items-end justify-between">
                <StageHeading stage={stage} />
                <output
                  aria-live="polite"
                  className="text-[15px] font-medium text-muted-foreground tabular-nums"
                  data-testid="stage-count"
                >
                  {stage === 1 && (
                    <>
                      <AnimatedNumber value={selectedMuscles.length} /> selected
                    </>
                  )}
                  {stage === 2 && (
                    <>
                      <AnimatedNumber value={selectedEquipment.length} />{" "}
                      selected
                    </>
                  )}
                  {stage === 3 && (
                    <>
                      <AnimatedNumber value={visibleExercises.length} />{" "}
                      exercises
                    </>
                  )}
                </output>
              </div>
            </header>

            <div className="t-page-slide min-h-0 flex-1" data-page={stage}>
              <section
                aria-hidden={stage !== 1}
                aria-label="Choose muscles"
                className="t-page px-5 pt-5 pb-[calc(6.5rem+env(safe-area-inset-bottom))]"
                data-page-id="1"
                inert={stage !== 1}
              >
                <div className="h-full min-h-0 rounded-[28px] border border-border bg-card/60 px-4 pt-5 pb-4 shadow-[0_18px_40px_rgba(0,0,0,0.16)] backdrop-blur-xl">
                  <BodyMap
                    onToggle={toggleMuscle}
                    selectedMuscles={selectedMuscles}
                  />
                </div>
              </section>

              <section
                aria-hidden={stage !== 2}
                aria-label="Choose equipment"
                className="t-page overflow-y-auto px-5 pt-5 pb-[calc(6.5rem+env(safe-area-inset-bottom))]"
                data-page-id="2"
                inert={stage !== 2}
              >
                <EquipmentPresets />
                <div className="grid grid-cols-2 gap-3">
                  {EQUIPMENT_OPTIONS.map((equipment) => {
                    const checked = selectedEquipment.includes(equipment)
                    return (
                      <button
                        aria-checked={checked}
                        className={`t-check group relative overflow-hidden rounded-[22px] border text-left transition-transform duration-150 active:scale-[0.97] ${
                          checked
                            ? "border-primary/70 bg-primary/10 shadow-[0_0_0_1px_rgba(255,102,51,0.12)] backdrop-blur-sm"
                            : "border-border bg-card/70 backdrop-blur-sm"
                        }`}
                        key={equipment}
                        onClick={() => toggleEquipment(equipment)}
                        role="checkbox"
                        type="button"
                      >
                        <span className="relative block aspect-[1.18] overflow-hidden bg-[#161618]">
                          <img
                            alt=""
                            className="h-full w-full object-cover transition-transform duration-250 ease-[var(--ease-smooth-out)] group-hover:scale-[1.025]"
                            draggable={false}
                            loading="lazy"
                            src={equipmentImage(equipment)}
                          />
                        </span>
                        <span className="flex min-h-13 items-center justify-center px-3.5 py-3 text-center text-base leading-tight font-semibold">
                          {titleCase(equipment)}
                        </span>
                        <span className="absolute top-2.5 right-2.5 grid size-7 place-items-center rounded-full border border-white/10 bg-black/55 text-primary backdrop-blur-sm">
                          <Check className="size-4" />
                        </span>
                      </button>
                    )
                  })}
                </div>
              </section>

              <section
                aria-hidden={stage !== 3}
                aria-label="Matching exercises"
                className="t-page overflow-y-auto px-5 pt-5 pb-[calc(6.5rem+env(safe-area-inset-bottom))]"
                data-page-id="3"
                inert={stage !== 3}
              >
                {visibleExercises.length === 0 ? (
                  <div className="flex h-full min-h-[20rem] flex-col items-center justify-center gap-3 text-center">
                    <SearchX className="size-7 text-muted-foreground/60" />
                    <p className="max-w-[16rem] text-base text-muted-foreground">
                      {favoritesOnly
                        ? "No favorites yet. Tap the heart on an exercise to save it here."
                        : "0 exercises"}
                    </p>
                  </div>
                ) : (
                  <div
                    className="t-stagger is-shown grid grid-cols-2 gap-3.5"
                    data-testid="exercise-results"
                  >
                    {visibleExercises.map((exercise, index) => (
                      <ExerciseCard
                        exercise={exercise}
                        index={index}
                        key={exercise.id}
                        onOpenDetail={openDetail}
                        onToggleSelect={toggleSelected}
                        selectMode={selectMode}
                        selected={selectedIds.includes(exercise.id)}
                      />
                    ))}
                  </div>
                )}
                {visibleExercises.length > 0 && (
                  <p className="mt-4 text-center text-xs text-muted-foreground/70">
                    Exercise animations © Gym visual —{" "}
                    <a
                      className="underline underline-offset-2"
                      href="https://gymvisual.com/"
                      rel="noreferrer"
                      target="_blank"
                    >
                      gymvisual.com
                    </a>
                  </p>
                )}
              </section>
            </div>

            <footer className="absolute inset-x-0 bottom-0 z-20 px-5 pt-4 pb-[calc(1rem+env(safe-area-inset-bottom))]">
              <div className="flex gap-2.5">
                {stage === 3 && selectMode ? (
                  <>
                    <Button
                      aria-label="Cancel selection"
                      className="size-[3.25rem] shrink-0 rounded-[26px]"
                      onClick={cancelSelectMode}
                      size="icon"
                      variant="secondary"
                    >
                      <X />
                    </Button>
                    <Button
                      className="h-[3.25rem] flex-1 rounded-[26px] text-base font-semibold"
                      disabled={selectedIds.length === 0}
                      onClick={addSelectionToWorkout}
                    >
                      <ListPlus data-icon="inline-start" />
                      Add to workout
                      {selectedIds.length > 0 && ` (${selectedIds.length})`}
                    </Button>
                  </>
                ) : (
                  <>
                    {stage > 1 && (
                      <button
                        aria-label={
                          stage === 3 && favoritesOnly
                            ? "Back to all exercises"
                            : "Previous stage"
                        }
                        className="grid size-[3.25rem] shrink-0 place-items-center rounded-[26px] border border-border bg-card/70 text-muted-foreground backdrop-blur-sm transition-transform duration-150 active:scale-95"
                        onClick={() =>
                          stage === 3 && favoritesOnly
                            ? setFavoritesOnly(false)
                            : goBack()
                        }
                        type="button"
                      >
                        <ChevronLeft className="size-5" />
                      </button>
                    )}
                    {stage === 3 && (
                      <button
                        aria-label={
                          favoritesOnly
                            ? "Show all exercises"
                            : "Show favorites only"
                        }
                        aria-pressed={favoritesOnly}
                        className={`grid size-[3.25rem] shrink-0 place-items-center rounded-[26px] border backdrop-blur-sm transition-transform duration-150 active:scale-95 ${
                          favoritesOnly
                            ? "border-primary/70 bg-primary/10 text-primary"
                            : "border-border bg-card/70 text-muted-foreground"
                        }`}
                        onClick={() => setFavoritesOnly((value) => !value)}
                        type="button"
                      >
                        <Heart
                          className={favoritesOnly ? "size-5 fill-primary" : "size-5"}
                        />
                      </button>
                    )}
                    {stage < 3 ? (
                      <Button
                        className="h-[3.25rem] flex-1 rounded-[26px] text-base font-semibold"
                        disabled={!canContinue}
                        onClick={goForward}
                      >
                        {stage === 1 ? "Choose equipment" : "Show exercises"}
                        <ChevronRight data-icon="inline-end" />
                      </Button>
                    ) : (
                      <Button
                        className="h-[3.25rem] flex-1 rounded-[26px] text-base font-semibold"
                        onClick={() => setSelectMode(true)}
                      >
                        Select
                      </Button>
                    )}
                  </>
                )}
              </div>
            </footer>
          </>
        )}
      </main>

      <ExerciseDetailDialog
        exercise={detailExercise}
        onAddToWorkout={addExerciseToWorkout}
        onOpenChange={setDetailOpen}
        open={detailOpen}
      />

      <WorkoutFormDialog
        initialExerciseIds={workoutFormSeed.exerciseIds}
        key={workoutFormGeneration}
        onOpenChange={setWorkoutFormOpen}
        onSaved={cancelSelectMode}
        open={workoutFormOpen}
        workout={workoutFormSeed.workout}
      />
    </div>
  )
}

export default App
