import {
  Fragment,
  startTransition,
  useCallback,
  useEffect,
  useMemo,
  useReducer,
  useRef,
  useState,
  type CSSProperties,
} from "react"
import {
  ChevronLeft,
  FlipHorizontal2,
  Home,
  Plus,
  Search,
  SearchX,
  X,
} from "lucide-react"

import { AnimatedCheck } from "@/components/animated-check"
import { AppImage } from "@/components/app-image"
import {
  AppControls,
  AppHeaderButton,
  AppScreen,
  AppShell,
  AppShellHeader,
  AppSurface,
  PageLayerProvider,
} from "@/components/app-shell"
import { BodyMap } from "@/components/body-map"
import {
  EquipmentPresetEditor,
  EquipmentPresets,
} from "@/components/equipment-presets"
import { ExerciseCard } from "@/components/exercise-card"
import { ExerciseSearch } from "@/components/exercise-search"
import { HapticLayer } from "@/components/haptic-layer"
import { LikeButton } from "@/components/like-button"
import {
  EquipmentPresetPage,
  ExerciseAlternativesPage,
  ExerciseDetailPage,
  WorkoutDestinationPage,
  WorkoutFormPage,
} from "@/components/secondary-pages"
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
import { clearAllGymLibData } from "@/lib/app-backup"
import {
  EQUIPMENT_OPTIONS,
  EXERCISE_PAGE_SIZE,
  EXERCISES,
  EXERCISES_BY_ID,
  filterExercises,
  supportingFromIndex,
} from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { isNative } from "@/lib/native"
import { syncICloudNow } from "@/lib/icloud-sync"
import { titleCase } from "@/lib/text"
import { cn } from "@/lib/utils"
import { equipmentImage } from "@/lib/visuals"
import {
  appNavigationReducer,
  pageHasControls,
  type AppPage,
  type AppPageEntry,
  type NavigationDirection,
} from "@/store/app-navigation"
import { readAppSession, writeAppSession } from "@/store/app-session"
import { useActiveWorkout } from "@/store/use-active-workout"
import { useFavorites } from "@/store/use-favorites"
import { useFilters } from "@/store/use-filters"
import { useWorkouts } from "@/store/use-workouts"
import type { ExerciseSummary, MuscleId } from "@/types"

type PickerStage = 1 | 2 | 3

const STAGE_LABELS: Record<PickerStage, string> = {
  1: "Muscles",
  2: "Equipment",
  3: "Exercises",
}

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

