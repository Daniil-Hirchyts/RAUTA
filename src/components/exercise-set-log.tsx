import { useMemo, useState } from "react"
import { motion } from "motion/react"
import { Plus } from "lucide-react"

import { SetEditor, type SetEditorValue } from "@/components/set-editor"
import { EXERCISES_BY_ID } from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { EASE_SMOOTH_OUT } from "@/lib/motion"
import {
  formatKg,
  formatResistance,
  loadContextFor,
  makeResistance,
  resistanceModes,
  type ResistanceMode,
} from "@/lib/resistance"
import { draftExercise } from "@/lib/training-session"
import { cn } from "@/lib/utils"
import { useFilters } from "@/store/use-filters"
import { useTrainingRecords } from "@/store/use-training-records"
import type {
  PersistedActiveSetDraft,
  PersistedCompletedSession,
  PersistedResistance,
  PersistedSetTarget,
} from "@/training-persistence/schema"

const EDITOR_TRANSITION = { duration: 0.24, ease: EASE_SMOOTH_OUT }

/** The set the editor opens on when nothing has been performed yet. Reps are a
 *  starting point for the dial, not a claim about the set: nothing is recorded
 *  until it is confirmed. */
const BLANK_REPS = 10

function editorValueOf(
  resistance: PersistedResistance,
  reps: number,
  rir: number | undefined,
  side: PersistedActiveSetDraft["side"]
): SetEditorValue {
  return {
    mode: resistance.type,
    kg: "kg" in resistance ? resistance.kg : 0,
    reps,
    rir: rir ?? null,
    side,
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
    "kg" in target.resistance ? ` · ${formatKg(target.resistance.kg)} kg` : ""
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
  const draft = useTrainingRecords((state) => state.data.activeWorkout)
  const sessions = useTrainingRecords((state) => state.data.sessions)
  const configuration = useTrainingRecords((state) =>
    state.data.settings.loadConfigurations.find(
      (item) => item.exerciseId === exerciseId
    )
  )
  const equipmentIncrementKg = useFilters((state) =>
    exercise ? state.equipmentLoadIncrements[exercise.equipment] : undefined
  )
  const addUnplannedSet = useTrainingRecords((state) => state.addUnplannedSet)
  const recordSet = useTrainingRecords((state) => state.recordSet)
  const updateSetDetails = useTrainingRecords((state) => state.updateSetDetails)
  const discardLoggedSet = useTrainingRecords((state) => state.discardLoggedSet)

  const entry = draftExercise(draft, exerciseId)
  const [editedSetId, setEditedSetId] = useState<string | null>(null)
  const [pending, setPending] = useState<SetEditorValue | null>(null)

  const modes = useMemo<ResistanceMode[]>(
    () => (exercise ? resistanceModes(exercise) : ["external_load"]),
    [exercise]
  )

  // What the editor opens on: this session's last set for the exercise, then
  // the last one from history, then a blank dial. Prefilling the editor is a
  // convenience; it becomes a record only when the person confirms it.
  const defaults = useMemo<SetEditorValue>(() => {
    const previous = entry?.sets
      .toReversed()
      .find((set) => set.observation?.completed)
    if (previous?.observation?.resistance)
      return editorValueOf(
        previous.observation.resistance,
        previous.observation.reps ?? BLANK_REPS,
        previous.observation.rir,
        previous.side
      )
    const performed = lastPerformedSet(sessions, exerciseId)
    if (performed)
      return editorValueOf(
        performed.resistance,
        performed.reps,
        performed.rir,
        performed.side
      )
    return { mode: modes[0], kg: 0, reps: BLANK_REPS, rir: null, side: "both" }
  }, [entry, exerciseId, modes, sessions])

  if (!exercise || !entry) return null

  const value = pending ?? defaults
  const context = loadContextFor(
    exercise,
    value.mode,
    configuration,
    equipmentIncrementKg
  )
  // The button offers the next set after the ones already on the card,
  // prescribed or performed; with an empty card it simply offers a set.
  const addSetLabel = entry.sets.length
    ? `Log set ${entry.sets.length + 1}`
    : "Log a set"
  const editedSet = entry.sets.find((set) => set.id === editedSetId) ?? null
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
        ? editorValueOf(
            set.observation.resistance,
            set.observation.reps ?? BLANK_REPS,
            set.observation.rir,
            set.side
          )
        : set?.target
          ? // A prescribed set opens on its target so it can be confirmed or
            // corrected; the target itself is never written as performed.
            editorValueOf(
              set.target.resistance,
              set.target.reps.max,
              set.target.rir,
              set.side
            )
          : null
    )
    onEditingChange(true)
  }

  const submit = () => {
    const observation = {
      reps: value.reps,
      resistance: makeResistance(value.mode, value.kg, context),
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
            <SetEditor
              context={context}
              exercise={exercise}
              modes={modes}
              onCancel={close}
              onChange={(update) =>
                setPending((previous) => update(previous ?? defaults))
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
