import type { ReactNode } from "react"

import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import {
  Drawer,
  DrawerClose,
  DrawerContent,
  DrawerFooter,
  DrawerHeader,
  DrawerTitle,
  DrawerTrigger,
} from "@/components/ui/drawer"
import { EQUIPMENT_OPTIONS } from "@/lib/exercises"
import { titleCase } from "@/lib/text"
import { useFilters } from "@/store/use-filters"

export function EquipmentDrawer({ children }: { children: ReactNode }) {
  const selectedEquipment = useFilters((state) => state.selectedEquipment)
  const toggleEquipment = useFilters((state) => state.toggleEquipment)

  return (
    <Drawer showSwipeHandle>
      <DrawerTrigger
        aria-label="Choose equipment"
        className="block w-full rounded-2xl text-left"
      >
        {children}
      </DrawerTrigger>
      <DrawerContent className="mx-auto max-w-[430px] bg-popover">
        <DrawerHeader className="border-b border-border px-5 pt-2 pb-4 text-left">
          <DrawerTitle className="text-lg">Equipment</DrawerTitle>
        </DrawerHeader>
        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-3 py-2">
          {EQUIPMENT_OPTIONS.map((equipment) => {
            const checked = selectedEquipment.includes(equipment)
            return (
              <label
                className="flex min-h-12 items-center gap-3 rounded-xl px-3 text-sm transition-colors hover:bg-muted/60"
                key={equipment}
              >
                <Checkbox
                  aria-label={titleCase(equipment)}
                  checked={checked}
                  onCheckedChange={() => toggleEquipment(equipment)}
                />
                <span className="flex-1">{titleCase(equipment)}</span>
              </label>
            )
          })}
        </div>
        <DrawerFooter className="border-t border-border px-4 pt-4 pb-[calc(1rem+env(safe-area-inset-bottom))]">
          <DrawerClose render={<Button className="h-11 w-full" />}>
            Done
          </DrawerClose>
        </DrawerFooter>
      </DrawerContent>
    </Drawer>
  )
}
