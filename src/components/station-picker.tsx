import { useState } from "react"
import { Plus, Settings2, Trash2, X } from "lucide-react"

import { Button } from "@/components/ui/button"
import { RotaryKnob } from "@/components/ui/rotary-knob"
import { triggerHaptic } from "@/lib/haptics"
import {
  firstLoad,
  formatKg,
  newStationId,
  sameLoadContext,
  stationChoicesFor,
  stationLabel,
  type LoadContext,
  type MeasuredMode,
  type StationChoice,
} from "@/lib/resistance"
import { cn } from "@/lib/utils"
import { useTrainingRecords } from "@/store/use-training-records"
import type { LoadGrid } from "@/training"
import type { PersistedLoadGrid } from "@/training-persistence/schema"
import type { ExerciseSummary } from "@/types"

/** Steps a rack, stack or plate set plausibly moves in. Wider than that is not
 *  a load step, it is a different exercise. */
const STEP_RANGE = { min: 0.25, max: 20, step: 0.25 }
/** Where a stack starts. Zero is the bar or the bare handle. */
const START_RANGE = { min: 0, max: 60, step: 0.5 }

/** What a station can be described by. Two numbers cover a rack that steps
 *  evenly; a list covers the ones that do not. */
const FACETS = [
  { key: "step" as const, chip: "Step", label: "Set the load step" },
  { key: "start" as const, chip: "Lightest", label: "Set the lightest load" },
  {
    key: "list" as const,
    chip: "List",
    label: "List the loads this station has",
  },
]

/** One load on the dial that adds them. Machine stacks and dumbbell racks both
 *  live inside this, and half-kilo plates are the finest thing most gyms have. */
const LOAD_RANGE = { min: 0, max: 300, step: 0.5 }

/** The engine takes at most this many, and a rack nobody could count is not a
 *  rack anybody will describe. */
const MAX_LADDER_LOADS = 60

