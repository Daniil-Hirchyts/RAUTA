import { useState } from "react"

import { AppImage } from "@/components/app-image"
import { CoverflowCarousel } from "@/components/ui/coverflow-carousel"
import { RotaryKnob } from "@/components/ui/rotary-knob"
import { triggerHaptic } from "@/lib/haptics"
import {
  equipmentLoadSpec,
  formatKg,
  loadConfigurableEquipment,
} from "@/lib/resistance"
import { titleCase } from "@/lib/text"
import { equipmentImage } from "@/lib/visuals"
import { useFilters } from "@/store/use-filters"

/**
 * One small extension of the existing equipment pages: the user tells RAUTA
 * how large the next real load step is on the equipment they selected.
 *
 * The catalogue still owns whether a number means total load or "each". This
 * control only replaces the generic rack/stack increment with the user's real
 * one, so set logging, week generation and progression speak the same load
 * grid. One machine that differs from the rest is described where it is used,
 * on its own station in the set editor, rather than here.
 */

/** What the number on the dial will mean once it is saved. */
function basisLabel(equipment: string) {
  return equipmentLoadSpec(equipment)?.basis === "per_implement"
    ? "Logged per implement · the value is for each hand"
    : "Logged as total load"
}

export function EquipmentLoadSettings() {
  const gymEquipment = useFilters((state) => state.gymEquipment)
  const increments = useFilters((state) => state.equipmentLoadIncrements)
  const setIncrement = useFilters((state) => state.setEquipmentLoadIncrement)
  const clearIncrement = useFilters(
    (state) => state.clearEquipmentLoadIncrement
  )
  const configurable = loadConfigurableEquipment(gymEquipment)
  const [selected, setSelected] = useState(configurable[0] ?? "")
  const equipment = configurable.includes(selected)
    ? selected
    : (configurable[0] ?? "")

  if (!equipment) {
    return (
      <p className="m-auto max-w-64 text-center text-sm leading-relaxed text-muted-foreground">
        Nothing here to describe yet. Pick equipment that carries a weight and
        its steps show up here.
      </p>
    )
  }

  const spec = equipmentLoadSpec(equipment)!
  const saved = increments[equipment]
  const value = saved ?? spec.incrementKg
  const label = titleCase(equipment)

  return (
    <div className="flex min-h-full flex-col">
      {/* The same deck the goal is picked from: one thing at a time, at the
          size a picture of it is worth showing. */}
      <CoverflowCarousel
        cardWidth="clamp(140px, 40vw, 190px)"
        className="-mx-(--app-content-inset)"
        label="Equipment"
        onChange={setSelected}
        slides={configurable.map((item) => ({
          description: basisLabel(item),
          id: item,
          media: (
            <span className="absolute inset-0 grid place-items-center bg-muted/40 p-5">
              <AppImage
                alt=""
                className="h-full w-full object-contain"
                draggable={false}
                src={equipmentImage(item)}
              />
            </span>
          ),
          title: titleCase(item),
        }))}
        value={equipment}
      />

      {/* What the dial is currently saying, said in words, above it: the
          wheel owns the bottom of the page, so the note that qualifies it
          goes on the last line before the wheel starts rather than under it
          where the page has already run out. */}
      <div className="mt-auto flex min-h-8 items-center justify-center pt-2">
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

      {/* The wheel is the bottom of the screen and runs off both sides of
          it, which is the whole reason everything above it fits. */}
      <RotaryKnob
        ariaLabel={`${label} load increment`}
        className="-mx-(--app-content-inset) mt-1 w-auto"
        format={formatKg}
        max={20}
        min={0.25}
        onChange={(incrementKg) => setIncrement(equipment, incrementKg)}
        size={520}
        step={0.25}
        unit="kg step"
        value={value}
      />
    </div>
  )
}
