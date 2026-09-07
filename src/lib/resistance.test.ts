import { describe, expect, it } from "vitest"

import { EXERCISES_BY_ID } from "@/lib/exercises"
import {
  formatResistance,
  isMeasuredInKg,
  loadContextFor,
  makeResistance,
  resistanceModes,
  sideOptions,
  stepLoad,
} from "@/lib/resistance"
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
})
