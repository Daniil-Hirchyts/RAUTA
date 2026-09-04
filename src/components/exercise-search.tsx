import { useEffect, useRef } from "react"
import { Search, X } from "lucide-react"

import { AppControlMorph } from "@/components/app-morph"
import { Input } from "@/components/ui/input"
import { triggerHaptic } from "@/lib/haptics"

/**
 * The bottom tool opens this inline field and moves focus into it.
 *
 * The field claims the same command role as the magnifier that opened it, so
 * the round button stretches into the box rather than being swapped for one —
 * the two are the same control at two sizes, and the band should say so.
 */
export function ExerciseSearch({
  onChange,
  value,
}: {
  onChange: (value: string) => void
  value: string
}) {
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    inputRef.current?.focus({ preventScroll: true })
  }, [])

  return (
    <AppControlMorph className="app-command-fill" role="search">
      <form
        className="pointer-events-auto relative min-w-0 flex-1"
        data-swipe-ignore
        onSubmit={(event) => {
          // A single-field form turns the keyboard's return key into
          // "search"; there is nothing to submit, so the useful thing it can
          // do is put the keyboard away.
          event.preventDefault()
          event.currentTarget.querySelector("input")?.blur()
        }}
      >
        <Search className="pointer-events-none absolute top-1/2 left-4 size-4.5 -translate-y-1/2 text-muted-foreground" />
        <Input
          aria-label="Search exercises"
          className="h-(--app-controls-height) rounded-full border-border bg-card pr-11 pl-11 shadow-[0_8px_24px_rgb(0_0_0/0.18)]"
          enterKeyHint="search"
          onChange={(event) => onChange(event.target.value)}
          placeholder="Search exercises"
          ref={inputRef}
          value={value}
        />
        {value !== "" && (
          <button
            aria-label="Clear search"
            className="interactive-spring hit-target absolute top-1/2 right-3 grid size-7 -translate-y-1/2 place-items-center rounded-full text-primary active:bg-card/90"
            data-haptics="off"
            onClick={() => {
              triggerHaptic("selection")
              onChange("")
            }}
            type="button"
          >
            <X className="size-4" />
          </button>
        )}
      </form>
    </AppControlMorph>
  )
}
