import { useState } from "react"
import { Plus, Settings2, Trash2 } from "lucide-react"

import { RotaryKnob } from "@/components/ui/rotary-knob"
import { triggerHaptic } from "@/lib/haptics"
import {
  activeConfigurationFor,
  formatKg,
  nextStationId,
  stationChoicesFor,
  type LoadContext,
  type MeasuredMode,
} from "@/lib/resistance"
import { cn } from "@/lib/utils"
import { useTrainingRecords } from "@/store/use-training-records"
import type { ExerciseSummary } from "@/types"

/** Steps a rack, stack or plate set plausibly moves in. Wider than that is not
 *  a load step, it is a different exercise. */
const STEP_RANGE = { min: 0.25, max: 20, step: 0.25 }
/** Where a stack starts. Zero is the bar or the bare handle. */
const START_RANGE = { min: 0, max: 60, step: 0.5 }

/** The two numbers a station has. Anything else about a machine is not
 *  something the app can measure a set against. */
const FACETS = [
  { key: "step" as const, chip: "Step", label: "Set the load step" },
  { key: "start" as const, chip: "Lightest", label: "Set the lightest load" },
]

function gridSummary(context: LoadContext) {
  const { grid } = context
  if ("availableLoadsKg" in grid) {
    const loads = [...grid.availableLoadsKg].sort((a, b) => a - b)
    return `${loads.length} fixed loads · ${formatKg(loads[0])}–${formatKg(loads.at(-1)!)} kg`
  }
  const from = grid.minimumKg ?? 0
  return [
    `${formatKg(grid.incrementKg)} kg steps`,
    ...(from > 0 ? [`from ${formatKg(from)} kg`] : []),
    context.basis === "per_implement" ? "each" : "total",
  ].join(" · ")
}

/**
 * Which machine this set is being measured on.
 *
 * Kilograms only compare inside one station: 60 on the stack in one corner is
 * not 60 on the one in the other, and the engine refuses to progress across
 * that gap rather than guessing. So the station has to be something a person
 * can state — but only where it matters. An exercise nobody has thought about
 * shows one chip, the equipment they already told us they have, and behaves
 * exactly as it did before this control existed.
 *
 * Nothing here is typed. A station is added with one tap and described with
 * the same dial the equipment page uses, because the two numbers it holds —
 * what the stack steps in and where it starts — are the whole of what the
 * machine physically offers.
 */
