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
    <div className="sticky top-0 z-20 mb-6 flex [scrollbar-width:none] gap-2 overflow-x-auto pb-1 [&::-webkit-scrollbar]:hidden">
      <Dialog onOpenChange={setOpen} open={open}>
        <DialogTrigger
          aria-label="Save current selection as a preset"
          disabled={selectedEquipment.length === 0}
          render={
            <button
              className="grid size-10 shrink-0 place-items-center rounded-full border border-white/10 bg-card/50 text-foreground shadow-[inset_0_1px_0_rgba(255,255,255,0.06)] backdrop-blur-xl transition-transform duration-150 active:scale-90 disabled:bg-card/25 disabled:text-foreground/35"
              type="button"
            />
          }
        >
          <Plus className="size-4.5" />
        </DialogTrigger>
        <DialogContent>
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
                className="h-12 w-full rounded-2xl text-base font-semibold"
                disabled={!name.trim()}
                type="submit"
              >
                Save preset
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

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
          className="flex shrink-0 items-center rounded-full bg-card/50 shadow-[inset_0_1px_0_rgba(255,255,255,0.06)] ring-1 ring-white/10 backdrop-blur-xl"
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
            className="mr-1 grid size-8 shrink-0 place-items-center rounded-full text-muted-foreground transition-transform duration-150 hover:bg-muted hover:text-foreground active:scale-90"
            onClick={() => deletePreset(preset.id)}
            type="button"
          >
            <Trash2 className="size-4" />
          </button>
        </div>
      ))}
    </div>
  )
}
