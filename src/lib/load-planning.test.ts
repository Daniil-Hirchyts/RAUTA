import { beforeEach, describe, expect, it } from "vitest"

import { formatPrescription } from "@/lib/training-plan"
import {
  engineLoadPreferences,
  generateAndSavePlan,
  planningEquipment,
} from "@/lib/training-workflow"
import { useFilters } from "@/store/use-filters"
import { useTrainingRecords } from "@/store/use-training-records"
import { useWorkouts } from "@/store/use-workouts"
import { createEmptyPersistedTrainingState } from "@/training-persistence/schema"
import type { PersistedResistance } from "@/training-persistence/schema"

/**
 * The load half of the integration, end to end.
 *
 * The engine will not name a kilogram until it is told where kilograms are
 * measured and in what steps. Everything the application already knows — the
 * equipment the person has, the step their gym actually offers, the stations
 * they named — has to reach the request as exactly that, or a week of real
 * training still comes back as "calibrate" forever.
 */
const BARBELL_BENCH = "0025"
const store = () => useTrainingRecords.getState()

const SETUP = {
  profile: {
    age: 32,
    trainingExperience: "intermediate" as const,
    health: { status: "healthy" as const },
  },
  preferences: {
    goal: "hypertrophy" as const,
    availableEquipment: planningEquipment,
    maxSessionDurationMinutes: 60,
  },
}

/** Three completed working sets at the top of the range, twice. Real logged
 *  evidence is the only thing that may move a load. */
function logSessions(resistance: PersistedResistance, days = [1, 4]) {
  for (const day of days) {
    store().startFreeWorkout([BARBELL_BENCH], `2026-09-0${day}T10:00:00.000Z`)
    const exercise = store().data.activeWorkout!.exercises[0]
    for (let set = 0; set < 3; set += 1) {
      const setDraftId = store().addUnplannedSet({
        exerciseEntryId: exercise.id,
        setType: "working",
        side: "both",
      })
      store().recordSet({
        exerciseEntryId: exercise.id,
        setDraftId,
        observation: {
          reps: 12,
          rir: 2,
          resistance,
          completed: true,
          timestamp: `2026-09-0${day}T10:1${set}:00.000Z`,
        },
      })
    }
    store().completeWorkout("completed", `2026-09-0${day}T10:30:00.000Z`)
  }
}

function plannedBench() {
  const { result } = generateAndSavePlan(SETUP, "2026-09-06T10:00:00.000Z")
  const program = "program" in result ? result.program : null
  return program?.weeks
    .flatMap((week) => week.sessions)
    .flatMap((session) => session.exercises)
    .find((exercise) => exercise.exerciseId === BARBELL_BENCH)
}

describe("load context reaching the engine", () => {
  beforeEach(() => {
    localStorage.clear()
    useTrainingRecords.setState({ data: createEmptyPersistedTrainingState() })
    useWorkouts.setState({ workouts: [] })
    useFilters.setState({ equipmentLoadIncrements: {} })
  })

  it("prescribes a load from logged sets with nothing configured at all", () => {
    logSessions({
      type: "external_load",
      kg: 80,
      stationId: "barbell",
      basis: "total",
    })

    // Top of the range at 80 kg twice, and a barbell moves in 2.5 kg steps.
    expect(plannedBench()?.workingSets[0].resistance).toEqual({
      type: "external_load",
      kg: 82.5,
      stationId: "barbell",
      basis: "total",
    })
    expect(plannedBench()?.progression.reasons).toContain("top_of_range")
  }, 30000)

  it("rounds the prescription to the step the gym actually offers", () => {
    useFilters.getState().setEquipmentLoadIncrement("barbell", 1.25)
    logSessions({
      type: "external_load",
      kg: 80,
      stationId: "barbell",
      basis: "total",
    })

    expect(plannedBench()?.workingSets[0].resistance).toMatchObject({
      kg: 81.25,
    })
  }, 30000)

  it("refuses to carry a load across to a station it was not measured at", () => {
    logSessions({
      type: "external_load",
      kg: 80,
      stationId: "barbell-2",
      basis: "total",
    })

    // Every set was performed on another bar. Nothing about this week's default
    // station has been observed, so the plan asks for the load to be found.
    const bench = plannedBench()
    expect(bench?.workingSets[0].resistance).toEqual({ type: "unknown" })
    expect(bench?.workingSets[0].loadAcquisition).toBe("calibrate_by_rir")
    expect(bench?.progression.reasons).toContain("context_changed")
  }, 30000)

  it("plans at the station the person says they are training at", () => {
    const id = store().saveLoadConfiguration({
      exerciseId: BARBELL_BENCH,
      stationId: "barbell-2",
      basis: "total",
      grid: { incrementKg: 5 },
    })
    store().selectLoadConfiguration(BARBELL_BENCH, id)
    logSessions({
      type: "external_load",
      kg: 80,
      stationId: "barbell-2",
      basis: "total",
    })

    expect(plannedBench()?.workingSets[0].resistance).toEqual({
      type: "external_load",
      kg: 85,
      stationId: "barbell-2",
      basis: "total",
    })
  }, 30000)

  it("lets an explicit station outrank the equipment's generic step", () => {
    useFilters.getState().setEquipmentLoadIncrement("barbell", 1.25)
    const id = store().saveLoadConfiguration({
      exerciseId: BARBELL_BENCH,
      stationId: "barbell",
      basis: "total",
      grid: { incrementKg: 10, minimumKg: 20 },
    })
    store().selectLoadConfiguration(BARBELL_BENCH, id)

    const preferences = engineLoadPreferences()
    expect(preferences.loadGrids?.[BARBELL_BENCH]).toEqual({
      incrementKg: 10,
      minimumKg: 20,
    })
    expect(preferences.loadContexts?.[BARBELL_BENCH]).toEqual({
      stationId: "barbell",
      basis: "total",
    })
    // Another barbell exercise keeps the generic step: a station describes one
    // exercise, not the whole equipment family.
    expect(preferences.loadGrids?.["0033"]).toEqual({
      incrementKg: 1.25,
      minimumKg: 0,
    })
  })

  it("keeps dumbbell grids per implement for the engine too", () => {
    const preferences = engineLoadPreferences()
    // 0289 is a dumbbell press: 30 kg means 30 in each hand.
    expect(preferences.loadContexts?.["0289"]).toEqual({
      stationId: "dumbbell",
      basis: "per_implement",
    })
  })

  it("writes a prescribed dumbbell load as what goes in each hand", () => {
    expect(
      formatPrescription({
        exerciseId: "0289",
        sets: 3,
        reps: { min: 8, max: 12 },
        rir: 2,
        loadKg: 30,
        loadBasis: "per_implement",
        restSeconds: 120,
      })
    ).toBe("3 × 8–12 · RIR 2 · 30 kg each · 120s rest")
    expect(
      formatPrescription({
        exerciseId: "0025",
        sets: 3,
        reps: { min: 8, max: 12 },
        rir: 2,
        loadKg: 80,
        loadBasis: "total",
        restSeconds: 120,
      })
    ).toBe("3 × 8–12 · RIR 2 · 80 kg · 120s rest")
  })
})
