import {
  Fragment,
  useCallback,
  useEffect,
  useMemo,
  useReducer,
  useRef,
  useState,
  type CSSProperties,
} from "react"
import {
  ArrowUp,
  ChevronLeft,
  FlipHorizontal2,
  Plus,
  Search,
  SearchX,
  Sparkles,
  X,
} from "lucide-react"

import { AnimatedNumber } from "@/components/animated-number"
import { Rauta } from "@/components/rauta"
import { AppControlMorph, TextSwap } from "@/components/app-morph"
import {
  AppControlButton,
  AppControls,
  AppHeaderButton,
  AppScreen,
  AppShell,
  AppShellHeader,
  AppSurface,
  PageLayerProvider,
} from "@/components/app-shell"
import { BodyMap } from "@/components/body-map"
import { EquipmentGrid } from "@/components/equipment-grid"
import {
  EquipmentPresetEditor,
  EquipmentPresets,
} from "@/components/equipment-presets"
import { ExerciseCard } from "@/components/exercise-card"
import { ExerciseSearch } from "@/components/exercise-search"
import { FlowProgress } from "@/components/flow-progress"
import { HapticLayer } from "@/components/haptic-layer"
import { LikeButton } from "@/components/like-button"
import { MorphingActionSlot } from "@/components/morphing-action-slot"
import {
  HealthEligibilityPage,
  MusclePrioritiesPage,
  OnboardingPage,
  ProfileBasicsPage,
  EquipmentLoadPage,
  ProfileEquipmentPage,
  TrainingPreferencesPage,
} from "@/components/profile-pages"
import {
  EquipmentPresetPage,
  ExerciseAlternativesPage,
  ExerciseDetailPage,
  WorkoutDestinationPage,
  WorkoutFormPage,
} from "@/components/secondary-pages"
import { PlanWeekPage } from "@/components/plan-week-page"
import { SettingsEffects } from "@/components/settings-effects"
import { SettingsPage } from "@/components/settings-page"
import { SvgFilterDefs } from "@/components/svg-filters"
import { Button } from "@/components/ui/button"
import { DotPattern } from "@/components/ui/dot-pattern"
import { MatrixLoader } from "@/components/ui/matrix-loader"
import { WorkoutDetailPage } from "@/components/workout-detail-page"
import { WorkoutsPage } from "@/components/workouts-page"
import { useEdgeSwipe } from "@/hooks/use-edge-swipe"
import { useLoadMoreOnScroll } from "@/hooks/use-load-more-on-scroll"
import { clearAllGymLibData, hasMeaningfulGymLibData } from "@/lib/app-backup"
import {
  EXERCISE_PAGE_SIZE,
  EXERCISES,
  EXERCISES_BY_ID,
  equipmentForMuscles,
  filterExercises,
} from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { ensureEngineWorkout, proposeEngineWorkout } from "@/lib/engine-workout"
import { syncICloudNow } from "@/lib/icloud-sync"
import { isNative } from "@/lib/native"
import { substituteRunningPlannedExercise } from "@/lib/planned-substitution"
import {
  replacementIds,
  buildTrainingRequest,
  trainingIndex,
} from "@/lib/training-workflow"
import {
  buildTrainingEngineInputs,
  toEngineEquipment,
} from "@/lib/training-engine-adapter"
import { rankExerciseCandidates } from "@/training/planning/rank"
import { useTrainingRecords } from "@/store/use-training-records"
import {
  refreshFutureWorkoutPrescriptions,
  deleteScheduledWorkout,
  substituteScheduledPlannedExercise,
  updateScheduledWorkoutExercises,
} from "@/lib/training-edits"
import { cn } from "@/lib/utils"
import {
  appNavigationReducer,
  pageHasControls,
  type AppPage,
  type AppPageEntry,
} from "@/store/app-navigation"
import {
  DEFAULT_APP_SESSION,
  readAppSession,
  writeAppSession,
  type AppSession,
} from "@/store/app-session"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useFavorites } from "@/store/use-favorites"
import { useFilters } from "@/store/use-filters"
import { useTrainingProfile } from "@/store/use-training-profile"
import { useWorkouts } from "@/store/use-workouts"
import type { MuscleId } from "@/types"

type PickerStage = 1 | 2 | 3

const STAGE_LABELS: Record<PickerStage, string> = {
  1: "Muscles",
  2: "Equipment",
  3: "Exercises",
}

/** How long a popped page stays mounted after the navigation that removed it,
 *  so it has something to dissolve during. Matches `--page-exit-dur` plus a
 *  frame of slack. */
const PAGE_EXIT_MS = 240

let pageSequence = 0

function createPageEntry(page: AppPage): AppPageEntry {
  pageSequence += 1
  return { id: `page-${pageSequence}`, page }
}

function stageForPage(page: AppPage): PickerStage | null {
  if (page.type === "muscles") return 1
  if (page.type === "equipment") return 2
  if (page.type === "exercises") return 3
  return null
}

