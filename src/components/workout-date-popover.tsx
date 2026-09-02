import { memo, useState, type ReactNode } from "react"

import { AppPopover } from "@/components/app-popover"
import { Calendar } from "@/components/ui/calendar"
import { toISODate } from "@/lib/date"
import { triggerHaptic } from "@/lib/haptics"

function todayStart() {
  const today = new Date()
  return new Date(today.getFullYear(), today.getMonth(), today.getDate())
}

function isoToDate(iso: string) {
  const [year, month, day] = iso.split("-").map(Number)
  return new Date(year, month - 1, day)
}

// The panel closes the moment a day is picked, so the DayPicker tree never
// needs to re-render — keeping it stable prevents a focused day button from
// being replaced mid-tap.
const StableCalendar = memo(Calendar, () => true)

/** The date control opens into its own calendar, in place. */
export function WorkoutDatePopover({
  ariaLabel,
  children,
  className,
  date,
  onSelect,
  triggerClassName,
}: {
  ariaLabel?: string
  children: ReactNode
  className?: string
  date: string
  onSelect: (date: string) => void
  triggerClassName?: string
}) {
  const [open, setOpen] = useState(false)

  return (
    <AppPopover
      ariaLabel={ariaLabel}
      className={className}
      onOpenChange={(next) => {
        if (next) triggerHaptic("light")
        setOpen(next)
      }}
      open={open}
      panelHeight={400}
      panelLabel="Choose workout date"
      trigger={children}
      triggerClassName={triggerClassName}
    >
      <StableCalendar
        className="w-full overflow-hidden rounded-2xl bg-background [--cell-size:2.75rem]"
        disabled={{ before: todayStart() }}
        mode="single"
        onSelect={(selected) => {
          if (!selected) return
          triggerHaptic("success")
          setOpen(false)
          onSelect(toISODate(selected))
        }}
        selected={isoToDate(date)}
      />
    </AppPopover>
  )
}
