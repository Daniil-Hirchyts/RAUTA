import { useState, type FormEvent } from "react"
import { Plus, Trash2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import {
  Drawer,
  DrawerContent,
  DrawerDescription,
  DrawerControls,
  DrawerHeader,
  DrawerTitle,
  DrawerTrigger,
} from "@/components/ui/drawer"
import { Input } from "@/components/ui/input"
import { EQUIPMENT_OPTIONS } from "@/lib/exercises"
import { triggerHaptic } from "@/lib/haptics"
import { cn } from "@/lib/utils"
import { useFilters } from "@/store/use-filters"

const STARTER_PRESETS = [
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

export function EquipmentPresets({ className }: { className?: string }) {
  const [open, setOpen] = useState(false)
  const [name, setName] = useState("")
  const selectedEquipment = useFilters((state) => state.selectedEquipment)
  const presets = useFilters((state) => state.equipmentPresets)
  const setEquipment = useFilters((state) => state.setEquipment)
  const savePreset = useFilters((state) => state.saveEquipmentPreset)
  const deletePreset = useFilters((state) => state.deleteEquipmentPreset)

  const togglePreset = (equipment: readonly string[]) => {
    triggerHaptic("selection")
    if (sameSelection(selectedEquipment, equipment)) {
      setEquipment([])
    } else {
      setEquipment([...equipment])
    }
  }

  const submit = (event: FormEvent) => {
    event.preventDefault()
    if (!name.trim() || selectedEquipment.length === 0) return
    savePreset(name)
    triggerHaptic("success")
    setName("")
    setOpen(false)
  }

  return (
    <div
      className={cn(
        "flex min-w-0 [scrollbar-width:none] gap-2 overflow-x-auto py-0.5 [&::-webkit-scrollbar]:hidden",
        className
      )}
      data-swipe-ignore
    >
      <Drawer onOpenChange={setOpen} open={open} swipeDirection="down">
        <DrawerTrigger
          aria-label="Save current selection as a preset"
          disabled={selectedEquipment.length === 0}
          render={
            <button
              className="interactive-spring grid size-11 shrink-0 place-items-center rounded-full border border-border bg-card text-primary shadow-[0_8px_24px_rgb(0_0_0/0.18)] active:bg-card/90 disabled:bg-muted disabled:text-muted-foreground"
              type="button"
            />
          }
        >
          <Plus className="size-4.5" />
        </DrawerTrigger>
        <DrawerContent className="mx-auto max-w-[430px]">
          <DrawerHeader className="px-5 pt-16 text-left">
            <DrawerTitle className="text-xl font-bold">
              Save equipment preset
            </DrawerTitle>
            <DrawerDescription>
              {selectedEquipment.length} selected item
              {selectedEquipment.length === 1 ? "" : "s"}
            </DrawerDescription>
          </DrawerHeader>
          <form className="space-y-4 px-5 pt-4 pb-6" id="equipment-preset-form" onSubmit={submit}>
            <Input
              aria-label="Preset name"
              autoFocus
              maxLength={30}
              onChange={(event) => setName(event.target.value)}
              placeholder="Preset name"
              value={name}
            />
            <DrawerControls>
              <Button
                className="w-full"
                disabled={!name.trim()}
                form="equipment-preset-form"
                size="cta"
                type="submit"
              >
                Save preset
              </Button>
            </DrawerControls>
          </form>
        </DrawerContent>
      </Drawer>

      {STARTER_PRESETS.map((preset) => (
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
  )
}
