import { useState } from "react"

import { AppImage } from "@/components/app-image"
import { RotaryKnob } from "@/components/ui/rotary-knob"
import { EQUIPMENT_OPTIONS } from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { equipmentLoadSpec, formatKg } from "@/lib/resistance"
import { titleCase } from "@/lib/text"
import { cn } from "@/lib/utils"
import { equipmentImage } from "@/lib/visuals"
import { useFilters } from "@/store/use-filters"

/**
 * One small extension of the existing equipment page: the user tells RAUTA
 * how large the next real load step is on the equipment they selected.
 *
 * The catalogue still owns whether a number means total load or "each". This
 * control only replaces the generic rack/stack increment with the user's real
 * one, so set logging, week generation and progression speak the same load
 * grid. One machine that differs from the rest is described where it is used,
 * on its own station in the set editor, rather than here.
 */
export function EquipmentLoadSettings() {
  const gymEquipment = useFilters((state) => state.gymEquipment)
  const increments = useFilters((state) => state.equipmentLoadIncrements)
  const setIncrement = useFilters((state) => state.setEquipmentLoadIncrement)
  const clearIncrement = useFilters(
    (state) => state.clearEquipmentLoadIncrement
  )
  const configurable = EQUIPMENT_OPTIONS.filter(
    (equipment) =>
      gymEquipment.includes(equipment) && equipmentLoadSpec(equipment)
  )
  const [selected, setSelected] = useState(configurable[0] ?? "")
  const equipment = configurable.includes(selected)
    ? selected
    : (configurable[0] ?? "")
  if (!equipment) return null

  const spec = equipmentLoadSpec(equipment)!
  const saved = increments[equipment]
  const value = saved ?? spec.incrementKg
  const label = titleCase(equipment)

  return (
    <section aria-label="Load increments" className="mt-8">
      <div className="px-1">
        <h2 className="text-lg font-black tracking-tight">Load steps</h2>
        <p className="mt-1 text-sm leading-snug text-muted-foreground">
          Set the next weight your equipment actually offers. RAUTA logs, plans
          and progresses in these steps.
        </p>
      </div>

      <div className="-mx-(--app-content-inset) mt-4 flex gap-2 overflow-x-auto px-(--app-content-inset) pb-1">
        {configurable.map((item) => {
          const active = item === equipment
          return (
            <button
              aria-pressed={active}
              className={cn(
                "interactive-spring w-24 shrink-0 overflow-hidden rounded-2xl border bg-card text-center",
                active ? "border-primary/65" : "border-border"
              )}
              key={item}
              onClick={() => {
                triggerHaptic("selection")
                setSelected(item)
              }}
              type="button"
            >
              <span className="block aspect-square bg-muted/30 p-2">
                <AppImage
                  alt=""
                  className="h-full w-full object-contain"
                  draggable={false}
                  src={equipmentImage(item)}
                />
              </span>
              <span className="block px-2 py-2 text-xs leading-tight font-bold">
                {titleCase(item)}
              </span>
            </button>
          )
        })}
      </div>

      <div className="mt-4 rounded-3xl border border-border bg-card/60 px-4 py-5">
        <div className="mb-2 text-center">
          <p className="text-base font-black">{label}</p>
          <p className="mt-1 text-xs text-muted-foreground">
            {spec.basis === "per_implement"
              ? "Logged per implement · the value is for each hand"
              : "Logged as total load"}
          </p>
        </div>
        <RotaryKnob
          ariaLabel={`${label} load increment`}
          className="mx-auto"
          format={formatKg}
          max={20}
          min={0.25}
          onChange={(incrementKg) => setIncrement(equipment, incrementKg)}
          size={184}
          step={0.25}
          unit="kg step"
          value={value}
        />
        <div className="mt-2 flex min-h-10 items-center justify-center">
          {saved !== undefined ? (
            <button
              className="interactive-spring rounded-full px-4 py-2 text-xs font-bold text-primary"
              onClick={() => {
                triggerHaptic("selection")
                clearIncrement(equipment)
              }}
              type="button"
            >
              Use {formatKg(spec.incrementKg)} kg default
            </button>
          ) : (
            <span className="text-xs text-muted-foreground">
              Default for {label.toLowerCase()}
            </span>
          )}
        </div>
      </div>
    </section>
  )
}
