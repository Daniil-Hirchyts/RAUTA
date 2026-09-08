import { Check, Trash2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Stepper } from "@/components/ui/stepper"
import { triggerHaptic } from "@/lib/haptics"
import {
  firstLoad,
  formatKg,
  isMeasuredInKg,
  resistanceModeLabel,
  sideOptions,
  stepLoad,
  type LoadContext,
  type ResistanceMode,
  type SetSide,
} from "@/lib/resistance"
import type { ExerciseSummary } from "@/types"

/** What the editor holds while it is being filled in. None of it is training
 *  evidence: nothing leaves this shape until the set is confirmed. */
export type SetEditorValue = {
  mode: ResistanceMode
  /**
   * The load, or null while there is none to state.
   *
   * Null is not zero. Zero is a real reading — an empty bar, a machine with no
   * assistance dialled in — while null says the load has not been established
   * yet, which is what happens when nothing comparable has been logged at this
   * station. The set cannot be recorded until it becomes a number.
   */
  kg: number | null
  reps: number
  /** Reps left in reserve, or null when the person did not judge it. */
  rir: number | null
  side: SetSide
  /**
   * Where this set is measured: its station, its basis, and the loads that
   * station offers.
   *
   * Carried on the value rather than read from the current selection, because
   * the two are not the same thing. Correcting the reps of a set logged last
   * week must leave it on the machine it was performed on, whatever machine is
   * selected for the next set.
   */
  context: LoadContext
}

const RIR_CHOICES = [null, 0, 1, 2, 3, 4] as const
const MAX_REPS = 100
const SIDE_LABELS: Record<SetSide, string> = {
  both: "Both",
  left: "Left",
  right: "Right",
}

function Chip({
  children,
  label,
  onSelect,
  selected,
}: {
  children: React.ReactNode
  label: string
  onSelect: () => void
  selected: boolean
}) {
  return (
    <button
      aria-label={label}
      aria-pressed={selected}
      className="preset-chip hit-target relative shrink-0 px-3.5 text-sm"
      data-haptics="off"
      onClick={() => {
        triggerHaptic("selection")
        onSelect()
      }}
      type="button"
    >
      {children}
    </button>
  )
}

function ChipRow({
  children,
  label,
}: {
  children: React.ReactNode
  label: string
}) {
  return (
    <div className="flex min-w-0 items-center gap-2">
      <span className="w-11 shrink-0 text-[10px] font-black tracking-[0.14em] text-muted-foreground uppercase">
        {label}
      </span>
      <div
        className="flex min-w-0 flex-1 [scrollbar-width:none] gap-1.5 overflow-x-auto py-0.5 [&::-webkit-scrollbar]:hidden"
        data-swipe-ignore
      >
        {children}
      </div>
    </div>
  )
}

/**
 * The one place a performed set is described.
 *
 * Everything it collects is what happened — the load that was on the bar, the
 * reps that were completed, how many were left. What the plan asked for is
 * shown above it by the set list and never written back into these fields, so
 * a prescription cannot quietly become a record.
 */
export function SetEditor({
  exercise,
  modes,
  onCancel,
  onChange,
  onDiscard,
  onSubmit,
  submitLabel,
  value,
}: {
  exercise: ExerciseSummary
  modes: ResistanceMode[]
  onCancel?: () => void
  /** Applied to the value as it stands, so a held stepper counts every step
   *  rather than the ones a render happened to keep up with. */
  onChange: (update: (value: SetEditorValue) => SetEditorValue) => void
  onDiscard?: () => void
  onSubmit: () => void
  submitLabel: string
  value: SetEditorValue
}) {
  const sides = sideOptions(exercise)
  const measured = isMeasuredInKg(value.mode)
  const { context } = value
  // Nothing to record until the load is a number. The button says so rather
  // than accepting a set with a load nobody stated.
  const unestablished = measured && value.kg === null

  return (
    <div className="space-y-2">
      {measured ? (
        <Stepper
          canDecrement={value.kg !== null && value.kg > 0}
          display={value.kg === null ? "—" : formatKg(value.kg)}
          label={value.mode === "assistance" ? "Assistance" : "Load"}
          onStep={(direction) =>
            onChange((current) => ({
              ...current,
              // From unset, stepping up establishes the lightest load this
              // station has; stepping down states nothing at all.
              kg:
                current.kg === null
                  ? direction === 1
                    ? firstLoad(current.context.grid)
                    : null
                  : stepLoad(current.kg, direction, current.context.grid),
            }))
          }
          unit={
            context.basis === "per_implement" && value.mode === "external_load"
              ? "kg each"
              : "kg"
          }
        />
      ) : null}

      <Stepper
        canDecrement={value.reps > 1}
        display={String(value.reps)}
        label="Reps"
        onStep={(direction) =>
          onChange((current) => ({
            ...current,
            reps: Math.min(MAX_REPS, Math.max(1, current.reps + direction)),
          }))
        }
      />

      <ChipRow label="RIR">
        {RIR_CHOICES.map((choice) => (
          <Chip
            key={choice ?? "none"}
            label={
              choice === null
                ? "Do not record reps in reserve"
                : `${choice} reps in reserve`
            }
            onSelect={() =>
              onChange((current) => ({ ...current, rir: choice }))
            }
            selected={value.rir === choice}
          >
            {choice === null ? "—" : choice}
          </Chip>
        ))}
      </ChipRow>

      {modes.length > 1 ? (
        <ChipRow label="How">
          {modes.map((mode) => (
            <Chip
              key={mode}
              label={`Log as ${resistanceModeLabel(mode).toLowerCase()}`}
              onSelect={() => onChange((current) => ({ ...current, mode }))}
              selected={value.mode === mode}
            >
              {resistanceModeLabel(mode)}
            </Chip>
          ))}
        </ChipRow>
      ) : null}

      {sides.length > 1 ? (
        <ChipRow label="Side">
          {sides.map((side) => (
            <Chip
              key={side}
              label={`Performed on ${SIDE_LABELS[side].toLowerCase()}`}
              onSelect={() => onChange((current) => ({ ...current, side }))}
              selected={value.side === side}
            >
              {SIDE_LABELS[side]}
            </Chip>
          ))}
        </ChipRow>
      ) : null}

      <div className="flex items-center gap-2 pt-0.5">
        {onDiscard ? (
          <Button
            aria-label="Delete this set"
            className="size-11 shrink-0 rounded-2xl"
            onClick={() => {
              triggerHaptic("warning")
              onDiscard()
            }}
            size="icon"
            variant="destructive"
          >
            <Trash2 className="size-5" />
          </Button>
        ) : null}
        {onCancel ? (
          <Button
            className="h-11 flex-1 rounded-2xl"
            onClick={onCancel}
            variant="ghost"
          >
            Cancel
          </Button>
        ) : null}
        <Button
          className="h-11 flex-[2] rounded-2xl"
          disabled={unestablished}
          onClick={() => {
            triggerHaptic("success")
            onSubmit()
          }}
        >
          <Check className="size-5" />
          {unestablished
            ? `Dial in the ${value.mode === "assistance" ? "assistance" : "load"}`
            : submitLabel}
        </Button>
      </div>
    </div>
  )
}
