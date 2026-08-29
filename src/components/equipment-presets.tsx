import { useState, type FormEvent } from "react"
import { Plus, Trash2 } from "lucide-react"

import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { EQUIPMENT_OPTIONS } from "@/lib/exercises"
import { useFilters } from "@/store/use-filters"

const STARTER_PRESETS = [
  { id: "starter-bodyweight", name: "Bodyweight", equipment: ["body weight"] },
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

export function EquipmentPresets() {
  const [open, setOpen] = useState(false)
  const [name, setName] = useState("")
  const selectedEquipment = useFilters((state) => state.selectedEquipment)
  const presets = useFilters((state) => state.equipmentPresets)
  const setEquipment = useFilters((state) => state.setEquipment)
  const savePreset = useFilters((state) => state.saveEquipmentPreset)
  const deletePreset = useFilters((state) => state.deleteEquipmentPreset)

  const submit = (event: FormEvent) => {
    event.preventDefault()
    if (!name.trim() || selectedEquipment.length === 0) return
    savePreset(name)
    setName("")
    setOpen(false)
  }

  return (
    <div className="mb-3">
      <div className="mb-2 flex items-center justify-between">
        <p className="text-[10px] font-medium tracking-[0.14em] text-muted-foreground uppercase">
          Presets
        </p>
        <Dialog onOpenChange={setOpen} open={open}>
          <DialogTrigger
            disabled={selectedEquipment.length === 0}
            render={
              <Button
                className="h-8 rounded-full px-3 text-xs"
                size="sm"
                variant="ghost"
              />
            }
          >
            <Plus data-icon="inline-start" />
            Save preset
          </DialogTrigger>
          <DialogContent className="max-w-[398px] gap-5">
            <DialogHeader>
              <DialogTitle>Save equipment preset</DialogTitle>
              <DialogDescription>
                {selectedEquipment.length} selected item
                {selectedEquipment.length === 1 ? "" : "s"}
              </DialogDescription>
            </DialogHeader>
            <form className="space-y-4" onSubmit={submit}>
              <Input
                aria-label="Preset name"
                autoFocus
                maxLength={30}
                onChange={(event) => setName(event.target.value)}
                placeholder="Preset name"
                value={name}
              />
              <DialogFooter>
                <Button
                  className="w-full"
                  disabled={!name.trim()}
                  type="submit"
                >
                  Save preset
                </Button>
              </DialogFooter>
            </form>
          </DialogContent>
        </Dialog>
      </div>

      <div className="-mx-4 flex [scrollbar-width:none] gap-2 overflow-x-auto px-4 pb-1 [&::-webkit-scrollbar]:hidden">
        {STARTER_PRESETS.map((preset) => (
          <button
            aria-pressed={sameSelection(selectedEquipment, preset.equipment)}
            className="preset-chip shrink-0"
            key={preset.id}
            onClick={() => setEquipment([...preset.equipment])}
            type="button"
          >
            {preset.name}
          </button>
        ))}
        {presets.map((preset) => (
          <div
            className="flex shrink-0 items-center rounded-full bg-card ring-1 ring-border"
            key={preset.id}
          >
            <button
              aria-pressed={sameSelection(selectedEquipment, preset.equipment)}
              className="preset-chip border-0 pr-2 ring-0"
              onClick={() => setEquipment([...preset.equipment])}
              type="button"
            >
              {preset.name}
            </button>
            <button
              aria-label={`Delete ${preset.name} preset`}
              className="mr-1 grid size-7 place-items-center rounded-full text-muted-foreground hover:bg-muted hover:text-foreground"
              onClick={() => deletePreset(preset.id)}
              type="button"
            >
              <Trash2 className="size-3.5" />
            </button>
          </div>
        ))}
      </div>
    </div>
  )
}