function StageHeading({ stage }: { stage: PickerStage }) {
  return <TextSwap>{STAGE_LABELS[stage]}</TextSwap>
}

function StageSubtitle({
  exerciseCount,
  selectMode,
  selectedEquipmentCount,
  selectedExercisesCount,
  selectedMusclesCount,
  stage,
}: {
  exerciseCount: number
  selectMode: boolean
  selectedEquipmentCount: number
  selectedExercisesCount: number
  selectedMusclesCount: number
  stage: PickerStage
}) {
  if (stage === 1 && selectedMusclesCount > 0) {
    return (
      <span>
        <AnimatedNumber value={selectedMusclesCount} /> selected
      </span>
    )
  }

  if (stage === 2 && selectedEquipmentCount > 0 && exerciseCount > 0) {
    return (
      <span>
        <AnimatedNumber value={exerciseCount} />{" "}
        {exerciseCount === 1 ? "exercise" : "exercises"}
      </span>
    )
  }

  if (stage === 3 && selectMode) {
    return (
      <span>
        <AnimatedNumber value={selectedExercisesCount} /> selected
      </span>
    )
  }

  return null
}

/** First-run setup is offered to a genuinely new install only. Someone whose
 *  library, presets or settings already exist has been using RAUTA for a
 *  while; a wizard in front of their workouts would be an ambush, and every
 *  answer it asks for is in Settings anyway. */
function initialPages(session: AppSession): AppPage[] {
  const { onboarding } = useTrainingProfile.getState()
  if (!onboarding.completed && !hasMeaningfulGymLibData())
    return [{ type: "onboarding" }]
  return isNative() ? DEFAULT_APP_SESSION.pages : session.pages
}

