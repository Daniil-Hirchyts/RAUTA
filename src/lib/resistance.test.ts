import { describe, expect, it } from "vitest"

import { EXERCISES_BY_ID } from "@/lib/exercises"
import {
  activeConfigurationFor,
  formatResistance,
  isMeasuredInKg,
  loadContextFor,
  makeResistance,
  nextStationId,
  resistanceModes,
  resolveLoadContext,
  sideOptions,
  stationChoicesFor,
  stepLoad,
} from "@/lib/resistance"
import type { PersistedLoadConfiguration } from "@/training-persistence/schema"
import type { ExerciseSummary } from "@/types"

/** Real catalogue entries: the point of these tests is that the semantics come
 *  from the shipped exercise data, not from a hand-made fixture. */
function exercise(id: string): ExerciseSummary {
  const found = EXERCISES_BY_ID.get(id)
  if (!found) throw new Error(`Missing exercise ${id}`)
  return found
}

const DUMBBELL_PRESS = exercise("0289")
const BARBELL_BENCH = exercise("0025")
const MACHINE_ROW = exercise("0571")
const ASSISTED_PULL_UP = exercise("0017")
const SIT_UP = exercise("0001")
const BAND_PULL_UP = exercise("0970")
const ONE_ARM_ROW = exercise("3156")

/** Steps a load `count` times from `start`, the way holding the button does. */
function ladder(
  start: number,
  count: number,
  grid: Parameters<typeof stepLoad>[2],
  direction: 1 | -1 = 1
) {
  const values = [start]
  for (let step = 0; step < count; step += 1)
    values.push(stepLoad(values[values.length - 1], direction, grid))
  return values
}

