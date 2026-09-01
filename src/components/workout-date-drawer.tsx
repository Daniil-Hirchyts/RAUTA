import { Calendar } from "@/components/ui/calendar"
import { Drawer, DrawerContent, DrawerTitle } from "@/components/ui/drawer"
import { formatDateLong, toISODate } from "@/lib/date"
import { triggerHaptic } from "@/lib/haptics"

function isoToDate(iso: string) {
  const [year, month, day] = iso.split("-").map(Number)
  return new Date(year, month - 1, day)
}

function todayStart() {
  const today = new Date()
  return new Date(today.getFullYear(), today.getMonth(), today.getDate())
}

/**
 * Moves a workout to another day. A workout is identified by its date
 * everywhere in the app — the list, the heatmap, the Lock Screen card — so
 * this is the one thing about a saved workout that is worth changing on its
 * own, without going through the whole form.
 */
export function WorkoutDateDrawer({
  date,
  onOpenChange,
  onSelect,
  open,
}: {
  date: string
  onOpenChange: (open: boolean) => void
  onSelect: (date: string) => void
  open: boolean
}) {
  return (
    <Drawer onOpenChange={onOpenChange} open={open} swipeDirection="down">
      <DrawerContent className="mx-auto max-w-[430px] [--drawer-inset:0px]">
        <div className="px-5 pt-16 pb-[calc(1.25rem+env(safe-area-inset-bottom))]">
          <DrawerTitle className="text-2xl font-black tracking-[-0.025em]">
            Change date
          </DrawerTitle>
          <p className="mt-1 text-sm text-muted-foreground">
            Currently {formatDateLong(date)}.
          </p>

          <div className="mt-4 rounded-xl border border-border bg-card p-3">
            <Calendar
              className="w-full overflow-hidden rounded-lg bg-background [--cell-size:clamp(2.5rem,11vw,3rem)]"
              disabled={{ before: todayStart() }}
              mode="single"
              onSelect={(selected) => {
                if (!selected) return
                triggerHaptic("success")
                onSelect(toISODate(selected))
                onOpenChange(false)
              }}
              selected={isoToDate(date)}
            />
          </div>
        </div>
      </DrawerContent>
    </Drawer>
  )
}
