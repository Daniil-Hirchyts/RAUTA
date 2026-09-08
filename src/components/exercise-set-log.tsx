import { useMemo, useState } from "react"
import { motion } from "motion/react"
import { Plus } from "lucide-react"

import { SetEditor, type SetEditorValue } from "@/components/set-editor"
import { StationPicker } from "@/components/station-picker"
import { EXERCISES_BY_ID } from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { EASE_SMOOTH_OUT } from "@/lib/motion"
import { progressionNote } from "@/lib/progression-note"
import {
  carryOverLoad,
  formatKg,
  formatResistance,
  isMeasuredInKg,
  makeResistance,
  recordedLoadContext,
  resistanceModes,
  resolveLoadContext,
  sameLoadContext,
  type LoadContext,
  type ResistanceMode,
} from "@/lib/resistance"
import { draftExercise } from "@/lib/training-session"
import { nextPerformance } from "@/lib/training-workflow"
import { cn } from "@/lib/utils"
import { useFilters } from "@/store/use-filters"
import { useTrainingRecords } from "@/store/use-training-records"
import { roundLoad } from "@/training"
import type {
  PersistedActiveSetDraft,
  PersistedCompletedSession,
  PersistedResistance,
  PersistedSetTarget,
  PersistedTrainingSettings,
} from "@/training-persistence/schema"
import type { ExerciseSummary } from "@/types"

const EDITOR_TRANSITION = { duration: 0.24, ease: EASE_SMOOTH_OUT }

/** The set the editor opens on when nothing has been performed yet. Reps are a
 *  starting point for the dial, not a claim about the set: nothing is recorded
 *  until it is confirmed. */
const BLANK_REPS = 10

/**
 * The editor opened on a set that was already performed.
 *
 * Its station comes from the observation, never from whatever is selected now:
 * correcting the reps of a set logged on one machine must not move it to
 * another. The load is its own, so no compatibility question arises.
 */
function recordedValue(
  exercise: ExerciseSummary,
  observation: NonNullable<PersistedActiveSetDraft["observation"]>,
  side: PersistedActiveSetDraft["side"],
  settings: PersistedTrainingSettings,
  equipmentIncrementKg: number | undefined
): SetEditorValue {
  // A draft observation can exist without a resistance; it is then a set with
  // reps and nothing said about load, and the editor opens on the exercise's
  // own measurement rather than inventing one.
  const resistance: PersistedResistance = observation.resistance ?? {
    type: "unknown",
  }
  return {
    mode: resistance.type,
    kg: "kg" in resistance ? resistance.kg : null,
    reps: observation.reps ?? BLANK_REPS,
    rir: observation.rir ?? null,
    side,
    context: recordedLoadContext(
      exercise,
      resistance,
      settings,
      equipmentIncrementKg
    ),
  }
}

/** The last set of this exercise the person actually performed, in any earlier
 *  session. Repeating a workout should not mean dialling the same load in from
 *  zero again. */
function lastPerformedSet(
  sessions: readonly PersistedCompletedSession[],
  exerciseId: string
) {
  for (let index = sessions.length - 1; index >= 0; index -= 1) {
    for (const exercise of sessions[index].exercises.toReversed()) {
      if (exercise.exerciseId !== exerciseId) continue
      const set = exercise.sets.at(-1)
      if (set) return set
    }
  }
  return null
}

function targetSummary(target: PersistedSetTarget) {
  const reps =
    target.reps.min === target.reps.max
      ? `${target.reps.max}`
      : `${target.reps.min}–${target.reps.max}`
  const load =
    "kg" in target.resistance ? ` · ${formatResistance(target.resistance)}` : ""
  return `${reps} reps · RIR ${target.rir}${load}`
}

function Column({
  children,
  className,
}: {
  children: React.ReactNode
  className?: string
}) {
  return (
    <span className={cn("truncate tabular-nums", className)}>{children}</span>
  )
}

/**
 * The performed sets of one exercise, inside the exercise it belongs to.
 *
 * This is the whole of set logging: no second workout screen, no spreadsheet.
 * The list above the editor is what was done — load, reps, reps in reserve —
 * and a planned set that has not been performed shows its target with dashes
 * where the actual values will go, so the two are never confused for each
 * other on screen either.
 */
