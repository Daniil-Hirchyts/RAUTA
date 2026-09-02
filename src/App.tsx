import {
  Fragment,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
} from "react"
import {
  ChevronLeft,
  FlipHorizontal2,
  Home,
  Search,
  SearchX,
  X,
} from "lucide-react"

import { AnimatedCheck } from "@/components/animated-check"
import {
  AppControls,
  AppDrawerHost,
  AppHeaderButton,
  AppScreen,
  AppShellHeader,
  AppSurface,
} from "@/components/app-shell"
import { BodyMap } from "@/components/body-map"
import { EquipmentPresets } from "@/components/equipment-presets"
import { ExerciseCard } from "@/components/exercise-card"
import { ExerciseDetailDrawer } from "@/components/exercise-detail-drawer"
import { ExerciseSearch } from "@/components/exercise-search"
import { HapticLayer } from "@/components/haptic-layer"
import { LikeButton } from "@/components/like-button"
import { SettingsEffects } from "@/components/settings-effects"
import { SettingsPage } from "@/components/settings-page"
import { SvgFilterDefs } from "@/components/svg-filters"
import { SwipeBackPage } from "@/components/swipe-back-page"
import { Button } from "@/components/ui/button"
import { DotPattern } from "@/components/ui/dot-pattern"
import { MatrixLoader } from "@/components/ui/matrix-loader"
import { WorkoutDetailPage } from "@/components/workout-detail-page"
import { WorkoutDestinationDrawer } from "@/components/workout-destination-drawer"
import { WorkoutFormDrawer } from "@/components/workout-form-drawer"
import { WorkoutsPage } from "@/components/workouts-page"
import { useEdgeSwipe } from "@/hooks/use-edge-swipe"
import { useLoadMoreOnScroll } from "@/hooks/use-load-more-on-scroll"
import {
  EQUIPMENT_OPTIONS,
  EXERCISE_PAGE_SIZE,
  EXERCISES,
  EXERCISES_BY_ID,
  filterExercises,
  supportingFromIndex,
} from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { titleCase } from "@/lib/text"
import { cn } from "@/lib/utils"
import { equipmentImage } from "@/lib/visuals"
import { useFavorites } from "@/store/use-favorites"
import { useFilters } from "@/store/use-filters"
import {
  readAppSession,
  writeAppSession,
  type AppStage as Stage,
  type AppView as View,
} from "@/store/app-session"
import { useWorkouts, type Workout } from "@/store/use-workouts"
import type { ExerciseSummary, MuscleId } from "@/types"

const STAGE_LABELS: Record<Stage, string> = {
  1: "Muscles",
  2: "Equipment",
  3: "Exercises",
}

function StageHeading({ stage }: { stage: Stage }) {
  // The label is React state, not a node an effect reaches in and rewrites.
  // "shown" trails "stage" by the length of the exit leg, so the swap lands
  // when the old word has finished leaving — and "exiting" is derived from the
  // gap between them rather than tracked separately. A fast back-then-forward
  // tap closes that gap on its own, which cancels the exit instead of leaving
  // the header stuck invisible.
  const [shown, setShown] = useState(stage)
  const [entering, setEntering] = useState(false)
  const exiting = stage !== shown

  useEffect(() => {
    if (!exiting) return
    const reduceMotion = window.matchMedia?.(
      "(prefers-reduced-motion: reduce)"
    ).matches
    const timeout = window.setTimeout(
      () => {
        setShown(stage)
        setEntering(true)
      },
      reduceMotion ? 0 : 150
    )
    return () => window.clearTimeout(timeout)
  }, [exiting, stage])

  useEffect(() => {
    if (!entering) return
    // The new word paints offset with transitions off; clearing that on the
    // next frame is what the forced reflow used to buy.
    const frame = requestAnimationFrame(() =>
      requestAnimationFrame(() => setEntering(false))
    )
    return () => cancelAnimationFrame(frame)
  }, [entering])

  return (
    <div
      className={cn(
        "t-text-swap",
        exiting && "is-exit",
        entering && "is-enter-start"
      )}
    >
      <span>{STAGE_LABELS[shown]}</span>
    </div>
  )
}

