import { useMemo } from "react"
import { ChevronRight, RotateCcw, SlidersHorizontal } from "lucide-react"

import { BodyMap } from "@/components/body-map"
import { EquipmentDrawer } from "@/components/equipment-drawer"
import { ExerciseCard } from "@/components/exercise-card"
import { Button } from "@/components/ui/button"
import { EXERCISES, filterExercises } from "@/lib/exercises"
import { useFilters } from "@/store/use-filters"

export function App() {
  const selectedMuscles = useFilters((state) => state.selectedMuscles)
  const selectedEquipment = useFilters((state) => state.selectedEquipment)
  const toggleMuscle = useFilters((state) => state.toggleMuscle)
  const reset = useFilters((state) => state.reset)

  const filtersReady =
    selectedMuscles.length > 0 && selectedEquipment.length > 0

  const exercises = useMemo(
    () => filterExercises(EXERCISES, selectedMuscles, selectedEquipment),
    [selectedMuscles, selectedEquipment]
  )

  const hasFilters = selectedMuscles.length > 0 || selectedEquipment.length > 0

  return (
    <div className="min-h-svh bg-[#0e0e0f] text-foreground">
      <main className="mx-auto min-h-svh w-full max-w-[430px] border-x border-white/[0.04] bg-background px-4 pt-[env(safe-area-inset-top)] pb-[calc(2rem+env(safe-area-inset-bottom))] shadow-2xl shadow-black/40">
        <header className="flex h-16 items-center justify-between">
          <h1 className="text-[17px] font-semibold tracking-[-0.025em]">
            Gym Lib
          </h1>
          {hasFilters && (
            <Button
              aria-label="Reset filters"
              className="h-8 rounded-full px-3 text-xs text-muted-foreground hover:text-foreground"
              onClick={reset}
              size="sm"
              variant="ghost"
            >
              <RotateCcw data-icon="inline-start" />
              Reset
            </Button>
          )}
        </header>

        <section aria-labelledby="muscles-heading">
          <div className="mb-3 flex items-end justify-between">
            <h2
              className="text-[11px] font-medium tracking-[0.12em] text-muted-foreground uppercase"
              id="muscles-heading"
            >
              Muscles
            </h2>
            <span className="text-[11px] text-muted-foreground tabular-nums">
              {selectedMuscles.length || "—"}
            </span>
          </div>
          <div className="rounded-[26px] border border-border bg-card/70 px-3 pt-4 pb-3 shadow-[0_18px_40px_rgba(0,0,0,0.16)]">
            <BodyMap
              onToggle={toggleMuscle}
              selectedMuscles={selectedMuscles}
            />
          </div>
        </section>

        <section aria-labelledby="equipment-heading" className="mt-5">
          <h2
            className="mb-3 text-[11px] font-medium tracking-[0.12em] text-muted-foreground uppercase"
            id="equipment-heading"
          >
            Equipment
          </h2>
          <EquipmentDrawer>
            <div className="flex min-h-14 w-full items-center justify-between rounded-2xl border border-border bg-card px-4 text-left transition-colors hover:bg-muted/60">
              <span className="flex items-center gap-3">
                <span className="grid size-8 place-items-center rounded-xl bg-secondary text-muted-foreground">
                  <SlidersHorizontal className="size-4" />
                </span>
                <span className="flex flex-col">
                  <span className="text-sm font-medium">Equipment</span>
                  <span className="text-xs text-muted-foreground">
                    {selectedEquipment.length > 0
                      ? `${selectedEquipment.length} selected`
                      : "None selected"}
                  </span>
                </span>
              </span>
              <ChevronRight className="size-4 text-muted-foreground" />
            </div>
          </EquipmentDrawer>
        </section>

        <section aria-labelledby="exercises-heading" className="mt-7">
          <div className="mb-3 flex items-end justify-between">
            <h2
              className="text-[11px] font-medium tracking-[0.12em] text-muted-foreground uppercase"
              id="exercises-heading"
            >
              Exercises
            </h2>
            <output
              aria-live="polite"
              className="text-[11px] text-muted-foreground tabular-nums"
              data-testid="result-count"
            >
              {filtersReady ? exercises.length : "—"}
            </output>
          </div>

          {filtersReady && (
            <div className="space-y-2" data-testid="exercise-results">
              {exercises.map((exercise) => (
                <ExerciseCard exercise={exercise} key={exercise.id} />
              ))}
              {exercises.length === 0 && (
                <div className="rounded-2xl border border-border bg-card px-4 py-8 text-center text-sm text-muted-foreground">
                  0 exercises
                </div>
              )}
            </div>
          )}
        </section>
      </main>
    </div>
  )
}

export default App