export function App() {
  const [initialSession] = useState(readAppSession)
  const [navigation, dispatchNavigation] = useReducer(
    appNavigationReducer,
    initialSession,
    (session) => ({
      direction: "forward" as const,
      pages: initialPages(session).map(createPageEntry),
    })
  )
  const pages = navigation.pages
  const pagesRef = useRef(pages)
  // Popped pages outlive their removal by one transition. Worked out during
  // render rather than in an effect: an effect would run after React had
  // already detached the layer, so the page would blink out and be rebuilt
  // from scratch — losing its scroll position and, with it, the very frame
  // the fade is supposed to start from.
  const [dissolving, setDissolving] = useState<{
    entries: AppPageEntry[]
    seen: AppPageEntry[]
  }>({ entries: [], seen: pages })

  if (dissolving.seen !== pages) {
    const live = new Set(pages.map((entry) => entry.id))
    setDissolving((current) => ({
      entries: [
        ...current.entries,
        ...current.seen.filter((entry) => !live.has(entry.id)),
      ],
      seen: pages,
    }))
  }

  const exitingEntries = dissolving.entries

  const focusOrigins = useRef(new Map<string, HTMLElement>())
  const [countdownOpen, setCountdownOpen] = useState(false)
  const [favoritesOnly, setFavoritesOnly] = useState(false)
  const [showBackToTop, setShowBackToTop] = useState(false)

  useEffect(() => {
    pagesRef.current = pages
  }, [pages])

  useEffect(() => {
    if (exitingEntries.length === 0) return
    const timeout = window.setTimeout(
      () => setDissolving((current) => ({ ...current, entries: [] })),
      PAGE_EXIT_MS
    )
    return () => window.clearTimeout(timeout)
  }, [exitingEntries])

  const focusPage = useCallback((entryId: string) => {
    requestAnimationFrame(() => {
      document
        .querySelector<HTMLElement>(`[data-page-entry="${entryId}"] h1`)
        ?.focus({ preventScroll: true })
    })
  }, [])

  const pushPage = useCallback(
    (page: AppPage) => {
      if (pagesRef.current.at(-1)?.page.type === "exercises") {
        setFavoritesOnly(false)
      }
      const entry = createPageEntry(page)
      const activeElement = document.activeElement
      if (activeElement instanceof HTMLElement) {
        focusOrigins.current.set(entry.id, activeElement)
      }
      dispatchNavigation({ type: "push", entry })
      focusPage(entry.id)
    },
    [focusPage]
  )

  const popPage = useCallback(() => {
    const current = pagesRef.current
    if (current.length <= 1) return
    const leaving = current[current.length - 1]
    if (leaving.page.type === "exercises") setFavoritesOnly(false)
    dispatchNavigation({ type: "pop" })
    const origin = focusOrigins.current.get(leaving.id)
    focusOrigins.current.delete(leaving.id)
    requestAnimationFrame(() => origin?.focus({ preventScroll: true }))
  }, [])

  const replacePage = useCallback(
    (page: AppPage) => {
      if (pagesRef.current.at(-1)?.page.type === "exercises") {
        setFavoritesOnly(false)
      }
      const entry = createPageEntry(page)
      dispatchNavigation({ type: "replace", entry })
      focusPage(entry.id)
    },
    [focusPage]
  )

  const resetPages = useCallback(
    (nextPages: AppPage[]) => {
      const entries = nextPages.map(createPageEntry)
      const active = entries.at(-1)
      if (!active) return
      setFavoritesOnly(false)
      focusOrigins.current.clear()
      dispatchNavigation({ type: "reset", entries })
      focusPage(active.id)
    },
    [focusPage]
  )

  const activeEntry = pages.at(-1) ?? pages[0]
  const activePage = activeEntry.page

  const selectedMuscles = useFilters((state) => state.selectedMuscles)
  const muscleDotIntensity = Math.min(selectedMuscles.length / 6, 1)
  const selectedEquipment = useFilters((state) => state.selectedEquipment)
  const toggleMuscle = useFilters((state) => state.toggleMuscle)
  const toggleEquipment = useFilters((state) => state.toggleEquipment)
  const setMuscles = useFilters((state) => state.setMuscles)
  const setEquipment = useFilters((state) => state.setEquipment)
  const resetFilters = useFilters((state) => state.reset)
  const favoriteIds = useFavorites((state) => state.favoriteIds)
  const workouts = useWorkouts((state) => state.workouts)

  const [selectMode, setSelectMode] = useState(initialSession.selectMode)
  const [selectedIds, setSelectedIds] = useState<string[]>(
    initialSession.selectedIds
  )
  const [search, setSearch] = useState("")
  const [searchOpen, setSearchOpen] = useState(false)
  const [presetEditorOpen, setPresetEditorOpen] = useState(false)
  const [bodySide, setBodySide] = useState<"front" | "back">("front")
  const equipmentScrollRef = useRef<HTMLElement>(null)
  const availableEquipment = useMemo(
    () => equipmentForMuscles(selectedMuscles),
    [selectedMuscles]
  )

  const trainingProfile = useTrainingProfile((state) => state.profile)
  const trainingData = useTrainingRecords((state) => state.data)
  const equipmentLoadIncrements = useFilters(
    (state) => state.equipmentLoadIncrements
  )
  const exercises = useMemo(() => {
    // The adapter reads these values through getState(); name the subscribed
    // snapshots here so React refreshes ranking when they change.
    void equipmentLoadIncrements
    void trainingData
    void trainingProfile
    void workouts
    const request = buildTrainingRequest(
      buildTrainingEngineInputs({
        availableEquipment: toEngineEquipment(selectedEquipment),
        preferredExerciseIds: favoriteIds,
      }),
      new Date().toISOString()
    )
    const ranked = rankExerciseCandidates(request, {
      index: trainingIndex(),
      focus: selectedMuscles,
      selectedExerciseIds: selectedIds,
    })
    const scores = new Map(
      ranked.map((item, index) => [item.exerciseId, index])
    )
    return filterExercises(EXERCISES, selectedMuscles, selectedEquipment).sort(
      (a, b) =>
        (selectedIds.includes(a.id) ? -1 : (scores.get(a.id) ?? Infinity)) -
        (selectedIds.includes(b.id) ? -1 : (scores.get(b.id) ?? Infinity))
    )
  }, [
    selectedEquipment,
    selectedMuscles,
    equipmentLoadIncrements,
    trainingData,
    trainingProfile,
    workouts,
    favoriteIds,
    selectedIds,
  ])

  const visibleExercises = useMemo(() => {
    const shortlist = favoritesOnly
      ? exercises.filter((exercise) => favoriteIds.includes(exercise.id))
      : exercises
    const query = search.trim().toLowerCase()
    if (!query) return shortlist
    return shortlist.filter((exercise) =>
      exercise.name.toLowerCase().includes(query)
    )
  }, [exercises, favoriteIds, favoritesOnly, search])

  const {
    hasMore: hasMoreExercises,
    rootRef: exercisesScrollRef,
    sentinelRef: loadMoreSentinelRef,
    visibleCount,
  } = useLoadMoreOnScroll(
    visibleExercises.length,
    EXERCISE_PAGE_SIZE,
    activePage.type === "exercises"
  )

  useEffect(() => {
    if (activePage.type !== "exercises") return

    const scroller = exercisesScrollRef.current
    if (!scroller) return
    let frame: number | null = null
    const update = () => {
      frame = null
      setShowBackToTop(
        scroller.scrollTop > Math.max(480, scroller.clientHeight)
      )
    }
    const onScroll = () => {
      if (frame === null) frame = requestAnimationFrame(update)
    }

    update()
    scroller.addEventListener("scroll", onScroll, { passive: true })
    return () => {
      if (frame !== null) cancelAnimationFrame(frame)
      scroller.removeEventListener("scroll", onScroll)
    }
  }, [activePage.type, exercisesScrollRef])

  const pagedExercises = visibleExercises.slice(0, visibleCount)

  const persistedPages = pages
  const appSession = useMemo(
    () => ({
      detailExerciseId:
        activePage.type === "exercise-detail" ? activePage.exerciseId : null,
      pages: persistedPages.map((entry) => entry.page),
      selectedIds,
      selectMode,
    }),
    [activePage, persistedPages, selectedIds, selectMode]
  )
  const latestSession = useRef(appSession)

  useEffect(() => {
    writeAppSession(appSession)
    latestSession.current = appSession
  }, [appSession])

  useEffect(() => {
    const saveBeforeSuspending = () => writeAppSession(latestSession.current)
    window.addEventListener("pagehide", saveBeforeSuspending)
    document.addEventListener("visibilitychange", saveBeforeSuspending)
    return () => {
      window.removeEventListener("pagehide", saveBeforeSuspending)
      document.removeEventListener("visibilitychange", saveBeforeSuspending)
    }
  }, [])

  const startExerciseFlow = useCallback(
    (preferredWorkoutId?: string) => {
      triggerHaptic("medium")
      resetFilters()
      useFilters.getState().setEquipment(useFilters.getState().gymEquipment)
      setSearch("")
      setSearchOpen(false)
      setPresetEditorOpen(false)
      setBodySide("front")
      setSelectMode(false)
      setSelectedIds([])
      pushPage({
        type: "muscles",
        preferredWorkoutId: preferredWorkoutId ?? null,
      })
    },
    [pushPage, resetFilters]
  )

  const cancelSelectMode = useCallback(() => {
    triggerHaptic("selection")
    setSelectMode(false)
    setSelectedIds([])
  }, [])

  const toggleSelected = useCallback((id: string) => {
    triggerHaptic("selection")
    setSelectedIds((ids) =>
      ids.includes(id) ? ids.filter((current) => current !== id) : [...ids, id]
    )
  }, [])

  const addSelectionToWorkout = useCallback(
    (preferredWorkoutId?: string | null) => {
      if (selectedIds.length === 0) return
      triggerHaptic("medium")
      pushPage({
        type: "workout-destination",
        preferredWorkoutId: preferredWorkoutId ?? null,
      })
    },
    [pushPage, selectedIds.length]
  )

  const toggleSearch = useCallback(() => {
    triggerHaptic("medium")
    if (searchOpen) setSearch("")
    setSearchOpen((value) => !value)
  }, [searchOpen])

  const { containerRef, handlers } = useEdgeSwipe({
    canGoBack: pages.length > 1,
    canGoForward: false,
    onBack: popPage,
    onForward: () => undefined,
  })

  const commandBandVisible = !countdownOpen && pageHasControls(activePage)

  const exitingIds = useMemo(
    () => new Set(exitingEntries.map((entry) => entry.id)),
    [exitingEntries]
  )
  const renderedEntries = useMemo(
    () => [...pages, ...exitingEntries],
    [exitingEntries, pages]
  )

  return (
    <div className="min-h-(--app-viewport-height) bg-(--app-shell) text-foreground">
      <HapticLayer />
      <SettingsEffects />
      <SvgFilterDefs />
      <AppShell commandsVisible={commandBandVisible}>
        <div
          className="app-page-stack"
          data-direction={navigation.direction}
          ref={containerRef}
          {...handlers}
        >
          {renderedEntries.map((entry) => {
            const page = entry.page
            const active = entry.id === activeEntry.id
            const exiting = !active && exitingIds.has(entry.id)
            const interactive = active
            const stage = stageForPage(page)
            let content = null

            if (page.type === "workouts") {
              content = (
                <WorkoutsPage
                  onCreate={() => startExerciseFlow()}
                  onCreatePlan={(sourceProgramId) => {
                    triggerHaptic("medium")
                    pushPage({ type: "plan-week", sourceProgramId })
                  }}
                  onDelete={deleteScheduledWorkout}
                  onSelect={(workout) => {
                    ensureEngineWorkout(workout.id)
                    pushPage({ type: "workout-detail", workoutId: workout.id })
                  }}
                  onSettings={() => pushPage({ type: "settings" })}
                />
              )
            } else if (page.type === "settings") {
              content = (
                <SettingsPage
                  onBack={popPage}
                  onClearData={() => {
                    clearAllGymLibData()
                    void syncICloudNow()
                    resetPages([{ type: "workouts" }])
                  }}
                  onOpenProfilePage={(type) => pushPage({ type })}
                />
              )
            } else if (page.type === "plan-week") {
              content = (
                <PlanWeekPage
                  onBack={popPage}
                  // The plan is the destination, not the page that made it:
                  // finishing lands back on the workout list it now fills.
                  onCreated={() => resetPages([{ type: "workouts" }])}
                  onOpenProfilePage={(type) => pushPage({ type })}
                  sourceProgramId={page.sourceProgramId}
                />
              )
            } else if (page.type === "onboarding") {
              content = (
                <OnboardingPage
                  onFinish={() => resetPages([{ type: "workouts" }])}
                />
              )
            } else if (page.type === "profile-basics") {
              content = <ProfileBasicsPage onBack={popPage} />
            } else if (page.type === "profile-training") {
              content = <TrainingPreferencesPage onBack={popPage} />
            } else if (page.type === "profile-health") {
              content = <HealthEligibilityPage onBack={popPage} />
            } else if (page.type === "profile-equipment") {
              content = (
                <ProfileEquipmentPage
                  onBack={popPage}
                  onOpenLoadSteps={() =>
                    pushPage({ type: "profile-load-steps" })
                  }
                />
              )
            } else if (page.type === "profile-load-steps") {
              content = <EquipmentLoadPage onBack={popPage} />
            } else if (page.type === "profile-priorities") {
              content = <MusclePrioritiesPage onBack={popPage} />
            } else if (page.type === "workout-detail") {
              content = (
                <WorkoutDetailPage
                  onAddExercise={() => startExerciseFlow(page.workoutId)}
                  onBack={popPage}
                  onDelete={() => {
                    deleteScheduledWorkout(page.workoutId)
                    resetPages([{ type: "workouts" }])
                  }}
                  onDiscard={() => useActiveWorkout.getState().cancel()}
                  onFinish={() => {
                    useActiveWorkout.getState().finish()
                    refreshFutureWorkoutPrescriptions()
                  }}
                  onCopied={(workoutId) =>
                    replacePage({ type: "workout-detail", workoutId })
                  }
                  onCountdownChange={setCountdownOpen}
                  onFindAlternative={(exercise) =>
                    pushPage({
                      type: "exercise-alternatives",
                      exerciseId: exercise.id,
                      workoutId: page.workoutId,
                    })
                  }
                  onOpenExercise={(exercise) =>
                    pushPage({
                      type: "exercise-detail",
                      exerciseId: exercise.id,
                    })
                  }
                  workoutId={page.workoutId}
                />
              )
            } else if (stage !== null) {
              const preferredWorkoutId =
                page.type === "muscles" ||
                page.type === "equipment" ||
                page.type === "exercises"
                  ? (page.preferredWorkoutId ?? null)
                  : null
              const canContinue =
                stage === 1
                  ? selectedMuscles.length > 0
                  : selectedEquipment.length > 0 && exercises.length > 0

              content = (
                <AppScreen bottomControls>
                  <AppSurface>
                    <AppShellHeader
                      above={<FlowProgress stage={stage} />}
                      left={
                        <AppHeaderButton
                          aria-label="Previous page"
                          onClick={popPage}
                        >
                          <ChevronLeft className="size-5" />
                        </AppHeaderButton>
                      }
                      right={null}
                      scrollRef={
                        stage === 2
                          ? equipmentScrollRef
                          : stage === 3
                            ? exercisesScrollRef
                            : undefined
                      }
                      subtitle={
                        (stage === 1 && selectedMuscles.length > 0) ||
                        (stage === 2 &&
                          selectedEquipment.length > 0 &&
                          exercises.length > 0) ||
                        (stage === 3 && selectMode) ? (
                          <StageSubtitle
                            exerciseCount={exercises.length}
                            key={stage}
                            selectMode={selectMode}
                            selectedEquipmentCount={selectedEquipment.length}
                            selectedExercisesCount={selectedIds.length}
                            selectedMusclesCount={selectedMuscles.length}
                            stage={stage}
                          />
                        ) : null
                      }
                      title={<StageHeading stage={stage} />}
                    />

                    {stage === 1 ? (
                      <section
                        aria-label="Choose muscles"
                        className="min-h-0 flex-1 px-[clamp(0.75rem,4vw,1rem)] pt-[calc(4.25rem+env(safe-area-inset-top)+0.75rem)] pb-[clamp(0.75rem,2vh,1.25rem)]"
                      >
                        <div className="relative h-full min-h-0">
                          <DotPattern
                            className="[mask-image:radial-gradient(ellipse_at_center,black_28%,transparent_80%)] transition-[fill,fill-opacity] duration-500"
                            cr={1.1}
                            cx={9}
                            cy={9}
                            height={18}
                            style={{
                              fill: `color-mix(in oklch, var(--muted-foreground), var(--primary) ${25 + muscleDotIntensity * 50}%)`,
                              fillOpacity: 0.36 + muscleDotIntensity * 0.28,
                            }}
                            width={18}
                          />
                          <div className="relative z-10 h-full">
                            <BodyMap
                              onSideChange={setBodySide}
                              onToggle={(muscle: MuscleId) => {
                                triggerHaptic("selection")
                                toggleMuscle(muscle)
                              }}
                              selectedMuscles={selectedMuscles}
                              showFlipButton={false}
                              side={bodySide}
                            />
                          </div>
                        </div>
                      </section>
                    ) : null}

                    {stage === 2 ? (
                      <section
                        aria-label="Choose equipment"
                        className="app-scroll-content min-h-0 flex-1 overflow-y-auto px-(--app-content-inset) pt-[calc(4.25rem+env(safe-area-inset-top)+0.75rem)] pb-20"
                        ref={equipmentScrollRef}
                        tabIndex={-1}
                      >
                        <EquipmentGrid
                          onToggle={toggleEquipment}
                          options={availableEquipment}
                          selected={selectedEquipment}
                        />
                      </section>
                    ) : null}

                    {stage === 3 ? (
                      <section
                        aria-label="Matching exercises"
                        className={cn(
                          "app-scroll-content min-h-0 flex-1 overflow-y-auto px-(--app-content-inset) pt-[calc(4.25rem+env(safe-area-inset-top)+0.75rem)]",
                          searchOpen || selectMode ? "pb-28" : "pb-6"
                        )}
                        ref={exercisesScrollRef}
                        tabIndex={-1}
                      >
                        {visibleExercises.length === 0 ? (
                          <div className="flex min-h-[20rem] flex-col items-center justify-center gap-3 text-center">
                            <SearchX className="size-7 text-muted-foreground" />
                            <p className="max-w-[16rem] text-base text-muted-foreground">
                              {search.trim()
                                ? `Nothing matches "${search.trim()}". Try a shorter word — the search reads exercise names only.`
                                : favoritesOnly
                                  ? "No favorites yet. Tap the heart on an exercise to keep it here."
                                  : "Nothing uses every muscle and every piece of equipment you picked. Go back and drop one of them."}
                            </p>
                          </div>
                        ) : (
                          <>
                            <div
                              className="t-stagger is-shown grid grid-cols-2 gap-3.5"
                              data-testid="exercise-results"
                            >
                              {pagedExercises.map((exercise, exerciseIndex) => (
                                <Fragment key={exercise.id}>
                                  <ExerciseCard
                                    exercise={exercise}
                                    index={exerciseIndex}
                                    onOpenDetail={(candidate) => {
                                      triggerHaptic("light")
                                      pushPage({
                                        type: "exercise-detail",
                                        exerciseId: candidate.id,
                                      })
                                    }}
                                    onToggleSelect={toggleSelected}
                                    selectMode={selectMode}
                                    selected={selectedIds.includes(exercise.id)}
                                  />
                                </Fragment>
                              ))}
                            </div>
                            {hasMoreExercises ? (
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
                            ) : null}
                          </>
                        )}
                      </section>
                    ) : null}

                    {stage === 3 ? (
                      <button
                        aria-label="Back to top"
                        aria-hidden={!showBackToTop}
                        className="exercise-back-to-top interactive-spring"
                        data-visible={showBackToTop ? "true" : undefined}
                        disabled={!showBackToTop}
                        onClick={() => {
                          triggerHaptic("light")
                          exercisesScrollRef.current?.scrollTo({
                            behavior: window.matchMedia?.(
                              "(prefers-reduced-motion: reduce)"
                            ).matches
                              ? "auto"
                              : "smooth",
                            top: 0,
                          })
                        }}
                        tabIndex={showBackToTop ? 0 : -1}
                        type="button"
                      >
                        <ArrowUp className="size-5" />
                      </button>
                    ) : null}

                    {stage === 2 && !presetEditorOpen ? (
                      <div className="app-surface-bottom-dock equipment-presets-dock">
                        <EquipmentPresets className="px-(--app-content-inset)" />
                      </div>
                    ) : null}
                  </AppSurface>

                  <AppControls
                    transitionKey={`picker:${stage}:${selectMode}:${presetEditorOpen}:${selectedMuscles.length}:${selectedEquipment.length}`}
                  >
                    {stage === 2 && presetEditorOpen ? (
                      <div className="flex items-center gap-2.5">
                        <EquipmentPresetEditor
                          className="flex-1"
                          onSaved={() => setPresetEditorOpen(false)}
                        />
                        {/* The command the band was showing collapses into the
                            way out of the field that replaced it, rather than
                            vanishing and leaving a new circle in its place. */}
                        <AppControlMorph role="primary">
                          <AppControlButton
                            aria-label="Close preset editor"
                            onClick={() => setPresetEditorOpen(false)}
                          >
                            <X />
                          </AppControlButton>
                        </AppControlMorph>
                      </div>
                    ) : stage === 3 && searchOpen ? (
                      <div className="flex items-center gap-2.5">
                        <ExerciseSearch onChange={setSearch} value={search} />
                        <AppControlMorph role="primary">
                          <AppControlButton
                            aria-label="Close search"
                            onClick={toggleSearch}
                          >
                            <X />
                          </AppControlButton>
                        </AppControlMorph>
                      </div>
                    ) : (
                      <div className="relative flex min-w-0 items-center">
                        {stage === 1 ? (
                          <AppControlButton
                            aria-label={`Show ${bodySide === "front" ? "back" : "front"}`}
                            onClick={() => {
                              triggerHaptic("selection")
                              setBodySide((side) =>
                                side === "front" ? "back" : "front"
                              )
                            }}
                            className="mr-2.5"
                          >
                            <FlipHorizontal2 />
                          </AppControlButton>
                        ) : null}
                        {stage === 1 ? (
                          <MorphingActionSlot
                            visible={selectedMuscles.length > 0}
                          >
                            <AppControlButton
                              aria-label="Clear muscle selection"
                              onClick={() => setMuscles([])}
                            >
                              <X />
                            </AppControlButton>
                          </MorphingActionSlot>
                        ) : null}
                        {stage === 2 ? (
                          <MorphingActionSlot
                            visible={selectedEquipment.length > 0}
                          >
                            <AppControlButton
                              aria-label="Clear equipment selection"
                              onClick={() => setEquipment([])}
                            >
                              <X />
                            </AppControlButton>
                          </MorphingActionSlot>
                        ) : null}
                        {stage === 2 ? (
                          <AppControlMorph className="mr-2.5" role="preset">
                            <AppControlButton
                              aria-expanded={presetEditorOpen}
                              aria-label={
                                presetEditorOpen
                                  ? "Close preset editor"
                                  : "Create equipment preset"
                              }
                              disabled={selectedEquipment.length === 0}
                              onClick={() =>
                                setPresetEditorOpen((open) => !open)
                              }
                            >
                              <Plus />
                            </AppControlButton>
                          </AppControlMorph>
                        ) : null}
                        {stage === 3 ? (
                          <MorphingActionSlot visible={selectMode}>
                            <AppControlButton
                              aria-label="Cancel selection"
                              onClick={cancelSelectMode}
                            >
                              <X />
                            </AppControlButton>
                          </MorphingActionSlot>
                        ) : null}
                        {stage === 3 ? (
                          <MorphingActionSlot
                            visible={!selectMode && !preferredWorkoutId}
                          >
                            <AppControlButton
                              aria-label="Build workout with RAUTA"
                              className="mr-2.5"
                              onClick={() => {
                                try {
                                  const date = new Date()
                                    .toISOString()
                                    .slice(0, 10)
                                  const exerciseIds = proposeEngineWorkout({
                                    date,
                                    focusMuscles: selectedMuscles,
                                    availableEquipment:
                                      toEngineEquipment(selectedEquipment),
                                  })
                                  triggerHaptic("medium")
                                  pushPage({
                                    type: "workout-form",
                                    exerciseIds,
                                    workoutId: null,
                                    engineFocusMuscles: [...selectedMuscles],
                                  })
                                } catch {
                                  triggerHaptic("warning")
                                }
                              }}
                            >
                              <Sparkles />
                            </AppControlButton>
                          </MorphingActionSlot>
                        ) : null}
                        {stage === 3 ? (
                          <AppControlMorph className="mr-2.5" role="search">
                            <AppControlButton
                              aria-expanded={searchOpen}
                              aria-label={
                                searchOpen ? "Close search" : "Search exercises"
                              }
                              onClick={toggleSearch}
                            >
                              <Search />
                            </AppControlButton>
                          </AppControlMorph>
                        ) : null}
                        {stage === 3 ? (
                          <LikeButton
                            animated={false}
                            aria-label={
                              favoritesOnly
                                ? "Show all exercises"
                                : "Show favorites only"
                            }
                            className="interactive-spring mr-2.5 grid size-(--app-controls-height) shrink-0 place-items-center rounded-full border border-border bg-card text-primary active:bg-card/90 aria-pressed:bg-muted"
                            iconClassName="size-5"
                            liked={favoritesOnly}
                            onClick={() => setFavoritesOnly((value) => !value)}
                          />
                        ) : null}
                        {stage === 3 ? (
                          <AppControlMorph
                            className="app-command-fill"
                            role="primary"
                          >
                            <Button
                              aria-label={
                                selectMode ? "Add to workout" : "Select"
                              }
                              className="w-full"
                              disabled={selectMode && selectedIds.length === 0}
                              onClick={() => {
                                if (selectMode) {
                                  addSelectionToWorkout(preferredWorkoutId)
                                } else {
                                  setSelectMode(true)
                                }
                              }}
                              size="cta"
                            >
                              {selectMode ? "Add to workout" : "Select"}
                            </Button>
                          </AppControlMorph>
                        ) : null}
                        {stage < 3 ? (
                          <AppControlMorph
                            className="app-command-fill"
                            role="primary"
                          >
                            <Button
                              aria-label={
                                stage === 1
                                  ? "Choose equipment"
                                  : "Show exercises"
                              }
                              className="w-full"
                              disabled={!canContinue}
                              onClick={() => {
                                triggerHaptic("medium")
                                pushPage({
                                  type: stage === 1 ? "equipment" : "exercises",
                                  preferredWorkoutId,
                                })
                              }}
                              size="cta"
                            >
                              {stage === 1
                                ? "Choose equipment"
                                : "Show exercises"}
                            </Button>
                          </AppControlMorph>
                        ) : null}
                      </div>
                    )}
                  </AppControls>
                </AppScreen>
              )
            } else if (page.type === "exercise-detail") {
              const exercise = EXERCISES_BY_ID.get(page.exerciseId)
              content = exercise ? (
                <ExerciseDetailPage exercise={exercise} onBack={popPage} />
              ) : null
            } else if (page.type === "workout-destination") {
              content = (
                <WorkoutDestinationPage
                  exerciseIds={selectedIds}
                  onAddToExisting={(workoutId) => {
                    const workout = useWorkouts
                      .getState()
                      .workouts.find((item) => item.id === workoutId)
                    if (!workout) return
                    updateScheduledWorkoutExercises(workoutId, [
                      ...new Set([...workout.exerciseIds, ...selectedIds]),
                    ])
                    ensureEngineWorkout(workoutId)
                    triggerHaptic("success")
                    cancelSelectMode()
                    resetPages([
                      { type: "workouts" },
                      { type: "workout-detail", workoutId },
                    ])
                  }}
                  onBack={popPage}
                  onCreateNew={() =>
                    pushPage({
                      type: "workout-form",
                      exerciseIds: selectedIds,
                      workoutId: null,
                    })
                  }
                  preferredWorkoutId={page.preferredWorkoutId}
                />
              )
            } else if (page.type === "workout-form") {
              const workout = page.workoutId
                ? workouts.find((item) => item.id === page.workoutId)
                : null
              content = (
                <WorkoutFormPage
                  initialExerciseIds={page.exerciseIds}
                  onBack={popPage}
                  onRegenerate={
                    page.engineFocusMuscles
                      ? (exerciseIds) =>
                          proposeEngineWorkout({
                            date: new Date().toISOString().slice(0, 10),
                            focusMuscles: page.engineFocusMuscles!,
                            previousExerciseIds: exerciseIds,
                            availableEquipment:
                              toEngineEquipment(selectedEquipment),
                          })
                      : undefined
                  }
                  onSaved={(workoutId) => {
                    cancelSelectMode()
                    resetPages([
                      { type: "workouts" },
                      { type: "workout-detail", workoutId },
                    ])
                  }}
                  workout={workout}
                />
              )
            } else if (page.type === "equipment-preset") {
              content = (
                <EquipmentPresetPage onBack={popPage} onSaved={popPage} />
              )
            } else if (page.type === "exercise-alternatives") {
              const workout = workouts.find(
                (item) => item.id === page.workoutId
              )
              const exercise = EXERCISES_BY_ID.get(page.exerciseId)
              content =
                workout && exercise ? (
                  <ExerciseAlternativesPage
                    alternativeExerciseIds={replacementIds(
                      exercise.id,
                      workout.id
                    )}
                    excludedExerciseIds={workout.exerciseIds}
                    exercise={exercise}
                    onBack={popPage}
                    onSwap={(replacement) => {
                      if (workout.planned) {
                        try {
                          const substitute =
                            useActiveWorkout.getState().session?.workoutId ===
                            workout.id
                              ? substituteRunningPlannedExercise
                              : substituteScheduledPlannedExercise
                          substitute(workout.id, exercise.id, replacement.id)
                        } catch (error) {
                          const message =
                            error instanceof Error
                              ? error.message
                              : "This exercise can’t be replaced right now."
                          return message.includes("recorded exercise")
                            ? "This exercise already has recorded sets, so it can’t be replaced in this session."
                            : message
                        }
                        triggerHaptic("success")
                        popPage()
                        return null
                      }
                      useWorkouts.getState().updateWorkout(workout.id, {
                        exerciseIds: workout.exerciseIds.map((id) =>
                          id === exercise.id ? replacement.id : id
                        ),
                      })
                      triggerHaptic("success")
                      popPage()
                    }}
                  />
                ) : null
            }

            return (
              <PageLayerProvider
                active={interactive}
                entryId={entry.id}
                key={entry.id}
              >
                <section
                  aria-hidden={!interactive}
                  className="app-page-layer"
                  data-active={active ? "true" : undefined}
                  data-exiting={exiting ? "true" : undefined}
                  data-page-entry={entry.id}
                  inert={!interactive}
                >
                  {content}
                </section>
              </PageLayerProvider>
            )
          })}
        </div>
        {/* One character for the whole picking flow, standing in the corner a
            home button would have. It is mounted here rather than in each
            page's header so that moving between muscles, equipment and
            exercises does not tear it down and build it again — and it carries
            the way home in the panel it opens. */}
        {stageForPage(activeEntry.page) !== null ? (
          <Rauta
            actions={[
              {
                label: "My workouts",
                onSelect: () => resetPages([{ type: "workouts" }]),
                primary: true,
              },
            ]}
            label="RAUTA"
            place="top"
            size={72}
          />
        ) : null}
      </AppShell>
    </div>
  )
}

export default App
