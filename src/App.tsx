import { useEffect, useMemo, useRef, useState } from "react"
import { Check, ChevronLeft, ChevronRight, RotateCcw } from "lucide-react"

import { AnimatedNumber } from "@/components/animated-number"
import { BodyMap } from "@/components/body-map"
import { EquipmentPresets } from "@/components/equipment-presets"
import { ExerciseCard } from "@/components/exercise-card"
import { Button } from "@/components/ui/button"
import { EQUIPMENT_OPTIONS, EXERCISES, filterExercises } from "@/lib/exercises"
import { titleCase } from "@/lib/text"
import { equipmentImage } from "@/lib/visuals"
import { useFilters } from "@/store/use-filters"

type Stage = 1 | 2 | 3

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
      <p className="t-stagger-line t-stagger-line--1 text-[10px] font-medium tracking-[0.14em] text-muted-foreground uppercase">
        {stage} / 3
      </p>
      <h1 className="t-stagger-line t-stagger-line--2 mt-0.5 text-2xl font-semibold tracking-[-0.04em]">
        {STAGE_LABELS[stage]}
      </h1>
    </div>
  )
}

export function App() {
  const [stage, setStage] = useState<Stage>(1)
  const selectedMuscles = useFilters((state) => state.selectedMuscles)
  const selectedEquipment = useFilters((state) => state.selectedEquipment)
  const toggleMuscle = useFilters((state) => state.toggleMuscle)
  const toggleEquipment = useFilters((state) => state.toggleEquipment)
  const reset = useFilters((state) => state.reset)

  const exercises = useMemo(
    () => filterExercises(EXERCISES, selectedMuscles, selectedEquipment),
    [selectedMuscles, selectedEquipment]
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

  return (
    <div className="min-h-svh bg-[#0e0e0f] text-foreground">
      <main className="mx-auto flex h-svh w-full max-w-[430px] flex-col overflow-hidden border-x border-white/[0.04] bg-background pt-[env(safe-area-inset-top)] shadow-2xl shadow-black/40">
        <header className="shrink-0 px-4 pt-3 pb-2">
          <div className="mb-4 flex items-center justify-between">
            <div
              aria-label={`Step ${stage} of 3`}
              aria-valuemax={3}
              aria-valuemin={1}
              aria-valuenow={stage}
              className="flex items-center gap-2"
              role="progressbar"
            >
              {[1, 2, 3].map((step) => (
                <span
                  aria-hidden="true"
                  className={`h-1.5 rounded-full transition-[width,background-color] duration-250 ${
                    step === stage
                      ? "w-8 bg-primary"
                      : step < stage
                        ? "w-4 bg-primary/35"
                        : "w-4 bg-white/10"
                  }`}
                  key={step}
                />
              ))}
            </div>
            {hasFilters && (
              <Button
                aria-label="Reset selections"
                className="size-9 rounded-full text-muted-foreground hover:text-foreground"
                onClick={resetFlow}
                size="icon"
                variant="ghost"
              >
                <RotateCcw />
              </Button>
            )}
          </div>
          <div className="flex items-end justify-between">
            <StageHeading stage={stage} />
            <output
              aria-live="polite"
              className="text-xs text-muted-foreground tabular-nums"
              data-testid="stage-count"
            >
              {stage === 1 && (
                <>
                  <AnimatedNumber value={selectedMuscles.length} /> selected
                </>
              )}
              {stage === 2 && (
                <>
                  <AnimatedNumber value={selectedEquipment.length} /> selected
                </>
              )}
              {stage === 3 && (
                <>
                  <AnimatedNumber value={exercises.length} /> exercises
                </>
              )}
            </output>
          </div>
        </header>

        <div className="t-page-slide min-h-0 flex-1" data-page={stage}>
          <section
            aria-hidden={stage !== 1}
            aria-label="Choose muscles"
            className="t-page px-4 pb-4"
            data-page-id="1"
            inert={stage !== 1}
          >
            <div className="h-full overflow-y-auto rounded-[28px] border border-border bg-card/70 px-3 pt-4 pb-3 shadow-[0_18px_40px_rgba(0,0,0,0.16)]">
              <BodyMap
                onToggle={toggleMuscle}
                selectedMuscles={selectedMuscles}
              />
            </div>
          </section>

          <section
            aria-hidden={stage !== 2}
            aria-label="Choose equipment"
            className="t-page overflow-y-auto px-4 pb-4"
            data-page-id="2"
            inert={stage !== 2}
          >
            <EquipmentPresets />
            <div className="grid grid-cols-2 gap-2">
              {EQUIPMENT_OPTIONS.map((equipment) => {
                const checked = selectedEquipment.includes(equipment)
                return (
                  <button
                    aria-checked={checked}
                    className={`t-check group relative overflow-hidden rounded-[22px] border text-left ${
                      checked
                        ? "border-primary/70 bg-primary/10 shadow-[0_0_0_1px_rgba(255,102,51,0.12)]"
                        : "border-border bg-card"
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
                        loading="lazy"
                        src={equipmentImage(equipment)}
                      />
                    </span>
                    <span className="flex min-h-12 items-center px-3 py-2.5 text-xs leading-tight font-medium">
                      {titleCase(equipment)}
                    </span>
                    <span className="absolute top-2 right-2 grid size-6 place-items-center rounded-full border border-white/10 bg-black/55 text-primary backdrop-blur-sm">
                      <Check className="size-3.5" />
                    </span>
                  </button>
                )
              })}
            </div>
          </section>

          <section
            aria-hidden={stage !== 3}
            aria-label="Matching exercises"
            className="t-page overflow-y-auto px-4 pb-4"
            data-page-id="3"
            inert={stage !== 3}
          >
            <div
              className="t-stagger is-shown exercise-results space-y-3"
              data-testid="exercise-results"
            >
              {exercises.map((exercise, index) => (
                <ExerciseCard
                  exercise={exercise}
                  index={index}
                  key={exercise.id}
                />
              ))}
              {exercises.length === 0 && (
                <div className="rounded-2xl border border-border bg-card px-4 py-8 text-center text-sm text-muted-foreground">
                  0 exercises
                </div>
              )}
            </div>
          </section>
        </div>

        <footer className="shrink-0 border-t border-border bg-background/95 px-4 pt-3 pb-[calc(0.75rem+env(safe-area-inset-bottom))] backdrop-blur-xl">
          <div className="flex gap-2">
            {stage > 1 && (
              <Button
                aria-label="Previous stage"
                className="size-12 shrink-0 rounded-2xl"
                onClick={goBack}
                size="icon"
                variant="secondary"
              >
                <ChevronLeft />
              </Button>
            )}
            {stage < 3 ? (
              <Button
                className="h-12 flex-1 rounded-2xl text-sm font-semibold"
                disabled={!canContinue}
                onClick={goForward}
              >
                {stage === 1 ? "Choose equipment" : "Show exercises"}
                <ChevronRight data-icon="inline-end" />
              </Button>
            ) : (
              <Button
                className="h-12 flex-1 rounded-2xl"
                onClick={() => setStage(1)}
                variant="secondary"
              >
                Change selection
              </Button>
            )}
          </div>
        </footer>
      </main>
    </div>
  )
}

export default App
