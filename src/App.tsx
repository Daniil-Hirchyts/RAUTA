import { useEffect, useMemo, useRef, useState } from "react"
import {
  CalendarDays,
  ChevronLeft,
  Eraser,
  SearchX,
  X,
} from "lucide-react"

import { AnimatedNumber } from "@/components/animated-number"
import { AnimatedCheck } from "@/components/animated-check"
import { BodyMap } from "@/components/body-map"
import { EquipmentPresets } from "@/components/equipment-presets"
import { ExerciseCard } from "@/components/exercise-card"
import { ExerciseDetailDrawer } from "@/components/exercise-detail-drawer"
import { HapticLayer } from "@/components/haptic-layer"
import { LikeButton } from "@/components/like-button"
import { SvgFilterDefs } from "@/components/svg-filters"
import { Button } from "@/components/ui/button"
import { DotPattern } from "@/components/ui/dot-pattern"
import { ProgressiveBlur } from "@/components/ui/progressive-blur"
import { WorkoutDetailPage } from "@/components/workout-detail-page"
import { WorkoutFormDrawer } from "@/components/workout-form-drawer"
import { WorkoutsPage } from "@/components/workouts-page"
import { useSwipeNavigation } from "@/hooks/use-swipe-navigation"
import { EQUIPMENT_OPTIONS, EXERCISES, filterExercises } from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { titleCase } from "@/lib/text"
import { equipmentImage } from "@/lib/visuals"
import { useFavorites } from "@/store/use-favorites"
import { useFilters } from "@/store/use-filters"
import type { Workout } from "@/store/use-workouts"
import type { ExerciseSummary, MuscleId } from "@/types"

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
  const [initialStage] = useState(stage)
  const elementRef = useRef<HTMLDivElement>(null)
  const displayedStage = useRef(stage)

  useEffect(() => {
    if (stage === displayedStage.current) return
    const element = elementRef.current
    if (!element) return
    const step = element.querySelector<HTMLElement>("[data-stage-step]")
    const title = element.querySelector<HTMLElement>("[data-stage-title]")
    if (!step || !title) return

    element.classList.add("is-exit")
    const reduceMotion = window.matchMedia?.(
      "(prefers-reduced-motion: reduce)"
    ).matches
    const timeout = window.setTimeout(() => {
      displayedStage.current = stage
      step.textContent = `${stage} / 3`
      title.textContent = STAGE_LABELS[stage]
      element.classList.remove("is-exit")
      element.classList.add("is-enter-start")
      void element.offsetHeight
      element.classList.remove("is-enter-start")
    }, reduceMotion ? 0 : 150)
    return () => window.clearTimeout(timeout)
  }, [stage])

  return (
    <div className="t-text-swap" ref={elementRef}>
      <p
        className="text-xs font-bold tracking-[0.16em] text-muted-foreground uppercase"
        data-stage-step
      >
        {initialStage} / 3
      </p>
      <h1
        className="mt-0.5 text-[32px] leading-[1.05] font-black tracking-[-0.03em] text-foreground"
        data-stage-title
      >
        {STAGE_LABELS[initialStage]}
      </h1>
    </div>
  )
}