export function StationPicker({
  equipmentIncrementKg,
  exercise,
  mode,
}: {
  /** The load step saved for this equipment, which the default station uses
   *  until a station of its own says otherwise. */
  equipmentIncrementKg?: number
  exercise: ExerciseSummary
  /** The measurement being logged. Load and assistance are separate stations
   *  even on one machine, and never stand in for each other. */
  mode: MeasuredMode
}) {
  const settings = useTrainingRecords((state) => state.data.settings)
  const saveLoadConfiguration = useTrainingRecords(
    (state) => state.saveLoadConfiguration
  )
  const removeLoadConfiguration = useTrainingRecords(
    (state) => state.removeLoadConfiguration
  )
  const selectLoadConfiguration = useTrainingRecords(
    (state) => state.selectLoadConfiguration
  )
  const [editing, setEditing] = useState(false)
  const [facet, setFacet] = useState<"step" | "start">("step")

  const choices = stationChoicesFor(
    exercise,
    mode,
    settings,
    equipmentIncrementKg
  )
  // One resolution rule, the same one the engine and the editor use: what the
  // picker highlights is what the next set will actually be measured against.
  const activeId =
    activeConfigurationFor(exercise.id, mode, settings)?.id ?? null
  const active = choices.find((choice) => choice.id === activeId) ?? choices[0]
  const defaultStationId = choices[0].context.stationId
  const editable = !("availableLoadsKg" in active.context.grid)
  const grid = active.context.grid

  const write = (patch: { incrementKg?: number; minimumKg?: number }) => {
    if ("availableLoadsKg" in grid) return
    const id = saveLoadConfiguration({
      ...(active.id ? { id: active.id } : {}),
      exerciseId: exercise.id,
      stationId: active.context.stationId,
      mode,
      basis: active.context.basis,
      grid: {
        incrementKg: patch.incrementKg ?? grid.incrementKg,
        minimumKg: patch.minimumKg ?? grid.minimumKg ?? 0,
      },
    })
    if (!active.id) selectLoadConfiguration(exercise.id, id)
  }

  /**
   * Writes down the station a choice stands for, so it can be selected.
   *
   * Going back to the equipment default is a statement about where the person
   * is training, and a statement has to be recorded somewhere: without this,
   * "the usual bar" and "nothing said yet" would be the same value, and the
   * one saved station would silently win every time.
   */
  const pin = (choice: (typeof choices)[number]) =>
    saveLoadConfiguration({
      exerciseId: exercise.id,
      stationId: choice.context.stationId,
      mode,
      basis: choice.context.basis,
      grid: structuredClone(choice.context.grid),
    })

  const add = () => {
    triggerHaptic("selection")
    const stationId = nextStationId(
      defaultStationId,
      settings.loadConfigurations
        .filter((item) => item.exerciseId === exercise.id)
        .map((item) => item.stationId)
    )
    const id = saveLoadConfiguration({
      exerciseId: exercise.id,
      stationId,
      mode,
      basis: choices[0].context.basis,
      grid:
        "availableLoadsKg" in choices[0].context.grid
          ? { incrementKg: 2.5, minimumKg: 0 }
          : {
              incrementKg: choices[0].context.grid.incrementKg,
              minimumKg: choices[0].context.grid.minimumKg ?? 0,
            },
    })
    selectLoadConfiguration(exercise.id, id)
    setEditing(true)
  }

  return (
    <div className="space-y-2">
      <div className="flex min-w-0 items-center gap-2">
        {/* The same label column the editor's own rows use, so the station
            sits in one list with load, reps and RIR rather than beside it. */}
        <span className="w-11 shrink-0 text-[10px] font-black tracking-[0.14em] text-muted-foreground uppercase">
          Where
        </span>
        <div
          className="flex min-w-0 flex-1 [scrollbar-width:none] gap-1.5 overflow-x-auto py-0.5 [&::-webkit-scrollbar]:hidden"
          data-swipe-ignore
        >
          {choices.map((choice) => {
            const selected = choice === active
            return (
              <button
                aria-label={`Log at ${choice.label}`}
                aria-pressed={selected}
                className="preset-chip hit-target relative shrink-0 px-3.5 text-sm"
                data-haptics="off"
                key={choice.id ?? "default"}
                onClick={() => {
                  triggerHaptic("selection")
                  if (selected) return setEditing((open) => !open)
                  selectLoadConfiguration(exercise.id, choice.id ?? pin(choice))
                  setEditing(false)
                }}
                type="button"
              >
                {choice.label}
              </button>
            )
          })}
          <button
            aria-label="Add another station for this exercise"
            className="preset-chip hit-target relative shrink-0 px-3 text-sm"
            data-haptics="off"
            onClick={add}
            type="button"
          >
            <Plus className="size-4" />
          </button>
        </div>
        <button
          aria-label={`${editing ? "Hide" : "Show"} load steps for ${active.label}`}
          aria-pressed={editing}
          className={cn(
            "interactive-spring grid size-10 shrink-0 place-items-center rounded-2xl border border-border",
            editing ? "bg-primary/12 text-primary" : "text-muted-foreground"
          )}
          onClick={() => {
            triggerHaptic("selection")
            setEditing((open) => !open)
          }}
          type="button"
        >
          <Settings2 className="size-4" />
        </button>
      </div>

      {editing ? (
        <div className="rounded-2xl border border-border bg-card/60 px-3 py-3">
          <p className="text-center text-[11px] font-semibold text-muted-foreground">
            {active.label} · {gridSummary(active.context)}
          </p>
          {editable ? (
            <>
              {/* One dial, two facts: a phone has room for a knob you can
                  actually turn, not for two of them side by side. */}
              <div className="mt-2 flex items-center justify-center gap-1.5">
                {FACETS.map((item) => (
                  <button
                    aria-label={item.label}
                    aria-pressed={facet === item.key}
                    className="preset-chip hit-target shrink-0 px-3.5 text-sm"
                    data-haptics="off"
                    key={item.key}
                    onClick={() => {
                      triggerHaptic("selection")
                      setFacet(item.key)
                    }}
                    type="button"
                  >
                    {item.chip}
                  </button>
                ))}
              </div>
              <RotaryKnob
                ariaLabel={`${active.label} ${facet === "step" ? "load step" : "lightest load"}`}
                className="mx-auto mt-2"
                format={formatKg}
                max={facet === "step" ? STEP_RANGE.max : START_RANGE.max}
                min={facet === "step" ? STEP_RANGE.min : START_RANGE.min}
                onChange={(value) =>
                  write(
                    facet === "step"
                      ? { incrementKg: value }
                      : { minimumKg: value }
                  )
                }
                size={152}
                step={facet === "step" ? STEP_RANGE.step : START_RANGE.step}
                unit={facet === "step" ? "kg step" : "kg lightest"}
                value={
                  facet === "step"
                    ? "incrementKg" in grid
                      ? grid.incrementKg
                      : 2.5
                    : "minimumKg" in grid
                      ? (grid.minimumKg ?? 0)
                      : 0
                }
              />
            </>
          ) : (
            // An imported ladder states loads this app cannot re-derive. It is
            // shown and used as it is, never rewritten into even steps.
            <p className="mt-2 text-center text-[11px] text-muted-foreground">
              Fixed loads from a backup. Remove the station to use even steps.
            </p>
          )}
          {active.id ? (
            <button
              className="interactive-spring mt-2 flex h-10 w-full items-center justify-center gap-1.5 rounded-2xl text-xs font-bold text-destructive"
              onClick={() => {
                triggerHaptic("warning")
                removeLoadConfiguration(active.id!)
                setEditing(false)
              }}
              type="button"
            >
              <Trash2 className="size-4" />
              {active.context.stationId === defaultStationId
                ? "Use equipment default"
                : `Remove ${active.label}`}
            </button>
          ) : null}
        </div>
      ) : null}
    </div>
  )
}
