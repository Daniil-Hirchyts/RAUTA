import { useState } from "react"

import { Button } from "@/components/ui/button"
import {
  Drawer,
  DrawerContent,
  DrawerDescription,
  DrawerFooter,
  DrawerTitle,
} from "@/components/ui/drawer"
import { triggerHaptic } from "@/lib/haptics"

/**
 * Guards the one action that empties the whole app. Deleting a single workout
 * asks once; this asks twice, because there is nothing left to undo it with.
 */
export function ClearDataConfirmation({
  onConfirm,
  onOpenChange,
  open,
}: {
  onConfirm: () => void
  onOpenChange: (open: boolean) => void
  open: boolean
}) {
  const [confirmed, setConfirmed] = useState(false)

  const close = () => {
    setConfirmed(false)
    onOpenChange(false)
  }

  return (
    <Drawer
      onOpenChange={(next) => {
        if (!next) setConfirmed(false)
        onOpenChange(next)
      }}
      open={open}
      swipeDirection="down"
    >
      <DrawerContent className="mx-auto max-w-[430px]">
        <div className="px-5 pt-16 pb-5 text-center">
          <DrawerTitle className="text-xl font-bold">
            {confirmed ? "This cannot be undone" : "Clear all data?"}
          </DrawerTitle>
          <DrawerDescription className="mx-auto mt-2 max-w-[18rem]">
            {confirmed
              ? "Export a backup first if you may need any of it later."
              : "Every workout, favorite, equipment preset, and preference on this device is removed."}
          </DrawerDescription>
        </div>
        <DrawerFooter className="bg-transparent pb-[calc(1rem+env(safe-area-inset-bottom))]">
          <Button
            className="h-12 w-full rounded-2xl text-base font-semibold"
            onClick={() => {
              if (!confirmed) {
                triggerHaptic("medium")
                setConfirmed(true)
                return
              }
              triggerHaptic("warning")
              onConfirm()
              close()
            }}
            variant="destructive"
          >
            {confirmed ? "Delete everything" : "Continue"}
          </Button>
          <Button
            className="h-12 w-full rounded-2xl text-base"
            onClick={close}
            variant="secondary"
          >
            Cancel
          </Button>
        </DrawerFooter>
      </DrawerContent>
    </Drawer>
  )
}
