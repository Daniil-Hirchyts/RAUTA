import { Button } from "@/components/ui/button"
import {
  Drawer,
  DrawerContent,
  DrawerDescription,
  DrawerFooter,
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
        <DrawerFooter className="bg-transparent pb-[calc(1rem+env(safe-area-inset-bottom))]">
          <Button
            className="h-12 w-full rounded-2xl text-base font-semibold"
            onClick={() => {
              triggerHaptic("warning")
              onConfirm()
              onOpenChange(false)
            }}
            variant="destructive"
          >
            Delete workout
          </Button>
          <Button
            className="h-12 w-full rounded-2xl text-base"
            onClick={() => onOpenChange(false)}
            variant="secondary"
          >
            Cancel
          </Button>
        </DrawerFooter>
      </DrawerContent>
    </Drawer>
  )
}