/** Sorted, without repeats: two of the same dumbbell is one available load. */
function tidyLadder(loads: readonly number[]) {
  return [...new Set(loads.map((load) => Math.round(load * 100) / 100))].sort(
    (left, right) => left - right
  )
}

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
  context,
  equipmentIncrementKg,
  exercise,
  mode,
  onSelect,
  pinSelection = true,
}: {
  /** The measurement the set on screen is being taken in. The picker follows
   *  the editor rather than the store, so a set already logged keeps the
   *  station it was performed at while another is selected for the next one. */
  context: LoadContext
  /** The load step saved for this equipment, which the default station uses
   *  until a station of its own says otherwise. */
  equipmentIncrementKg?: number
  exercise: ExerciseSummary
  /** The measurement being logged. Load and assistance are separate stations
   *  even on one machine, and never stand in for each other. */
  mode: MeasuredMode
  onSelect: (context: LoadContext) => void
  /** Whether choosing a station also makes it the exercise's station for the
   *  sets that come after. False while correcting one already performed. */
  pinSelection?: boolean
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
  const [facet, setFacet] = useState<"step" | "start" | "list">("step")
  /** The list being written, held apart from what is saved so backing out of
   *  it leaves the station exactly as it was. */
  const [ladder, setLadder] = useState<number[] | null>(null)
  const [ladderValue, setLadderValue] = useState(20)

  const saved = stationChoicesFor(
    exercise,
    mode,
    settings,
    equipmentIncrementKg
  )
  const defaultStationId = saved[0].context.stationId
  // A set can name a station nothing describes any more — one deleted after it
  // was logged. It stays on screen as its own chip so the set can be read and
  // corrected, and so it can never be mistaken for a station that still exists.
  const choices: StationChoice[] = saved.some((choice) =>
    sameLoadContext(choice.context, context)
  )
    ? saved
    : [
        ...saved,
        {
          id: null,
          label: stationLabel(context.stationId, defaultStationId),
          context,
        },
      ]
  const active =
    choices.find((choice) => sameLoadContext(choice.context, context)) ??
    choices[0]
  const grid = active.context.grid
  const isLadder = "availableLoadsKg" in grid
  // A station described by a list stays described by one until somebody says
  // otherwise: an imported ladder is never quietly rounded into even steps.
  const facetInUse = isLadder && facet !== "list" ? "convert" : facet
  const draft = ladder ?? (isLadder ? [...grid.availableLoadsKg] : [])

  /** Describes the selected station. The grid is what the machine offers; the
   *  kilograms already logged against it are untouched by saying so. */
  const write = (patch: PersistedLoadGrid) => {
    const id = saveLoadConfiguration({
      ...(active.id ? { id: active.id } : {}),
      exerciseId: exercise.id,
      stationId: active.context.stationId,
      mode,
      basis: active.context.basis,
      grid: patch,
    })
    if (!active.id && pinSelection) selectLoadConfiguration(exercise.id, id)
    onSelect({ ...active.context, grid: structuredClone(patch) as LoadGrid })
  }

  const stepPatch = (patch: {
    incrementKg?: number
    minimumKg?: number
  }): PersistedLoadGrid => ({
    incrementKg:
      patch.incrementKg ?? ("incrementKg" in grid ? grid.incrementKg : 2.5),
    minimumKg:
      patch.minimumKg ?? ("minimumKg" in grid ? (grid.minimumKg ?? 0) : 0),
  })

  const choose = (choice: StationChoice) => {
    triggerHaptic("selection")
    if (sameLoadContext(choice.context, active.context))
      return setEditing((open) => !open)
    if (pinSelection)
      selectLoadConfiguration(exercise.id, choice.id ?? pin(choice))
    onSelect(choice.context)
    setEditing(false)
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
    // A fresh identity every time, never one a deleted station used to hold:
    // sets logged at a machine that is gone must not turn out to be comparable
    // with the next machine described.
    const stationId = newStationId(defaultStationId)
    const seed = choices[0].context.grid
    const grid: PersistedLoadGrid =
      "availableLoadsKg" in seed
        ? { availableLoadsKg: [...seed.availableLoadsKg] }
        : { incrementKg: seed.incrementKg, minimumKg: seed.minimumKg ?? 0 }
    const id = saveLoadConfiguration({
      exerciseId: exercise.id,
      stationId,
      mode,
      basis: choices[0].context.basis,
      grid,
    })
    if (pinSelection) selectLoadConfiguration(exercise.id, id)
    onSelect({
      stationId,
      basis: choices[0].context.basis,
      grid: structuredClone(grid) as LoadGrid,
    })
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
                onClick={() => choose(choice)}
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
          {/* One dial at a time: a phone has room for a knob you can actually
              turn, not for three of them side by side. */}
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
                  if (item.key !== "list") setLadder(null)
                }}
                type="button"
              >
                {item.chip}
              </button>
            ))}
          </div>
          {facetInUse === "list" ? (
            <>
              <div
                className="-mx-1 mt-2 flex flex-wrap justify-center gap-1.5"
                data-swipe-ignore
              >
                {tidyLadder(draft).map((load) => (
                  <button
                    aria-label={`Remove ${formatKg(load)} kg from ${active.label}`}
                    className="preset-chip hit-target shrink-0 gap-1 px-3 text-sm"
                    data-haptics="off"
                    key={load}
                    onClick={() => {
                      triggerHaptic("selection")
                      setLadder(draft.filter((item) => item !== load))
                    }}
                    type="button"
                  >
                    {formatKg(load)}
                    <X className="size-3.5 opacity-70" />
                  </button>
                ))}
                {draft.length === 0 ? (
                  <p className="py-2 text-[11px] text-muted-foreground">
                    Add every load this station actually has.
                  </p>
                ) : null}
              </div>
              <RotaryKnob
                ariaLabel={`${active.label} load to add`}
                className="mx-auto mt-2"
                format={formatKg}
                max={LOAD_RANGE.max}
                min={LOAD_RANGE.min}
                onChange={setLadderValue}
                size={240}
                step={LOAD_RANGE.step}
                unit="kg"
                value={ladderValue}
              />
              <div className="mt-2 flex items-center gap-2">
                <Button
                  className="h-10 flex-1 rounded-2xl"
                  disabled={
                    draft.includes(ladderValue) ||
                    draft.length >= MAX_LADDER_LOADS
                  }
                  onClick={() => {
                    triggerHaptic("selection")
                    setLadder(tidyLadder([...draft, ladderValue]))
                  }}
                  variant="secondary"
                >
                  <Plus className="size-4" />
                  Add {formatKg(ladderValue)} kg
                </Button>
                <Button
                  className="h-10 flex-1 rounded-2xl"
                  disabled={draft.length === 0}
                  onClick={() => {
                    triggerHaptic("success")
                    write({ availableLoadsKg: tidyLadder(draft) })
                    setLadder(null)
                  }}
                >
                  Save loads
                </Button>
              </div>
              {ladder ? (
                <button
                  aria-label={`Discard changes to ${active.label} loads`}
                  className="interactive-spring mt-1 h-9 w-full rounded-2xl text-xs font-bold text-muted-foreground"
                  onClick={() => {
                    triggerHaptic("selection")
                    setLadder(null)
                  }}
                  type="button"
                >
                  Cancel
                </button>
              ) : null}
            </>
          ) : facetInUse === "convert" ? (
            // Turning a list into even steps throws away what it says, so it
            // is a thing to press rather than something a dial does behind it.
            <div className="mt-2 space-y-2 text-center">
              <p className="text-[11px] text-muted-foreground">
                This station is described by the loads it has.
              </p>
              <Button
                className="h-10 w-full rounded-2xl"
                onClick={() => {
                  triggerHaptic("warning")
                  write({
                    incrementKg: 2.5,
                    minimumKg: isLadder ? firstLoad(grid) : 0,
                  })
                  setFacet("step")
                }}
                variant="secondary"
              >
                Use even steps instead
              </Button>
            </div>
          ) : (
            <>
              <RotaryKnob
                ariaLabel={`${active.label} ${facet === "step" ? "load step" : "lightest load"}`}
                className="mx-auto mt-2"
                format={formatKg}
                max={facet === "step" ? STEP_RANGE.max : START_RANGE.max}
                min={facet === "step" ? STEP_RANGE.min : START_RANGE.min}
                onChange={(value) =>
                  write(
                    stepPatch(
                      facet === "step"
                        ? { incrementKg: value }
                        : { minimumKg: value }
                    )
                  )
                }
                size={240}
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
