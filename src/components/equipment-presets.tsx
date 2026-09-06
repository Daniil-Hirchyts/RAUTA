import { useEffect, useRef, useState, type FormEvent } from "react"
import { Check, Trash2 } from "lucide-react"

import { AppControlButton } from "@/components/app-shell"
import { AppControlMorph } from "@/components/app-morph"
import { Input } from "@/components/ui/input"
import { EQUIPMENT_OPTIONS } from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { cn } from "@/lib/utils"
import { useFilters } from "@/store/use-filters"

const STARTER_EQUIPMENT_PRESETS = [
  {
    id: "starter-home",
    name: "Home kit",
    equipment: [
      "body weight",
      "band",
      "resistance band",
      "dumbbell",
      "kettlebell",
    ],
  },
  { id: "starter-gym", name: "Full gym", equipment: EQUIPMENT_OPTIONS },
] as const

function sameSelection(left: readonly string[], right: readonly string[]) {
  return (
    left.length === right.length && left.every((item) => right.includes(item))
  )
}

/** The saved presets, applied to whichever equipment selection asked for them:
 *  the browse filter by default, or the profile's own equipment when it passes
 *  `value` and `onChange`. One preset list, two places to spend it. */
export function EquipmentPresets({
  className,
  onChange,
  value,
}: {
  className?: string
  onChange?: (equipment: string[]) => void
  value?: string[]
}) {
  const filterEquipment = useFilters((state) => state.selectedEquipment)
  const presets = useFilters((state) => state.equipmentPresets)
  const setFilterEquipment = useFilters((state) => state.setEquipment)
  const deletePreset = useFilters((state) => state.deleteEquipmentPreset)
  const selectedEquipment = value ?? filterEquipment
  const setEquipment = onChange ?? setFilterEquipment

  const togglePreset = (equipment: readonly string[]) => {
    triggerHaptic("selection")
    if (sameSelection(selectedEquipment, equipment)) {
      setEquipment([])
    } else {
      setEquipment([...equipment])
    }
  }

  return (
    <div
      className={cn(
        "pointer-events-auto flex min-w-0 [scrollbar-width:none] overflow-x-auto py-0.5 [&::-webkit-scrollbar]:hidden",
        className
      )}
      data-swipe-ignore
    >
      <div className="flex w-max min-w-full shrink-0 justify-center gap-2">
        {STARTER_EQUIPMENT_PRESETS.map((preset) => (
          <button
            aria-pressed={sameSelection(selectedEquipment, preset.equipment)}
            className="preset-chip shrink-0"
            data-haptics="off"
            key={preset.id}
            onClick={() => togglePreset(preset.equipment)}
            type="button"
          >
            {preset.name}
          </button>
        ))}
        {presets.map((preset) => {
          const isSelected = sameSelection(selectedEquipment, preset.equipment)
          return (
            <div
              className="preset-chip preset-chip--custom flex shrink-0 items-center"
              data-pressed={isSelected ? "true" : undefined}
              key={preset.id}
            >
              <button
                aria-pressed={isSelected}
                className="flex h-full items-center font-semibold text-inherit outline-none"
                data-haptics="off"
                onClick={() => togglePreset(preset.equipment)}
                type="button"
              >
                {preset.name}
              </button>
              <button
                aria-label={`Delete ${preset.name} preset`}
                className="interactive-spring hit-target ml-1.5 grid size-8 shrink-0 place-items-center rounded-full text-primary opacity-65 hover:opacity-100 active:opacity-100"
                data-haptics="off"
                onClick={() => {
                  triggerHaptic("warning")
                  deletePreset(preset.id)
                }}
                type="button"
              >
                <Trash2 className="size-4" />
              </button>
            </div>
          )
        })}
      </div>
    </div>
  )
}

export function EquipmentPresetEditor({
  className,
  equipment,
  onSaved,
}: {
  className?: string
  /** What the preset should hold; the browse filter when nothing is passed. */
  equipment?: string[]
  onSaved: () => void
}) {
  const [name, setName] = useState("")
  const inputRef = useRef<HTMLInputElement>(null)
  const filterEquipment = useFilters((state) => state.selectedEquipment)
  const savePreset = useFilters((state) => state.saveEquipmentPreset)
  const selection = equipment ?? filterEquipment
  const canSave = name.trim().length > 0 && selection.length > 0

  useEffect(() => {
    inputRef.current?.focus({ preventScroll: true })
  }, [])

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (!canSave) return
    savePreset(name, selection)
    triggerHaptic("success")
    onSaved()
  }

  return (
    <form
      className={cn(
        "pointer-events-auto flex min-w-0 items-center gap-2.5",
        className
      )}
      data-swipe-ignore
      onSubmit={handleSubmit}
    >
      {/* The field takes over the role the "+" tool was holding, so the round
          button opens into the box you type in instead of handing the band to
          a different control. */}
      <AppControlMorph className="app-command-fill" role="preset">
        <Input
          aria-label="Preset name"
          className="h-(--app-controls-height) min-w-0 flex-1 rounded-full border-border bg-card px-4 shadow-[0_8px_24px_rgb(0_0_0/0.18)]"
          enterKeyHint="done"
          onChange={(event) => setName(event.target.value)}
          placeholder="Preset name"
          ref={inputRef}
          value={name}
        />
      </AppControlMorph>
      <AppControlButton
        aria-label="Save preset"
        className="t-search-reveal"
        disabled={!canSave}
        type="submit"
      >
        <Check />
      </AppControlButton>
    </form>
  )
}
