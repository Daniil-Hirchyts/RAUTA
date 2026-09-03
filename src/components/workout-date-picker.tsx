import { memo, useState, type ReactNode } from "react"

import { AppModal } from "@/components/app-modal"
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

// The modal closes the moment a day is picked, so the DayPicker tree never
// needs to re-render — keeping it stable prevents a focused day button from
// being replaced mid-tap.
const StableCalendar = memo(Calendar, () => true)

/** The date control opens a calendar over the page, not a page of its own. */
export function WorkoutDatePicker({
  ariaLabel,
  children,
  className,
  date,
  onSelect,
}: {
  ariaLabel?: string
  children: ReactNode
  className?: string
  date: string
  onSelect: (date: string) => void
}) {
  const [open, setOpen] = useState(false)

  return (
    <>
      <button
        aria-expanded={open}
        aria-haspopup="dialog"
        aria-label={ariaLabel}
        className={className}
        data-haptics="off"
        onClick={() => {
          triggerHaptic("light")
          setOpen(true)
        }}
        type="button"
      >
        {children}
      </button>
      <AppModal
        label="Choose workout date"
        onClose={() => setOpen(false)}
        open={open}
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
      </AppModal>
    </>
  )
}