export function App() {
  const [view, setView] = useState<View>({ type: "flow" })
  const [stage, setStage] = useState<Stage>(1)
  const selectedMuscles = useFilters((state) => state.selectedMuscles)
  const muscleDotIntensity = Math.min(selectedMuscles.length / 6, 1)
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
  // Bumped on every "open the workout form" action so the drawer remounts
  // with clean local state instead of reusing whatever was left over from
  // the previous time it was open (see WorkoutFormDrawer).
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

  const goForward = () => {
    triggerHaptic("medium")
    setStage((current) => Math.min(3, current + 1) as Stage)
  }
  const goBack = () => {
    triggerHaptic("medium")
    setStage((current) => Math.max(1, current - 1) as Stage)
  }
  const resetFlow = () => {
    triggerHaptic("warning")
    reset()
    setStage(1)
  }

  const toggleMuscleWithHaptic = (muscle: MuscleId) => {
    triggerHaptic("selection")
    toggleMuscle(muscle)
  }

  const toggleEquipmentWithHaptic = (equipment: string) => {
    triggerHaptic("selection")
    toggleEquipment(equipment)
  }

  const openDetail = (exercise: ExerciseSummary) => {
    triggerHaptic("light")
    setDetailExercise(exercise)
    setDetailOpen(true)
  }

  const toggleSelected = (id: string) => {
    triggerHaptic("selection")
    setSelectedIds((ids) =>
      ids.includes(id) ? ids.filter((current) => current !== id) : [...ids, id]
    )
  }

  const cancelSelectMode = () => {
    triggerHaptic("selection")
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

  const swipeNavigation = useSwipeNavigation((direction) => {
    if (direction === "right") {
      if (view.type === "workout-detail") {
        triggerHaptic("medium")
        setView({ type: "workouts" })
        return
      }
      if (view.type === "workouts") {
        triggerHaptic("medium")
        setView({ type: "flow" })
        return
      }
      if (selectMode) {
        cancelSelectMode()
        return
      }
      if (stage > 1) goBack()
      return
    }

    if (view.type === "flow" && stage < 3 && canContinue) goForward()
  })

  return (
    <div className="min-h-svh bg-[#0e0e0f] text-foreground">
      <HapticLayer />
      <SvgFilterDefs />
      <main
        className="relative mx-auto flex h-svh w-full max-w-[430px] touch-pan-y flex-col overflow-hidden border-x border-white/[0.04] bg-background pt-[env(safe-area-inset-top)] shadow-2xl shadow-black/40"
        {...swipeNavigation}
      >
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
                    className="rounded-full bg-card text-muted-foreground hover:bg-muted hover:text-foreground"
                    onClick={() => {
                      triggerHaptic("medium")
                      setView({ type: "workouts" })
                    }}
                    size="icon-lg"
                    variant="ghost"
                  >
                    <CalendarDays className="size-5.5" />
                  </Button>
                  {hasFilters && (
                    <Button
                      aria-label="Reset selections"
                      className="rounded-full bg-card text-muted-foreground hover:bg-muted hover:text-foreground"
                      onClick={resetFlow}
                      size="icon-lg"
                      variant="ghost"
                    >
                      <Eraser className="size-5.5" />
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
                <div className="relative h-full min-h-0 overflow-hidden rounded-[28px] border border-border bg-card/60 px-4 pt-5 pb-4 shadow-[0_18px_40px_rgba(0,0,0,0.16)] backdrop-blur-xl">
                  <DotPattern
                    className="[mask-image:radial-gradient(ellipse_at_center,black_15%,transparent_72%)] transition-[fill,fill-opacity] duration-500 ease-[var(--ease-smooth-out)]"
                    cr={1}
                    height={18}
                    style={{
                      fill: `color-mix(in oklch, var(--muted-foreground), var(--primary) ${25 + muscleDotIntensity * 55}%)`,
                      fillOpacity: 0.3 + muscleDotIntensity * 0.3,
                    }}
                    width={18}
                  />
                  <div className="relative z-10 h-full">
                    <BodyMap
                      onToggle={toggleMuscleWithHaptic}
                      selectedMuscles={selectedMuscles}
                    />
                  </div>
                </div>
              </section>

              <section
                aria-hidden={stage !== 2}
                aria-label="Choose equipment"
                className="t-page overflow-y-auto px-5 pt-2 pb-[calc(6.5rem+env(safe-area-inset-bottom))]"
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
                        className={`t-check group relative overflow-hidden rounded-[22px] border bg-card text-left transition-[border-color,box-shadow] duration-300 ease-[var(--ease-smooth-out)] ${
                          checked
                            ? "border-primary shadow-[0_0_0_1px_var(--primary)]"
                            : "border-border"
                        }`}
                        key={equipment}
                        onClick={() => toggleEquipmentWithHaptic(equipment)}
                        role="checkbox"
                        type="button"
                      >
                        <span className="relative block aspect-[1.18] overflow-hidden bg-[#161618]">
                          <img
                            alt=""
                            className="h-full w-full object-cover saturate-[1.65] transition-transform duration-250 ease-[var(--ease-smooth-out)] group-hover:scale-[1.025]"
                            draggable={false}
                            loading="lazy"
                            src={equipmentImage(equipment)}
                          />
                        </span>
                        <span className="flex min-h-13 items-center justify-center px-3.5 py-3 text-center text-base leading-tight font-semibold">
                          {titleCase(equipment)}
                        </span>
                        <AnimatedCheck
                          checked={checked}
                          className="absolute top-2.5 right-2.5 size-7"
                        />
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
                    <SearchX className="size-7 text-[color-mix(in_oklch,var(--muted-foreground),var(--background)_35%)]" />
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
              </section>
            </div>

            <footer className="absolute inset-x-0 bottom-0 z-20 px-5 pt-4 pb-[calc(1rem+env(safe-area-inset-bottom))]">
              <ProgressiveBlur
                className="absolute inset-x-0 -top-6 bottom-0"
                direction="bottom"
              />
              <div className="relative flex gap-2.5">
                {stage > 1 && !selectMode && (
                  <Button
                    aria-label="Previous stage"
                    className="size-[3.25rem] shrink-0 rounded-[26px]"
                    onClick={goBack}
                    size="icon"
                    variant="secondary"
                  >
                    <ChevronLeft className="size-5" />
                  </Button>
                )}
                {stage === 3 && selectMode && (
                  <Button
                    aria-label="Cancel selection"
                    className="size-[3.25rem] shrink-0 rounded-[26px]"
                    onClick={cancelSelectMode}
                    size="icon"
                    variant="secondary"
                  >
                    <X />
                  </Button>
                )}
                {stage === 3 && (
                  <LikeButton
                    animated={false}
                    aria-label={
                      favoritesOnly
                        ? "Show all exercises"
                        : "Show favorites only"
                    }
                    className={`grid size-[3.25rem] shrink-0 place-items-center rounded-[26px] border transition-colors duration-150 ${
                      favoritesOnly
                        ? "border-primary bg-[color-mix(in_oklch,var(--card),var(--primary)_16%)] text-primary"
                        : "border-border bg-card text-muted-foreground hover:bg-muted"
                    }`}
                    iconClassName="size-5"
                    liked={favoritesOnly}
                    onClick={() => {
                      triggerHaptic("selection")
                      setFavoritesOnly((value) => !value)
                    }}
                  />
                )}
                {stage < 3 ? (
                  <Button
                    className="h-[3.25rem] flex-1 rounded-[26px] text-base font-semibold"
                    disabled={!canContinue}
                    onClick={goForward}
                  >
                    {stage === 1 ? "Choose equipment" : "Show exercises"}
                  </Button>
                ) : selectMode ? (
                  <Button
                    className="h-[3.25rem] flex-1 rounded-[26px] text-base font-semibold"
                    disabled={selectedIds.length === 0}
                    onClick={addSelectionToWorkout}
                  >
                    Add to workout
                    {selectedIds.length > 0 && ` (${selectedIds.length})`}
                  </Button>
                ) : (
                  <Button
                    className="h-[3.25rem] flex-1 rounded-[26px] text-base font-semibold"
                    onClick={() => {
                      triggerHaptic("medium")
                      setSelectMode(true)
                    }}
                  >
                    Select
                  </Button>
                )}
              </div>
            </footer>
          </>
        )}
      </main>

      <ExerciseDetailDrawer
        exercise={detailExercise}
        onAddToWorkout={addExerciseToWorkout}
        onOpenChange={setDetailOpen}
        open={detailOpen}
      />

      <WorkoutFormDrawer
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
