import { useMemo, useState } from "react"

import { RestCountdown } from "@/components/rest-countdown"
import { SetEditor, type SetEditorValue } from "@/components/set-editor"
import { EXERCISES_BY_ID } from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { cueRauta } from "@/lib/rauta-cues"
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
import type {
  PersistedActiveSetDraft,
  PersistedCompletedSession,
  PersistedResistance,
  PersistedSetTarget,
  PersistedTrainingSettings,
} from "@/training-persistence/schema"
import type { ExerciseSummary } from "@/types"

/** The set the editor opens on when nothing has been performed and nothing was
 *  prescribed. Reps are a starting point for the dial, not a claim about the
 *  set: nothing is recorded until it is confirmed. */
const BLANK_REPS = 10

/** The rest to count down when nothing prescribed one. */
const DEFAULT_REST_SECONDS = 90

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
  exerciseId,
  restSeconds = DEFAULT_REST_SECONDS,
}: {
  exerciseId: string
  /** What the week asks between sets of this exercise. */
  restSeconds?: number
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
  /** The rest started by the last saved set. The id makes each one its own
   *  countdown rather than a continuation of the one before. */
  const [rest, setRest] = useState<{ id: number; seconds: number } | null>(null)
  const [pending, setPending] = useState<SetEditorValue | null>(null)
  // The engine is asked about the measurement on screen, so what RAUTA says
  // and what the dial collects are one statement.
  const loggedMode = pending?.mode

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
        ? nextPerformance(
            entry,
            undefined,
            data,
            increments,
            loggedMode,
            pending?.context
          )
        : null,
    [data, entry, increments, loggedMode, pending?.context]
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
    const planned = entry?.sets.find((set) => set.target)?.target
    const previous = entry?.sets
      .toReversed()
      .find((set) => set.observation?.completed)?.observation
    // The engine resolves the same station this editor is on, so a load it
    // names is already comparable; anything else it returns is calibration,
    // which is not a load at all.
    const engine =
      recommendation &&
      recommendation.resistance.type === mode &&
      "kg" in recommendation.resistance &&
      sameLoadContext(recommendation.resistance, context)
        ? recommendation
        : null
    return {
      mode,
      // A kilogram is only offered again when it was measured at this same
      // station, in this same basis. Where nothing is known the dial opens at
      // zero rather than empty: a set can be logged from the bar and stepped
      // up, which is what finding a working load actually looks like.
      kg:
        (previous ? carryOverLoad(previous.resistance, mode, context) : null) ??
        (engine && "kg" in engine.resistance ? engine.resistance.kg : null) ??
        (isMeasuredInKg(mode) ? 0 : null),
      // Reps and effort carry over freely — they describe the person, not the
      // machine — and fall back to what the week asked for.
      reps:
        previous?.reps ??
        engine?.targetReps.max ??
        planned?.reps.max ??
        BLANK_REPS,
      rir: previous?.rir ?? planned?.rir ?? null,
      side: "both",
      context,
    }
  }, [entry, modes, nextContext, recommendation])

  /** What the editor shows for a set: the observation to correct, the
   *  prescription to confirm, or a blank dial for a set nobody planned. */
  const valueFor = (set: PersistedActiveSetDraft | null): SetEditorValue => {
    if (!exercise) return defaults
    if (set?.observation?.resistance)
      return recordedValue(
        exercise,
        set.observation,
        set.side,
        settings,
        equipmentIncrementKg
      )
    if (!set?.target) return defaults
    // A prescribed set opens on its target so it can be confirmed or
    // corrected; the target itself is never written as performed. Its load
    // only carries over where the plan and this station are the same
    // measurement — a target from another machine stays on the card as the
    // prescription and never becomes an actual load here.
    return {
      ...defaults,
      reps: set.target.reps.max,
      rir: set.target.rir,
      side: set.side,
      // The prescription first, where it names a load measured the same way;
      // otherwise whatever the sets already performed establish, which is what
      // an unprescribed dial opens on too.
      kg:
        carryOverLoad(set.target.resistance, defaults.mode, defaults.context) ??
        defaults.kg,
    }
  }

  if (!exercise || !entry) return null

  /** The set being performed: the first one nobody has logged yet, or a new
   *  one where the prescription is finished. Nothing selected means this one —
   *  there is no button to add a set, because the next set is already the row
   *  in front of you. */
  const currentSet =
    entry.sets.find((set) => !set.observation?.completed) ?? null
  const editedSet =
    (editedSetId ? entry.sets.find((set) => set.id === editedSetId) : null) ??
    currentSet
  const value = pending ?? valueFor(editedSet)
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
  // The working set is the prescription somebody is training towards; a warm-up
  // target is real but is not what this card is a summary of.
  const target =
    entry.sets.find((set) => set.setType === "working" && set.target)?.target ??
    entry.sets.find((set) => set.target)?.target
  // What the engine makes of the load — and only for an exercise that carries
  // one. There is nothing to say about the load of a set done in reps.
  const note =
    recommendation && isMeasuredInKg(modes[0])
      ? progressionNote(recommendation, previousKg)
      : null

  /** The load really logged in this measurement at this station — this
   *  session first, then history — or nothing at all. */
  const carried = (mode: ResistanceMode, context: LoadContext) => {
    for (const set of entry.sets.toReversed()) {
      if (!set.observation?.completed) continue
      const load = carryOverLoad(set.observation.resistance, mode, context)
      if (load !== null) return load
    }
    const next = nextPerformance(
      entry,
      undefined,
      data,
      increments,
      mode,
      context
    )
    return next && next.action !== "calibrate"
      ? carryOverLoad(next.resistance, mode, context)
      : null
  }

  /** There is nowhere to close to: leaving a correction goes back to the set
   *  being performed rather than to an empty card. */
  const close = () => {
    setEditedSetId(null)
    setPending(null)
  }

  const selectSet = (set: PersistedActiveSetDraft) => {
    triggerHaptic("selection")
    setEditedSetId(set.id)
    setPending(null)
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
    // The rest starts with the set that earned it.
    setRest((current) => ({
      id: (current?.id ?? 0) + 1,
      seconds: Math.round(restSeconds),
    }))
    cueRauta("set-saved")
    close()
  }

  return (
    <div className="mx-(--app-content-inset) mt-1.5 rounded-3xl border border-border bg-card/60 p-2.5">
      {/* What the week asked of this exercise, said once and quietly: a chip
          rather than a heading, because the sets under it are the page. The
          rest between them counts down on the same line. */}
      {target || note || rest ? (
        <div className="flex items-center gap-x-2 gap-y-1 px-1 pb-2.5">
          {target ? (
            <span className="shrink-0 rounded-full bg-primary/12 px-2.5 py-1 text-[11px] font-bold text-primary">
              {targetSummary(target)}
            </span>
          ) : null}
          {note ? (
            <span className="min-w-0 flex-1 truncate text-[11px] leading-snug text-muted-foreground">
              {note.kg === null
                ? null
                : `${formatKg(note.kg)} kg${note.basis === "per_implement" ? " each" : ""} · `}
              {note.text}
            </span>
          ) : null}
          {rest ? (
            <RestCountdown
              key={rest.id}
              onDone={() => setRest(null)}
              seconds={rest.seconds}
            />
          ) : null}
        </div>
      ) : null}

      {entry.sets.length ? (
        <>
          <div className="grid grid-cols-[1.5rem_1fr_2.75rem_2.75rem] gap-1.5 border-b border-border/60 px-2 pb-1.5 text-[9px] font-bold tracking-[0.12em] text-muted-foreground/70 uppercase">
            <Column>{""}</Column>
            <Column>Load</Column>
            <Column className="text-right">Reps</Column>
            <Column className="text-right">RIR</Column>
          </div>
          <ol className="space-y-1 pt-1">
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
                      editedSet?.id === set.id
                        ? "bg-primary/12 text-foreground"
                        : observation
                          ? "bg-muted/40"
                          : "bg-muted/20 text-muted-foreground"
                    )}
                    onClick={() => selectSet(set)}
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

      <div className="pt-2">
        <SetEditor
          exercise={exercise}
          modes={modes}
          onCancel={editedSet?.observation?.completed ? close : undefined}
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
    </div>
  )
}