function FlowProgress({ stage }: { stage: Stage }) {
  return (
    <div
      aria-label={`Step ${stage} of 3`}
      aria-valuemax={3}
      aria-valuemin={1}
      aria-valuenow={stage}
      className="flex items-center justify-center gap-1.5"
      role="progressbar"
    >
      {[1, 2, 3].map((step) => (
        <span
          aria-hidden="true"
          className={`h-1 rounded-full transition-[width,background-color] duration-250 ${
            step === stage
              ? "w-7 bg-primary"
              : step < stage
                ? "w-3.5 bg-primary/35"
                : "w-3.5 bg-white/10"
          }`}
          key={step}
        />
      ))}
    </div>
  )
}

export function App() {
  const [initialSession] = useState(readAppSession)
  const [view, setView] = useState<View>(initialSession.view)
  const [viewDirection, setViewDirection] = useState<"forward" | "back">(
    "forward"
  )
  const navigate = useCallback(
    (nextView: View, direction: "forward" | "back" = "forward") => {
      setViewDirection(direction)
      setView(nextView)
    },
    []
  )
  const [stage, setStage] = useState<Stage>(initialSession.stage)
  const selectedMuscles = useFilters((state) => state.selectedMuscles)
  const muscleDotIntensity = Math.min(selectedMuscles.length / 6, 1)
  const selectedEquipment = useFilters((state) => state.selectedEquipment)
  const toggleMuscle = useFilters((state) => state.toggleMuscle)
  const toggleEquipment = useFilters((state) => state.toggleEquipment)
  const setMuscles = useFilters((state) => state.setMuscles)
  const setEquipment = useFilters((state) => state.setEquipment)
  const reset = useFilters((state) => state.reset)
  const favoriteIds = useFavorites((state) => state.favoriteIds)

  const [favoritesOnly, setFavoritesOnly] = useState(
    initialSession.favoritesOnly
  )
  const [selectMode, setSelectMode] = useState(initialSession.selectMode)
  const [selectedIds, setSelectedIds] = useState<string[]>(
    initialSession.selectedIds
  )

  const [detailExercise, setDetailExercise] = useState<ExerciseSummary | null>(
    initialSession.detailExerciseId
      ? (EXERCISES_BY_ID.get(initialSession.detailExerciseId) ?? null)
      : null
  )
  const [detailOpen, setDetailOpen] = useState(initialSession.detailOpen)

  const [workoutFormOpen, setWorkoutFormOpen] = useState(
    initialSession.workoutFormOpen
  )
  const [workoutDestinationOpen, setWorkoutDestinationOpen] = useState(false)
  const [preferredWorkoutId, setPreferredWorkoutId] = useState<string | null>(
    null
  )
  // Bumped on every "open the workout form" action so the drawer remounts
  // with clean local state instead of reusing whatever was left over from
  // the previous time it was open (see WorkoutFormDrawer).
  const [workoutFormGeneration, setWorkoutFormGeneration] = useState(0)
  const [workoutFormSeed, setWorkoutFormSeed] = useState<{
    workout?: Workout | null
    exerciseIds?: string[]
  }>(() => ({
    exerciseIds: initialSession.workoutFormExerciseIds,
    workout: initialSession.workoutFormWorkoutId
      ? (useWorkouts
          .getState()
          .workouts.find(
            (workout) => workout.id === initialSession.workoutFormWorkoutId
          ) ?? null)
      : null,
  }))

  const appSession = useMemo(
    () => ({
      detailExerciseId: detailExercise?.id ?? null,
      detailOpen,
      favoritesOnly,
      selectedIds,
      selectMode,
      stage,
      view,
      workoutFormExerciseIds: workoutFormSeed.exerciseIds ?? [],
      workoutFormOpen,
      workoutFormWorkoutId: workoutFormSeed.workout?.id ?? null,
    }),
    [
      detailExercise?.id,
      detailOpen,
      favoritesOnly,
      selectedIds,
      selectMode,
      stage,
      view,
      workoutFormOpen,
      workoutFormSeed.exerciseIds,
      workoutFormSeed.workout?.id,
    ]
  )

  const latestSession = useRef(appSession)

  useEffect(() => {
    writeAppSession(appSession)
    latestSession.current = appSession
  }, [appSession])

  useEffect(() => {
    // Reads the latest session through a ref, so suspending the app is wired
    // up once instead of on every stage change and every selection.
    const saveBeforeSuspending = () => writeAppSession(latestSession.current)
    window.addEventListener("pagehide", saveBeforeSuspending)
    document.addEventListener("visibilitychange", saveBeforeSuspending)
    return () => {
      window.removeEventListener("pagehide", saveBeforeSuspending)
      document.removeEventListener("visibilitychange", saveBeforeSuspending)
    }
  }, [])

  const exercises = useMemo(
    () => filterExercises(EXERCISES, selectedMuscles, selectedEquipment),
    [selectedMuscles, selectedEquipment]
  )

  const [search, setSearch] = useState("")
  const [searchOpen, setSearchOpen] = useState(false)
  const [bodySide, setBodySide] = useState<"front" | "back">("front")
  const equipmentScrollRef = useRef<HTMLElement>(null)

  const visibleExercises = useMemo(() => {
    const shortlist = favoritesOnly
      ? exercises.filter((exercise) => favoriteIds.includes(exercise.id))
      : exercises
    const query = search.trim().toLowerCase()
    if (!query) return shortlist
    return shortlist.filter((exercise) =>
      exercise.name.toLowerCase().includes(query)
    )
  }, [exercises, favoritesOnly, favoriteIds, search])

  const {
    hasMore: hasMoreExercises,
    rootRef: exercisesScrollRef,
    sentinelRef: loadMoreSentinelRef,
    visibleCount,
  } = useLoadMoreOnScroll(visibleExercises.length, EXERCISE_PAGE_SIZE)
  const pagedExercises = visibleExercises.slice(0, visibleCount)

  // Results are ordered by how much of an exercise actually goes into the
  // picked muscles, so everything past this index still involves them but is
  // built around something else. Labelling the seam beats silently hiding the
  // tail: the exercises stay reachable, they just stop pretending to be the
  // answer.
  const supportingIndex = useMemo(
    () => supportingFromIndex(visibleExercises, selectedMuscles),
    [visibleExercises, selectedMuscles]
  )

  const canContinue =
    stage === 1
      ? selectedMuscles.length > 0
      : selectedEquipment.length > 0 && exercises.length > 0

  const goForward = () => {
    triggerHaptic("medium")
    setStage((current) => Math.min(3, current + 1) as Stage)
  }
  const goBack = () => {
    triggerHaptic("medium")
    setStage((current) => Math.max(1, current - 1) as Stage)
  }

  const toggleSearch = () => {
    triggerHaptic("medium")
    // Closing takes the query with it: a filter that keeps narrowing the
    // results from behind a hidden field has no visible cause.
    if (searchOpen) setSearch("")
    setSearchOpen(!searchOpen)
  }

  const toggleMuscleWithHaptic = useCallback(
    (muscle: MuscleId) => {
      triggerHaptic("selection")
      toggleMuscle(muscle)
    },
    [toggleMuscle]
  )

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
    triggerHaptic("medium")
    setWorkoutDestinationOpen(true)
  }

  const selectExerciseFromDetail = (exercise: ExerciseSummary) => {
    triggerHaptic("selection")
    setSelectedIds((ids) =>
      ids.includes(exercise.id) ? ids : [...ids, exercise.id]
    )
    setSelectMode(true)
    setDetailOpen(false)
  }

  const startExerciseFlow = (workoutId?: string) => {
    triggerHaptic("medium")
    reset()
    setSearch("")
    setSearchOpen(false)
    setBodySide("front")
    setStage(1)
    setSelectMode(false)
    setSelectedIds([])
    setPreferredWorkoutId(workoutId ?? null)
    navigate({ type: "flow" })
  }

  const {
    containerRef: swipeContainerRef,
    dragging: swipeDragging,
    handlers: swipeHandlers,
    offset: swipeOffset,
    peer: swipePeer,
  } = useEdgeSwipe({
    canGoBack: stage > 1,
    // Forward only where the footer button would also allow it, so a swipe
    // can never skip a step the flow still needs answered.
    canGoForward: stage < 3 && canContinue,
    onBack: goBack,
    onForward: goForward,
  })
  const peerStage =
    swipePeer === "prev" ? stage - 1 : swipePeer === "next" ? stage + 1 : null
  const viewKey =
    view.type === "workout-detail"
      ? `${view.type}-${view.workoutId}`
      : view.type

  return (
    <div className="min-h-(--app-viewport-height) bg-(--app-shell) text-foreground">
      <HapticLayer />
      <SettingsEffects />
      <SvgFilterDefs />
      <main className="app-shell-frame relative mx-auto flex h-(--app-viewport-height) w-full touch-pan-y flex-col overflow-hidden bg-(--app-shell) sm:max-w-[430px]">
        <AppDrawerHost>
          <div
            className="t-app-page flex min-h-0 flex-1 flex-col"
            data-direction={viewDirection}
            key={viewKey}
          >
            {view.type === "workouts" && (
              <WorkoutsPage
                onCreate={() => startExerciseFlow()}
                onSelect={(workout) =>
                  navigate({ type: "workout-detail", workoutId: workout.id })
                }
                onSettings={() => navigate({ type: "settings" })}
              />
            )}

            {view.type === "settings" && (
              <SwipeBackPage
                onBack={() => navigate({ type: "workouts" }, "back")}
              >
                <SettingsPage
                  onBack={() => navigate({ type: "workouts" }, "back")}
                  onDataCleared={() => navigate({ type: "workouts" }, "back")}
                />
              </SwipeBackPage>
            )}

            {view.type === "workout-detail" && (
              <SwipeBackPage
                onBack={() => navigate({ type: "workouts" }, "back")}
              >
                <WorkoutDetailPage
                  onAddExercise={() => startExerciseFlow(view.workoutId)}
                  onBack={() => navigate({ type: "workouts" }, "back")}
                  onCopied={(workoutId) =>
                    navigate({ type: "workout-detail", workoutId })
                  }
                  onDeleted={() => navigate({ type: "workouts" }, "back")}
                  onOpenExercise={openDetail}
                  workoutId={view.workoutId}
                />
              </SwipeBackPage>
            )}

            {view.type === "flow" && (
              <AppScreen bottomControls>
                <AppSurface>
                  <AppShellHeader
                    above={<FlowProgress stage={stage} />}
                    left={
                      <AppHeaderButton
                        aria-label={
                          stage === 1 ? "Back to workouts" : "Previous stage"
                        }
                        onClick={() => {
                          if (stage === 1) {
                            triggerHaptic("medium")
                            navigate({ type: "workouts" }, "back")
                          } else {
                            goBack()
                          }
                        }}
                      >
                        <ChevronLeft className="size-5" />
                      </AppHeaderButton>
                    }
                    right={
                      <AppHeaderButton
                        aria-label="My workouts"
                        onClick={() => {
                          triggerHaptic("medium")
                          navigate({ type: "workouts" }, "back")
                        }}
                      >
                        <Home className="size-5" />
                      </AppHeaderButton>
                    }
                    scrollRef={
                      stage === 2
                        ? equipmentScrollRef
                        : stage === 3
                          ? exercisesScrollRef
                          : undefined
                    }
                    title={<StageHeading stage={stage} />}
                  />

                  <div
                    className="app-stage-frame t-page-slide min-h-0 flex-1"
                    data-dragging={swipeDragging ? "true" : undefined}
                    data-page={stage}
                    ref={swipeContainerRef}
                    style={
                      swipeDragging
                        ? ({
                            "--drag-x": `${swipeOffset}px`,
                          } as React.CSSProperties)
                        : undefined
                    }
                    {...swipeHandlers}
                  >
                    <section
                      aria-hidden={stage !== 1}
                      aria-label="Choose muscles"
                      className="t-page px-[clamp(0.75rem,4vw,1.25rem)] pt-[clamp(0.75rem,2vh,1.25rem)] pb-[clamp(0.75rem,2vh,1.25rem)]"
                      data-drag-peer={peerStage === 1 ? "true" : undefined}
                      data-page-id="1"
                      inert={stage !== 1}
                    >
                      <div className="relative h-full min-h-0">
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
                            onSideChange={setBodySide}
                            onToggle={toggleMuscleWithHaptic}
                            selectedMuscles={selectedMuscles}
                            showFlipButton={false}
                            side={bodySide}
                          />
                        </div>
                      </div>
                    </section>

                    <section
                      aria-hidden={stage !== 2}
                      aria-label="Choose equipment"
                      className="app-scroll-content t-page overflow-y-auto px-5 pt-4 pb-20"
                      data-drag-peer={peerStage === 2 ? "true" : undefined}
                      data-page-id="2"
                      inert={stage !== 2}
                      ref={equipmentScrollRef}
                      tabIndex={-1}
                    >
                      <div className="grid grid-cols-2 gap-3">
                        {EQUIPMENT_OPTIONS.map((equipment) => {
                          const checked = selectedEquipment.includes(equipment)
                          return (
                            <button
                              aria-checked={checked}
                              className={`interactive-spring group relative overflow-hidden rounded-3xl border bg-card text-left shadow-sm shadow-black/10 transition-[border-color,box-shadow] duration-300 ease-[var(--ease-smooth-out)] ${
                                checked
                                  ? "border-primary/75 shadow-[0_0_0_1px_color-mix(in_oklch,var(--primary)_30%,transparent)]"
                                  : "border-border"
                              }`}
                              key={equipment}
                              onClick={() =>
                                toggleEquipmentWithHaptic(equipment)
                              }
                              role="checkbox"
                              type="button"
                            >
                              <span className="relative block aspect-[1.18] overflow-hidden bg-[#161618]">
                                <img
                                  alt=""
                                  className="h-full w-full object-cover saturate-[1.65] transition-transform duration-250 ease-[var(--ease-smooth-out)]"
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
                                className="pointer-events-none absolute top-2.5 right-2.5 size-8"
                              />
                            </button>
                          )
                        })}
                      </div>
                    </section>

                    <section
                      aria-hidden={stage !== 3}
                      aria-label="Matching exercises"
                      className="app-scroll-content t-page overflow-y-auto px-5 pt-4 pb-6"
                      data-drag-peer={peerStage === 3 ? "true" : undefined}
                      data-page-id="3"
                      inert={stage !== 3}
                      ref={exercisesScrollRef}
                      tabIndex={-1}
                    >
                      {visibleExercises.length === 0 ? (
                        <div className="flex min-h-[20rem] flex-col items-center justify-center gap-3 text-center">
                          <SearchX className="size-7 text-[color-mix(in_oklch,var(--muted-foreground),var(--background)_35%)]" />
                          <p className="max-w-[16rem] text-base text-muted-foreground">
                            {search.trim()
                              ? `No exercises match "${search.trim()}".`
                              : favoritesOnly
                                ? "No favorites yet. Tap the heart on an exercise to save it here."
                                : "0 exercises"}
                          </p>
                        </div>
                      ) : (
                        <>
                          <div
                            className="t-stagger is-shown grid grid-cols-2 gap-3.5"
                            data-testid="exercise-results"
                          >
                            {pagedExercises.map((exercise, index) => (
                              <Fragment key={exercise.id}>
                                {index === supportingIndex && (
                                  <h2 className="col-span-2 flex items-center gap-3 pt-3 pb-0.5 text-xs font-medium tracking-wide text-muted-foreground uppercase">
                                    <span className="h-px flex-1 bg-border" />
                                    Also works these muscles
                                    <span className="h-px flex-1 bg-border" />
                                  </h2>
                                )}
                                <ExerciseCard
                                  exercise={exercise}
                                  index={index}
                                  onOpenDetail={openDetail}
                                  onToggleSelect={toggleSelected}
                                  selectMode={selectMode}
                                  selected={selectedIds.includes(exercise.id)}
                                />
                              </Fragment>
                            ))}
                          </div>
                          {hasMoreExercises && (
                            <>
                              <div className="flex justify-center py-6">
                                <MatrixLoader
                                  label="Loading more exercises"
                                  style={
                                    {
                                      "--matrix-dot": "3px",
                                      "--matrix-gap": "3px",
                                    } as CSSProperties
                                  }
                                  variant="scan"
                                />
                              </div>
                              <div
                                aria-hidden="true"
                                className="h-1"
                                data-testid="load-more-sentinel"
                                ref={loadMoreSentinelRef}
                              />
                            </>
                          )}
                        </>
                      )}
                    </section>
                  </div>

                  {stage === 2 ? (
                    <div className="app-surface-bottom-dock equipment-presets-dock">
                      <EquipmentPresets className="px-5" />
                    </div>
                  ) : null}
                </AppSurface>

                <AppControls>
                  {stage === 3 && searchOpen ? (
                    <div className="relative flex gap-2.5">
                      <ExerciseSearch onChange={setSearch} value={search} />
                      <Button
                        aria-label="Close search"
                        onClick={toggleSearch}
                        size="icon-cta"
                        variant="secondary"
                      >
                        <X className="size-5" />
                      </Button>
                    </div>
                  ) : (
                    <div className="relative flex gap-2.5">
                      {stage === 1 ? (
                        <Button
                          aria-label={`Show ${bodySide === "front" ? "back" : "front"}`}
                          onClick={() => {
                            triggerHaptic("selection")
                            setBodySide((side) =>
                              side === "front" ? "back" : "front"
                            )
                          }}
                          size="icon-cta"
                          variant="secondary"
                        >
                          <FlipHorizontal2 className="size-5" />
                        </Button>
                      ) : null}
                      {stage === 1 && selectedMuscles.length > 0 ? (
                        <Button
                          aria-label="Clear muscle selection"
                          onClick={() => {
                            triggerHaptic("selection")
                            setMuscles([])
                          }}
                          size="icon-cta"
                          variant="secondary"
                        >
                          <X className="size-5" />
                        </Button>
                      ) : null}
                      {stage === 2 && selectedEquipment.length > 0 ? (
                        <Button
                          aria-label="Clear equipment selection"
                          onClick={() => {
                            triggerHaptic("selection")
                            setEquipment([])
                          }}
                          size="icon-cta"
                          variant="secondary"
                        >
                          <X className="size-5" />
                        </Button>
                      ) : null}
                      {stage === 3 && selectMode ? (
                        <Button
                          aria-label="Cancel selection"
                          onClick={cancelSelectMode}
                          size="icon-cta"
                          variant="secondary"
                        >
                          <X />
                        </Button>
                      ) : null}
                      {stage === 3 ? (
                        <Button
                          aria-label="Search exercises"
                          onClick={toggleSearch}
                          size="icon-cta"
                          variant="secondary"
                        >
                          <Search className="size-5" />
                        </Button>
                      ) : null}
                      {stage === 3 ? (
                        <LikeButton
                          animated={false}
                          aria-label={
                            favoritesOnly
                              ? "Show all exercises"
                              : "Show favorites only"
                          }
                          className={`interactive-spring grid size-(--app-controls-height) shrink-0 place-items-center rounded-2xl border ${
                            favoritesOnly
                              ? "border-primary bg-[color-mix(in_oklch,var(--card),var(--primary)_22%)] text-primary active:border-(--primary-softer)"
                              : "border-border bg-card text-primary active:bg-card/90"
                          }`}
                          iconClassName="size-5"
                          liked={favoritesOnly}
                          onClick={() => {
                            triggerHaptic("selection")
                            setFavoritesOnly((value) => !value)
                          }}
                        />
                      ) : null}
                      {stage < 3 ? (
                        <Button
                          size="cta"
                          className="min-w-0 flex-1"
                          disabled={!canContinue}
                          onClick={goForward}
                        >
                          {stage === 1
                            ? "Choose equipment"
                            : `Show exercises (${exercises.length})`}
                        </Button>
                      ) : selectMode ? (
                        <Button
                          size="cta"
                          className="min-w-0 flex-1"
                          disabled={selectedIds.length === 0}
                          onClick={addSelectionToWorkout}
                        >
                          Add to workout
                          {selectedIds.length > 0 && ` (${selectedIds.length})`}
                        </Button>
                      ) : (
                        <Button
                          size="cta"
                          className="min-w-0 flex-1"
                          onClick={() => {
                            triggerHaptic("medium")
                            setSelectMode(true)
                          }}
                        >
                          Select
                        </Button>
                      )}
                    </div>
                  )}
                </AppControls>
              </AppScreen>
            )}
          </div>

          <ExerciseDetailDrawer
            exercise={detailExercise}
            onSelectExercise={
              view.type === "flow" ? selectExerciseFromDetail : undefined
            }
            onOpenChange={setDetailOpen}
            open={detailOpen}
            selected={
              detailExercise ? selectedIds.includes(detailExercise.id) : false
            }
          />

          <WorkoutFormDrawer
            initialExerciseIds={workoutFormSeed.exerciseIds}
            key={workoutFormGeneration}
            onOpenChange={setWorkoutFormOpen}
            onSaved={(workoutId) => {
              cancelSelectMode()
              setPreferredWorkoutId(null)
              navigate({ type: "workout-detail", workoutId })
            }}
            open={workoutFormOpen}
            workout={workoutFormSeed.workout}
          />

          <WorkoutDestinationDrawer
            exerciseIds={selectedIds}
            onAddToExisting={(workoutId) => {
              const workout = useWorkouts
                .getState()
                .workouts.find((item) => item.id === workoutId)
              if (!workout) return
              useWorkouts.getState().updateWorkout(workoutId, {
                exerciseIds: [
                  ...new Set([...workout.exerciseIds, ...selectedIds]),
                ],
              })
              setWorkoutDestinationOpen(false)
              cancelSelectMode()
              setPreferredWorkoutId(null)
              navigate({ type: "workout-detail", workoutId })
            }}
            onCreateNew={() => {
              setWorkoutDestinationOpen(false)
              openWorkoutForm({ exerciseIds: selectedIds })
            }}
            onOpenChange={setWorkoutDestinationOpen}
            open={workoutDestinationOpen}
            preferredWorkoutId={preferredWorkoutId}
          />
        </AppDrawerHost>
      </main>
    </div>
  )
}

export default App