export function ExerciseSetLog({
  editing,
  exerciseId,
  onEditingChange,
}: {
  /** True while this exercise's editor is the open one. */
  editing: boolean
  exerciseId: string
  onEditingChange: (editing: boolean) => void
}) {
  const exercise = EXERCISES_BY_ID.get(exerciseId)
  const data = useTrainingRecords((state) => state.data)
  const increments = useFilters((state) => state.equipmentLoadIncrements)
  const { activeWorkout: draft, sessions, settings } = data
  const equipmentIncrementKg = exercise
    ? increments[exercise.equipment]
    : undefined
  const addUnplannedSet = useTrainingRecords((state) => state.addUnplannedSet)
  const recordSet = useTrainingRecords((state) => state.recordSet)
  const updateSetDetails = useTrainingRecords((state) => state.updateSetDetails)
  const discardLoggedSet = useTrainingRecords((state) => state.discardLoggedSet)

  const entry = draftExercise(draft, exerciseId)
  const [editedSetId, setEditedSetId] = useState<string | null>(null)
  const [pending, setPending] = useState<SetEditorValue | null>(null)
  // While the editor is open the engine is asked about the measurement on
  // screen, so what RAUTA says and what the dial collects are one statement.
  const loggedMode = editing ? pending?.mode : undefined

  const modes = useMemo<ResistanceMode[]>(
    () => (exercise ? resistanceModes(exercise) : ["external_load"]),
    [exercise]
  )

  // What the deterministic engine makes of this exercise right now, from the
  // sets that were actually logged and the station they were logged at. It is
  // recomputed from persisted records rather than remembered, so it can never
  // outlive the evidence it was drawn from.
  const recommendation = useMemo(
    () =>
      entry
        ? nextPerformance(entry, undefined, data, increments, loggedMode)
        : null,
    [data, entry, increments, loggedMode]
  )

  // Where the next set will be measured: the station selected for this
  // exercise, in the measurement this exercise is logged in. Every prefill
  // below is judged against it.
  const nextContext = useMemo(
    () =>
      exercise
        ? resolveLoadContext(exercise, modes[0], settings, equipmentIncrementKg)
        : null,
    [equipmentIncrementKg, exercise, modes, settings]
  )

  /**
   * What the editor opens on for a set that has not been performed.
   *
   * Reps and effort carry over freely — they describe the person, not the
   * machine. A kilogram does not: it is only offered again when it was
   * measured at this same station, in this same basis, and is a load the
   * station still has. Where none of that holds the dial opens unset, because
   * the honest answer to "what should be on the bar" is that nobody knows yet.
   */
  const defaults = useMemo<SetEditorValue>(() => {
    const mode = modes[0]
    const context =
      nextContext ??
      ({
        stationId: "unknown",
        basis: "total",
        grid: { incrementKg: 2.5 },
      } as const)
    const blank: SetEditorValue = {
      mode,
      kg: null,
      reps: BLANK_REPS,
      rir: null,
      side: "both",
      context,
    }
    const previous = entry?.sets
      .toReversed()
      .find((set) => set.observation?.completed)?.observation
    if (previous)
      return {
        ...blank,
        kg: carryOverLoad(previous.resistance, mode, context),
        reps: previous.reps ?? BLANK_REPS,
        rir: previous.rir ?? null,
      }
    // The engine resolves the same station this editor is on, so a load it
    // names is already comparable; anything else it returns is calibration,
    // and calibration is a blank dial rather than a guess.
    if (
      recommendation &&
      recommendation.resistance.type === mode &&
      "kg" in recommendation.resistance &&
      sameLoadContext(recommendation.resistance, context)
    )
      return {
        ...blank,
        kg: recommendation.resistance.kg,
        reps: recommendation.targetReps.max,
      }
    const performed = lastPerformedSet(sessions, exerciseId)
    if (performed) {
      const kg = carryOverLoad(performed.resistance, mode, context)
      return kg === null
        ? blank
        : { ...blank, kg, reps: performed.reps, rir: performed.rir ?? null }
    }
    return blank
  }, [entry, exerciseId, modes, nextContext, recommendation, sessions])

  if (!exercise || !entry) return null

  const value = pending ?? defaults
  // The button offers the next set after the ones already on the card,
  // prescribed or performed; with an empty card it simply offers a set.
  const addSetLabel = entry.sets.length
    ? `Log set ${entry.sets.length + 1}`
    : "Log a set"
  const editedSet = entry.sets.find((set) => set.id === editedSetId) ?? null
  const previous = lastPerformedSet(sessions, exerciseId)
  // A step is only quoted when it is a step from the same measurement: the
  // difference between two stations is not a progression.
  const previousKg =
    previous &&
    "kg" in previous.resistance &&
    recommendation &&
    "kg" in recommendation.resistance &&
    previous.resistance.stationId === recommendation.resistance.stationId &&
    previous.resistance.basis === recommendation.resistance.basis
      ? previous.resistance.kg
      : undefined
  const note = recommendation
    ? progressionNote(recommendation, previousKg)
    : null
  // The working set is the prescription somebody is training towards; a warm-up
  // target is real but is not what this card is a summary of.
  const target =
    entry.sets.find((set) => set.setType === "working" && set.target)?.target ??
    entry.sets.find((set) => set.target)?.target

  const close = () => {
    setPending(null)
    setEditedSetId(null)
    onEditingChange(false)
  }

  const openFor = (set: PersistedActiveSetDraft | null) => {
    triggerHaptic("selection")
    setEditedSetId(set?.id ?? null)
    setPending(
      set?.observation?.resistance
        ? recordedValue(
            exercise,
            set.observation,
            set.side,
            settings,
            equipmentIncrementKg
          )
        : set?.target
          ? // A prescribed set opens on its target so it can be confirmed or
            // corrected; the target itself is never written as performed. Its
            // load only carries over where the plan and this station are the
            // same measurement — a target from another machine stays on the
            // card as the prescription and never becomes an actual load here.
            {
              ...defaults,
              reps: set.target.reps.max,
              rir: set.target.rir,
              side: set.side,
              // The prescription first, where it names a load measured the
              // same way; otherwise whatever the sets already performed
              // establish, which is what an unprescribed dial opens on too.
              kg:
                carryOverLoad(
                  set.target.resistance,
                  defaults.mode,
                  defaults.context
                ) ?? defaults.kg,
            }
          : null
    )
    onEditingChange(true)
  }

  /**
   * Moving the set being edited to another station.
   *
   * For a set already logged this is a correction: the kilograms were real, so
   * they stay, snapped to what the station it is being moved to actually
   * offers. For a set not yet performed the load has to be established again —
   * a number from one machine is not a number for another — so it falls back
   * to whatever was really logged at the station now selected, and to nothing
   * when that is nothing.
   */
  /** The load really logged in this measurement at this station — this
   *  session first, then history — or nothing at all. */
  const carried = (mode: ResistanceMode, context: LoadContext) =>
    carryOverLoad(
      entry.sets.toReversed().find((set) => set.observation?.completed)
        ?.observation?.resistance,
      mode,
      context
    ) ??
    carryOverLoad(
      lastPerformedSet(sessions, exerciseId)?.resistance,
      mode,
      context
    )

  const selectStation = (context: LoadContext) => {
    setPending((current) => {
      const from = current ?? defaults
      if (sameLoadContext(from.context, context)) return { ...from, context }
      if (editedSet?.observation?.completed)
        return {
          ...from,
          context,
          kg:
            from.kg === null
              ? null
              : (roundLoad(from.kg, context.grid) ?? from.kg),
        }
      return { ...from, context, kg: carried(from.mode, context) }
    })
  }

  const submit = () => {
    if (isMeasuredInKg(value.mode) && value.kg === null) return
    const observation = {
      reps: value.reps,
      resistance: makeResistance(value.mode, value.kg ?? 0, value.context),
      ...(value.rir === null ? {} : { rir: value.rir }),
      completed: true,
      timestamp: new Date().toISOString(),
    }
    if (editedSet) {
      if (editedSet.side !== value.side)
        updateSetDetails(entry.id, editedSet.id, {
          setType: editedSet.setType,
          side: value.side,
        })
      recordSet({
        exerciseEntryId: entry.id,
        setDraftId: editedSet.id,
        observation,
      })
    } else {
      addUnplannedSet({
        exerciseEntryId: entry.id,
        setType: "working",
        side: value.side,
        observation,
      })
    }
    close()
  }

  return (
    <div className="mx-(--app-content-inset) mt-1.5 rounded-3xl border border-border bg-card/60 p-2.5">
      {target ? (
        <p className="px-1 pb-2 text-[11px] font-semibold text-muted-foreground">
          <span className="font-black tracking-[0.14em] text-primary uppercase">
            Target
          </span>{" "}
          {targetSummary(target)}
        </p>
      ) : null}

      {note ? (
        <p className="px-1 pb-2 text-[11px] leading-snug font-semibold text-muted-foreground">
          <span className="mr-1 font-black tracking-[0.14em] text-primary uppercase">
            Rauta
          </span>
          {note.kg === null
            ? null
            : `${formatKg(note.kg)} kg${note.basis === "per_implement" ? " each" : ""} · `}
          {note.text}
        </p>
      ) : null}

      {entry.sets.length ? (
        <>
          <div className="grid grid-cols-[1.5rem_1fr_2.75rem_2.75rem] gap-1.5 px-2 pb-1 text-[10px] font-black tracking-[0.14em] text-muted-foreground uppercase">
            <Column>Set</Column>
            <Column>Load</Column>
            <Column className="text-right">Reps</Column>
            <Column className="text-right">RIR</Column>
          </div>
          <ol className="space-y-1">
            {entry.sets.map((set, index) => {
              const observation = set.observation?.completed
                ? set.observation
                : null
              return (
                <li key={set.id}>
                  <button
                    aria-label={
                      observation
                        ? `Edit set ${index + 1} of ${exercise.name}`
                        : `Log set ${index + 1} of ${exercise.name}`
                    }
                    className={cn(
                      "interactive-spring grid w-full grid-cols-[1.5rem_1fr_2.75rem_2.75rem] items-center gap-1.5 rounded-2xl px-2 py-2.5 text-left text-[15px] font-semibold",
                      editedSetId === set.id
                        ? "bg-primary/12 text-foreground"
                        : observation
                          ? "bg-muted/40"
                          : "bg-muted/20 text-muted-foreground"
                    )}
                    onClick={() => openFor(set)}
                    type="button"
                  >
                    <Column className="text-primary">{index + 1}</Column>
                    <Column className="font-bold">
                      {observation?.resistance
                        ? formatResistance(observation.resistance)
                        : "—"}
                    </Column>
                    <Column className="text-right font-bold">
                      {observation?.reps ?? "—"}
                    </Column>
                    <Column className="text-right">
                      {observation?.rir ?? "—"}
                    </Column>
                  </button>
                </li>
              )
            })}
          </ol>
        </>
      ) : null}

      {editing ? (
        <motion.div
          animate={{ height: "auto", opacity: 1 }}
          className="overflow-hidden"
          initial={{ height: 0, opacity: 0 }}
          transition={EDITOR_TRANSITION}
        >
          <div className="pt-2">
            {isMeasuredInKg(value.mode) ? (
              <div className="pb-2">
                <StationPicker
                  context={value.context}
                  equipmentIncrementKg={equipmentIncrementKg}
                  exercise={exercise}
                  mode={value.mode}
                  onSelect={selectStation}
                  // Choosing where the next set happens is a statement about
                  // today. Correcting a set already logged is a statement
                  // about that set alone, and must not repoint the exercise.
                  pinSelection={!editedSet?.observation?.completed}
                />
              </div>
            ) : null}
            <SetEditor
              exercise={exercise}
              modes={modes}
              onCancel={close}
              onChange={(update) =>
                setPending((previous) => {
                  const from = previous ?? defaults
                  const next = update(from)
                  if (next.mode === from.mode) return next
                  // Another measurement is another question: load and
                  // assistance are not each other's numbers, so the station is
                  // resolved again and the dial keeps only what was really
                  // logged in the measurement now selected.
                  const context = resolveLoadContext(
                    exercise,
                    next.mode,
                    settings,
                    equipmentIncrementKg
                  )
                  return { ...next, context, kg: carried(next.mode, context) }
                })
              }
              onDiscard={
                editedSet && !editedSet.plannedSetId
                  ? () => {
                      discardLoggedSet(entry.id, editedSet.id)
                      close()
                    }
                  : undefined
              }
              onSubmit={submit}
              submitLabel={
                editedSet
                  ? `Save set ${entry.sets.indexOf(editedSet) + 1}`
                  : `Log set ${entry.sets.length + 1}`
              }
              value={value}
            />
          </div>
        </motion.div>
      ) : (
        <button
          aria-label={`${addSetLabel} of ${exercise.name}`}
          className="interactive-spring mt-1.5 flex h-11 w-full items-center justify-center gap-1.5 rounded-2xl border border-border bg-card text-[15px] font-bold text-primary"
          onClick={() => openFor(null)}
          type="button"
        >
          <Plus className="size-4" />
          {addSetLabel}
        </button>
      )}
    </div>
  )
}