describe("resistance semantics", () => {
  it("keeps dumbbell load per implement and barbell load total", () => {
    const dumbbell = loadContextFor(DUMBBELL_PRESS, "external_load")
    const barbell = loadContextFor(BARBELL_BENCH, "external_load")

    expect(dumbbell.basis).toBe("per_implement")
    expect(barbell.basis).toBe("total")
    // Two stations that must never pool their kilograms.
    expect(dumbbell.stationId).not.toBe(barbell.stationId)

    expect(
      formatResistance(makeResistance("external_load", 30, dumbbell))
    ).toBe("30 kg each")
    expect(formatResistance(makeResistance("external_load", 80, barbell))).toBe(
      "80 kg"
    )
  })

  it("steps each equipment family by the loads it actually stocks", () => {
    expect(
      ladder(28, 2, loadContextFor(DUMBBELL_PRESS, "external_load").grid)
    ).toEqual([28, 30, 32])
    expect(
      ladder(80, 2, loadContextFor(BARBELL_BENCH, "external_load").grid)
    ).toEqual([80, 82.5, 85])
    expect(
      ladder(40, 2, loadContextFor(MACHINE_ROW, "external_load").grid)
    ).toEqual([40, 45, 50])
  })

  it("never steps a load below an empty station", () => {
    const { grid } = loadContextFor(BARBELL_BENCH, "external_load")
    expect(ladder(2.5, 3, grid, -1)).toEqual([2.5, 0, 0, 0])
  })

  it("records assistance as assistance rather than as negative load", () => {
    expect(resistanceModes(ASSISTED_PULL_UP)[0]).toBe("assistance")
    const context = loadContextFor(ASSISTED_PULL_UP, "assistance")
    const resistance = makeResistance("assistance", 40, context)

    expect(resistance).toMatchObject({ type: "assistance", kg: 40 })
    expect(formatResistance(resistance)).toBe("40 kg assist")
    // Assistance is measured at its own station: 40 kg of help is not 40 kg of
    // load on the same machine.
    expect(context.stationId).not.toBe(
      loadContextFor(ASSISTED_PULL_UP, "external_load").stationId
    )
  })

  it("offers body weight, added load and assistance for a body-weight movement", () => {
    expect(resistanceModes(SIT_UP)).toEqual([
      "bodyweight",
      "external_load",
      "assistance",
    ])
    expect(isMeasuredInKg("bodyweight")).toBe(false)
    expect(
      makeResistance("bodyweight", 0, loadContextFor(SIT_UP, "bodyweight"))
    ).toEqual({ type: "bodyweight" })
    expect(formatResistance({ type: "bodyweight" })).toBe("Body weight")

    // Weight added to a body-weight movement is added load, and says so.
    const added = loadContextFor(SIT_UP, "external_load")
    expect(added.basis).toBe("total")
    expect(formatResistance(makeResistance("external_load", 10, added))).toBe(
      "10 kg"
    )
  })

  it("leaves bands qualitative rather than inventing kilograms", () => {
    expect(resistanceModes(BAND_PULL_UP)).toEqual(["band_resistance"])
    expect(isMeasuredInKg("band_resistance")).toBe(false)
    expect(
      makeResistance(
        "band_resistance",
        0,
        loadContextFor(BAND_PULL_UP, "band_resistance")
      )
    ).toEqual({ type: "band_resistance" })
  })

  it("prefers a saved load configuration over the equipment default", () => {
    const context = loadContextFor(BARBELL_BENCH, "external_load", {
      id: "config-1",
      exerciseId: BARBELL_BENCH.id,
      stationId: "Bench A",
      basis: "total",
      grid: { availableLoadsKg: [40, 60, 80, 100] },
    })

    expect(context.stationId).toBe("Bench A")
    expect(ladder(60, 2, context.grid)).toEqual([60, 80, 100])
    expect(stepLoad(100, 1, context.grid)).toBe(100)
  })

  it("asks for a side only where the movement has one", () => {
    expect(sideOptions(BARBELL_BENCH)).toEqual(["both"])
    expect(sideOptions(ONE_ARM_ROW)).toEqual(["both", "left", "right"])
  })

  it("keeps a station's own steps out of another station's history", () => {
    const stackA: PersistedLoadConfiguration = {
      id: "config-a",
      exerciseId: MACHINE_ROW.id,
      stationId: "leverage machine",
      basis: "total",
      grid: { incrementKg: 5, minimumKg: 10 },
    }
    const stackB: PersistedLoadConfiguration = {
      id: "config-b",
      exerciseId: MACHINE_ROW.id,
      stationId: "leverage machine-2",
      basis: "total",
      grid: { incrementKg: 7.5, minimumKg: 7.5 },
    }
    const settings = { loadConfigurations: [stackA, stackB] }

    const choices = stationChoicesFor(MACHINE_ROW, "external_load", settings)
    // The configuration on the default station describes that station rather
    // than adding a second one beside it.
    expect(choices).toHaveLength(2)
    expect(choices[0]).toMatchObject({
      id: "config-a",
      label: "Leverage Machine",
    })
    expect(choices[1]).toMatchObject({
      id: "config-b",
      label: "Leverage Machine 2",
    })
    expect(ladder(10, 2, choices[0].context.grid)).toEqual([10, 15, 20])
    expect(ladder(7.5, 2, choices[1].context.grid)).toEqual([7.5, 15, 22.5])

    // With more than one station saved, nothing is assumed: the exercise stays
    // on its equipment default until somebody says which machine they are at.
    expect(
      activeConfigurationFor(MACHINE_ROW.id, "external_load", settings)
    ).toBeNull()
    expect(
      resolveLoadContext(MACHINE_ROW, "external_load", {
        ...settings,
        activeLoadConfigurations: { [MACHINE_ROW.id]: "config-b" },
      }).stationId
    ).toBe("leverage machine-2")
  })

  it("treats one saved station as the station and a stale selection as none", () => {
    const only: PersistedLoadConfiguration = {
      id: "config-a",
      exerciseId: BARBELL_BENCH.id,
      stationId: "barbell-2",
      basis: "total",
      grid: { incrementKg: 5 },
    }
    expect(
      activeConfigurationFor(BARBELL_BENCH.id, "external_load", {
        loadConfigurations: [only],
      })
    ).toBe(only)
    // A selection naming a station that is gone falls back to the equipment
    // default instead of failing or picking something else.
    expect(
      resolveLoadContext(BARBELL_BENCH, "external_load", {
        loadConfigurations: [],
        activeLoadConfigurations: { [BARBELL_BENCH.id]: "config-a" },
      }).stationId
    ).toBe("barbell")
  })

  it("never lets an assistance station stand in for a loaded one", () => {
    const assist: PersistedLoadConfiguration = {
      id: "config-assist",
      exerciseId: ASSISTED_PULL_UP.id,
      stationId: "assisted-2",
      mode: "assistance",
      basis: "total",
      grid: { incrementKg: 4.5, minimumKg: 9 },
    }
    const settings = {
      loadConfigurations: [assist],
      activeLoadConfigurations: { [ASSISTED_PULL_UP.id]: assist.id },
    }

    const assistance = resolveLoadContext(
      ASSISTED_PULL_UP,
      "assistance",
      settings
    )
    expect(assistance.stationId).toBe("assisted-2")
    expect(ladder(9, 2, assistance.grid)).toEqual([9, 13.5, 18])

    // The same saved station says nothing about weight hung off a belt.
    const load = resolveLoadContext(ASSISTED_PULL_UP, "external_load", settings)
    expect(load.stationId).not.toBe("assisted-2")
    expect(
      stationChoicesFor(ASSISTED_PULL_UP, "external_load", settings)
    ).toHaveLength(1)
  })

  it("numbers a new station off the equipment and skips the ones taken", () => {
    expect(nextStationId("cable", [])).toBe("cable-2")
    expect(nextStationId("cable", ["cable", "cable-2", "cable-3"])).toBe(
      "cable-4"
    )
  })

  it("carries the saved equipment step into the default station", () => {
    const context = resolveLoadContext(
      BARBELL_BENCH,
      "external_load",
      { loadConfigurations: [] },
      1.25
    )
    expect(ladder(80, 2, context.grid)).toEqual([80, 81.25, 82.5])
  })
})
