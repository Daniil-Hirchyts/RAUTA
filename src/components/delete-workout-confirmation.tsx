import { Button } from "@/components/ui/button"
import {
  Drawer,
  DrawerContent,
  DrawerDescription,
  DrawerControls,
  DrawerTitle,
} from "@/components/ui/drawer"
import { triggerHaptic } from "@/lib/haptics"

export function DeleteWorkoutConfirmation({
  onConfirm,
  onOpenChange,
  open,
}: {
  onConfirm: () => void
  onOpenChange: (open: boolean) => void
  open: boolean
}) {
  return (
    <Drawer onOpenChange={onOpenChange} open={open} swipeDirection="down">
      <DrawerContent className="mx-auto max-w-[430px]">
        <div className="px-5 pt-16 pb-5 text-center">
          <DrawerTitle className="text-xl font-bold">
            Delete workout?
          </DrawerTitle>
          <DrawerDescription className="mx-auto mt-2 max-w-[18rem]">
            This workout will be permanently removed from this device.
          </DrawerDescription>
        </div>
        <DrawerControls>
          <Button
            className="w-full"
            size="cta"
            onClick={() => {
              triggerHaptic("warning")
              onConfirm()
              onOpenChange(false)
            }}
            variant="destructive"
          >
            Delete workout
          </Button>
        </DrawerControls>
      </DrawerContent>
    </Drawer>
  )
}