function FlowProgress({ stage }: { stage: PickerStage }) {
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

function prefersReducedMotion() {
  return (
    window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false
  )
}

export function App() {
  const [initialSession] = useState(readAppSession)
  const [navigation, dispatchNavigation] = useReducer(
    appNavigationReducer,
    initialSession.pages,
    (initialPages) => ({
      direction: "forward" as const,
      pages: initialPages.map(createPageEntry),
    })
  )
  const pages = navigation.pages
  const pagesRef = useRef(pages)
  const focusOrigins = useRef(new Map<string, HTMLElement>())
  const popTimer = useRef<number | null>(null)
  const entryFrame = useRef<number | null>(null)
  const entryTimer = useRef<number | null>(null)
  const entryCompletion = useRef<(() => void) | null>(null)
  const [direction, setDirection] = useState<NavigationDirection>("forward")
  const [enteringId, setEnteringId] = useState<string | null>(null)
  const [leavingId, setLeavingId] = useState<string | null>(null)
  const [countdownOpen, setCountdownOpen] = useState(false)

  useEffect(() => {
    pagesRef.current = pages
  }, [pages])

  useEffect(
    () => () => {
      if (popTimer.current !== null) window.clearTimeout(popTimer.current)
      if (entryFrame.current !== null) cancelAnimationFrame(entryFrame.current)
      if (entryTimer.current !== null) window.clearTimeout(entryTimer.current)
    },
    []
  )

  const focusPage = useCallback((entryId: string) => {
    requestAnimationFrame(() => {
      document
        .querySelector<HTMLElement>(`[data-page-entry="${entryId}"] h1`)
        ?.focus({ preventScroll: true })
    })
  }, [])

  const cancelEntryTransition = useCallback(() => {
    if (entryFrame.current !== null) cancelAnimationFrame(entryFrame.current)
    if (entryTimer.current !== null) window.clearTimeout(entryTimer.current)
    entryFrame.current = null
    entryTimer.current = null
    entryCompletion.current = null
    const stack = document.querySelector<HTMLElement>(".app-page-stack")
    if (stack) {
      delete stack.dataset.transitionReady
      stack
        .querySelectorAll<HTMLElement>(".app-page-layer[data-ready]")
        .forEach((layer) => delete layer.dataset.ready)
    }
  }, [])

  const beginEntryTransition = useCallback(
    (entryId: string, completion?: () => void) => {
      cancelEntryTransition()
      entryCompletion.current = completion ?? null
      setEnteringId(entryId)

      const finish = () => {
        startTransition(() => {
          setEnteringId((current) => (current === entryId ? null : current))
        })
        const stack = document.querySelector<HTMLElement>(".app-page-stack")
        if (stack) {
          delete stack.dataset.transitionReady
          stack
            .querySelectorAll<HTMLElement>(".app-page-layer[data-ready]")
            .forEach((layer) => delete layer.dataset.ready)
        }
        entryCompletion.current?.()
        entryCompletion.current = null
        entryTimer.current = null
        focusPage(entryId)
      }

      // The browser already composites the regular transform transition. The
      // two-frame staging is only for the slower WKWebView path; keeping it
      // out of the browser also prevents a focus click from racing a React
      // page remount in tests and desktop Safari.
      if (!isNative() || prefersReducedMotion()) {
        entryTimer.current = window.setTimeout(finish, 0)
        return
      }

      // Mount the next page at +100%, then give WKWebView two complete paint
      // opportunities before moving either large page layer.
      entryFrame.current = requestAnimationFrame(() => {
        entryFrame.current = requestAnimationFrame(() => {
          entryFrame.current = null
          const stack = document.querySelector<HTMLElement>(".app-page-stack")
          if (stack) {
            stack.dataset.transitionReady = "true"
            stack
              .querySelector<HTMLElement>(`[data-page-entry="${entryId}"]`)
              ?.setAttribute("data-ready", "true")
          }
          entryTimer.current = window.setTimeout(finish, 310)
        })
      })
    },
    [cancelEntryTransition, focusPage]
  )

  const pushPage = useCallback(
    (page: AppPage) => {
      if (leavingId) {
        if (popTimer.current !== null) window.clearTimeout(popTimer.current)
        dispatchNavigation({ type: "pop" })
        focusOrigins.current.delete(leavingId)
        setLeavingId(null)
        popTimer.current = null
      }
      const entry = createPageEntry(page)
      const activeElement = document.activeElement
      if (activeElement instanceof HTMLElement) {
        focusOrigins.current.set(entry.id, activeElement)
      }
      setDirection("forward")
      beginEntryTransition(entry.id)
      dispatchNavigation({ type: "push", entry })
    },
    [beginEntryTransition, leavingId]
  )

  const popPage = useCallback(() => {
    const current = pagesRef.current
    if (current.length <= 1 || leavingId) return
    const leaving = current[current.length - 1]
    setDirection("back")
    setLeavingId(leaving.id)
    popTimer.current = window.setTimeout(
      () => {
        dispatchNavigation({ type: "pop" })
        setLeavingId(null)
        popTimer.current = null
        const origin = focusOrigins.current.get(leaving.id)
        focusOrigins.current.delete(leaving.id)
        requestAnimationFrame(() => origin?.focus({ preventScroll: true }))
      },
      prefersReducedMotion() ? 0 : 290
    )
  }, [leavingId])

  const replacePage = useCallback(
    (page: AppPage) => {
      if (popTimer.current !== null) {
        window.clearTimeout(popTimer.current)
        popTimer.current = null
      }
      if (leavingId) {
        dispatchNavigation({ type: "pop" })
        focusOrigins.current.delete(leavingId)
        setLeavingId(null)
      }
      const entry = createPageEntry(page)
      const current = leavingId
        ? pagesRef.current.slice(0, -1)
        : pagesRef.current
      const desired = [...current.slice(0, -1), entry]
      setDirection("forward")
      beginEntryTransition(entry.id, () =>
        dispatchNavigation({ type: "reset", entries: desired })
      )
      dispatchNavigation({ type: "push", entry })
    },
    [beginEntryTransition, leavingId]
  )

  const resetPages = useCallback(
    (nextPages: AppPage[]) => {
      if (popTimer.current !== null) {
        window.clearTimeout(popTimer.current)
        popTimer.current = null
      }
      cancelEntryTransition()
      const entries = nextPages.map(createPageEntry)
      const active = entries.at(-1)
      if (!active) return
      setDirection("back")
      setEnteringId(null)
      setLeavingId(null)
      focusOrigins.current.clear()
      dispatchNavigation({ type: "reset", entries })
      focusPage(active.id)
    },
    [cancelEntryTransition, focusPage]
  )

  const visualActiveIndex = leavingId
    ? Math.max(0, pages.length - 2)
    : pages.length - 1
  const activeEntry = pages[visualActiveIndex] ?? pages[0]
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

  const [favoritesOnly, setFavoritesOnly] = useState(
    initialSession.favoritesOnly
  )
  const [selectMode, setSelectMode] = useState(initialSession.selectMode)
  const [selectedIds, setSelectedIds] = useState<string[]>(
    initialSession.selectedIds
  )
  const [search, setSearch] = useState("")
  const [searchOpen, setSearchOpen] = useState(false)
  const [presetEditorOpen, setPresetEditorOpen] = useState(false)
  const [bodySide, setBodySide] = useState<"front" | "back">("front")
  const equipmentScrollRef = useRef<HTMLElement>(null)

  const exercises = useMemo(
    () => filterExercises(EXERCISES, selectedMuscles, selectedEquipment),
    [selectedEquipment, selectedMuscles]
  )

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
  const pagedExercises = visibleExercises.slice(0, visibleCount)
  const supportingIndex = useMemo(
    () => supportingFromIndex(visibleExercises, selectedMuscles),
    [selectedMuscles, visibleExercises]
  )

  const persistedPages = useMemo(
    () => (leavingId ? pages.slice(0, Math.max(1, pages.length - 1)) : pages),
    [leavingId, pages]
  )
  const appSession = useMemo(
    () => ({
      detailExerciseId:
        activePage.type === "exercise-detail" ? activePage.exerciseId : null,
      favoritesOnly,
      pages: persistedPages.map((entry) => entry.page),
      selectedIds,
      selectMode,
    }),
    [activePage, favoritesOnly, persistedPages, selectedIds, selectMode]
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

  const selectExerciseFromDetail = useCallback(
    (exercise: ExerciseSummary) => {
      triggerHaptic("selection")
      setSelectedIds((ids) =>
        ids.includes(exercise.id) ? ids : [...ids, exercise.id]
      )
      setSelectMode(true)
      popPage()
    },
    [popPage]
  )

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
    canGoBack: pages.length > 1 && !leavingId && !enteringId,
    canGoForward: false,
    onBack: popPage,
    onForward: () => undefined,
  })

  const commandBandVisible = !countdownOpen && pageHasControls(activePage)

  return (
    <div className="min-h-(--app-viewport-height) bg-(--app-shell) text-foreground">
      <HapticLayer />
      <SettingsEffects />
      <SvgFilterDefs />
      <AppShell commandsVisible={commandBandVisible}>
        <div
          className="app-page-stack"
          data-direction={direction}
          data-entering={enteringId ? "true" : undefined}
          ref={containerRef}
          {...handlers}
        >
          {pages.map((entry, index) => {
            const page = entry.page
            const active = index === visualActiveIndex
            const previous = index === visualActiveIndex - 1
            // The incoming page becomes the semantic active page immediately
            // (so VoiceOver and keyboard users can reach its heading); only
            // its visual layer waits for the two-paint preparation above.
            const interactive = active
            const leaving = entry.id === leavingId
            const stage = stageForPage(page)
            let content = null

            if (page.type === "workouts") {
              content = (
                <WorkoutsPage
                  onCreate={() => startExerciseFlow()}
                  onDelete={(workoutId) =>
                    useWorkouts.getState().deleteWorkout(workoutId)
                  }
                  onSelect={(workout) =>
                    pushPage({ type: "workout-detail", workoutId: workout.id })
                  }
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
                />
              )
            } else if (page.type === "workout-detail") {
              content = (
                <WorkoutDetailPage
                  onAddExercise={() => startExerciseFlow(page.workoutId)}
                  onBack={popPage}
                  onDelete={() => {
                    useWorkouts.getState().deleteWorkout(page.workoutId)
                    resetPages([{ type: "workouts" }])
                  }}
                  onDiscard={() => useActiveWorkout.getState().cancel()}
                  onFinish={() => useActiveWorkout.getState().finish()}
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
                      selectable: false,
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
                      right={
                        <AppHeaderButton
                          aria-label="My workouts"
                          onClick={() => resetPages([{ type: "workouts" }])}
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

                    {stage === 1 ? (
                      <section
                        aria-label="Choose muscles"
                        className="min-h-0 flex-1 px-[clamp(0.75rem,4vw,1.25rem)] pt-[calc(4.25rem+env(safe-area-inset-top)+0.75rem)] pb-[clamp(0.75rem,2vh,1.25rem)]"
                      >
                        <div className="relative h-full min-h-0">
                          <DotPattern
                            className="[mask-image:radial-gradient(ellipse_at_center,black_15%,transparent_72%)] transition-[fill,fill-opacity] duration-500"
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
                        className="app-scroll-content min-h-0 flex-1 overflow-y-auto px-5 pt-[calc(4.25rem+env(safe-area-inset-top)+0.75rem)] pb-20"
                        ref={equipmentScrollRef}
                        tabIndex={-1}
                      >
                        <div className="grid grid-cols-2 gap-3">
                          {EQUIPMENT_OPTIONS.map(
                            (equipment, equipmentIndex) => {
                              const checked =
                                selectedEquipment.includes(equipment)
                              return (
                                <button
                                  aria-checked={checked}
                                  className={`interactive-spring group relative overflow-hidden rounded-3xl border bg-card text-left shadow-sm shadow-black/10 transition-[border-color,box-shadow] duration-300 ${
                                    checked
                                      ? "border-primary/75 shadow-[0_0_0_1px_color-mix(in_oklch,var(--primary)_30%,transparent)]"
                                      : "border-border"
                                  }`}
                                  key={equipment}
                                  onClick={() => {
                                    triggerHaptic("selection")
                                    toggleEquipment(equipment)
                                  }}
                                  role="checkbox"
                                  type="button"
                                >
                                  <span className="relative block aspect-[1.18] overflow-hidden bg-[#161618]">
                                    <AppImage
                                      alt=""
                                      className="h-full w-full object-cover saturate-[1.65]"
                                      decoding="async"
                                      draggable={false}
                                      fetchPriority={
                                        equipmentIndex < 4 ? "high" : "low"
                                      }
                                      loading={
                                        equipmentIndex < 4 ? "eager" : "lazy"
                                      }
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
                            }
                          )}
                        </div>
                      </section>
                    ) : null}

                    {stage === 3 ? (
                      <section
                        aria-label="Matching exercises"
                        className={cn(
                          "app-scroll-content min-h-0 flex-1 overflow-y-auto px-5 pt-[calc(4.25rem+env(safe-area-inset-top)+0.75rem)]",
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
                              {pagedExercises.map((exercise, exerciseIndex) => (
                                <Fragment key={exercise.id}>
                                  {exerciseIndex === supportingIndex ? (
                                    <h2 className="col-span-2 flex items-center gap-3 pt-3 pb-0.5 text-xs font-medium tracking-wide text-muted-foreground uppercase">
                                      <span className="h-px flex-1 bg-border" />
                                      Also works these muscles
                                      <span className="h-px flex-1 bg-border" />
                                    </h2>
                                  ) : null}
                                  <ExerciseCard
                                    exercise={exercise}
                                    index={exerciseIndex}
                                    onOpenDetail={(candidate) => {
                                      triggerHaptic("light")
                                      pushPage({
                                        type: "exercise-detail",
                                        exerciseId: candidate.id,
                                        selectable: true,
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

                    {stage === 2 ? (
                      <div className="app-surface-bottom-dock equipment-presets-dock">
                        {presetEditorOpen ? (
                          <EquipmentPresetEditor
                            className="px-5"
                            onSaved={() => setPresetEditorOpen(false)}
                          />
                        ) : (
                          <EquipmentPresets className="px-5" />
                        )}
                      </div>
                    ) : null}

                    {stage === 3 && searchOpen ? (
                      <div className="app-surface-bottom-dock exercise-search-dock">
                        <ExerciseSearch onChange={setSearch} value={search} />
                      </div>
                    ) : stage === 3 && selectMode ? (
                      <div className="app-surface-bottom-dock exercise-selection-dock">
                        <Button
                          className="pointer-events-auto w-full"
                          disabled={selectedIds.length === 0}
                          onClick={() =>
                            addSelectionToWorkout(preferredWorkoutId)
                          }
                          size="cta"
                        >
                          Add to workout
                          {selectedIds.length > 0
                            ? ` (${selectedIds.length})`
                            : ""}
                        </Button>
                      </div>
                    ) : null}
                  </AppSurface>

                  <AppControls
                    transitionKey={`picker:${stage}:${selectMode}:${presetEditorOpen}:${selectedMuscles.length}:${selectedEquipment.length}`}
                  >
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
                          onClick={() => setMuscles([])}
                          size="icon-cta"
                          variant="secondary"
                        >
                          <X className="size-5" />
                        </Button>
                      ) : null}
                      {stage === 2 && selectedEquipment.length > 0 ? (
                        <Button
                          aria-label="Clear equipment selection"
                          onClick={() => setEquipment([])}
                          size="icon-cta"
                          variant="secondary"
                        >
                          <X className="size-5" />
                        </Button>
                      ) : null}
                      {stage === 2 ? (
                        <Button
                          aria-expanded={presetEditorOpen}
                          aria-label={
                            presetEditorOpen
                              ? "Close preset editor"
                              : "Create equipment preset"
                          }
                          disabled={selectedEquipment.length === 0}
                          onClick={() => setPresetEditorOpen((open) => !open)}
                          size="icon-cta"
                          variant="secondary"
                        >
                          <Plus className="size-5" />
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
                          aria-expanded={searchOpen}
                          aria-label={
                            searchOpen ? "Close search" : "Search exercises"
                          }
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
                              ? "border-primary bg-[color-mix(in_oklch,var(--card),var(--primary)_22%)] text-primary"
                              : "border-border bg-card text-primary"
                          }`}
                          iconClassName="size-5"
                          liked={favoritesOnly}
                          onClick={() => setFavoritesOnly((value) => !value)}
                        />
                      ) : null}
                      {stage < 3 ? (
                        <Button
                          className="min-w-0 flex-1"
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
                            : `Show exercises (${exercises.length})`}
                        </Button>
                      ) : selectMode ? null : (
                        <Button
                          className="min-w-0 flex-1"
                          onClick={() => setSelectMode(true)}
                          size="cta"
                        >
                          Select
                        </Button>
                      )}
                    </div>
                  </AppControls>
                </AppScreen>
              )
            } else if (page.type === "exercise-detail") {
              const exercise = EXERCISES_BY_ID.get(page.exerciseId)
              content = exercise ? (
                <ExerciseDetailPage
                  exercise={exercise}
                  onBack={popPage}
                  onSelect={selectExerciseFromDetail}
                  selectable={page.selectable}
                  selected={selectedIds.includes(page.exerciseId)}
                />
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
                    useWorkouts.getState().updateWorkout(workoutId, {
                      exerciseIds: [
                        ...new Set([...workout.exerciseIds, ...selectedIds]),
                      ],
                    })
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
                    excludedExerciseIds={workout.exerciseIds}
                    exercise={exercise}
                    onBack={popPage}
                    onSwap={(replacement) => {
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
                  data-entering={entry.id === enteringId ? "true" : undefined}
                  data-leaving={leaving ? "true" : undefined}
                  data-page-entry={entry.id}
                  data-previous={previous ? "true" : undefined}
                  inert={!interactive}
                >
                  {content}
                </section>
              </PageLayerProvider>
            )
          })}
        </div>
      </AppShell>
    </div>
  )
}

export default App
