import { useEffect, useRef } from "react"
import { Search, X } from "lucide-react"

import { Input } from "@/components/ui/input"
import { triggerHaptic } from "@/lib/haptics"

/**
 * Floats above the results the same way the equipment presets float above
 * the equipment grid: sticky to the top of the scroller, no backdrop, with
 * the card treatment carrying it over the content that scrolls beneath.
 *
 * The header's search toggle mounts and unmounts this, so being on screen at
 * all is already the answer to "does the user want to search".
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
    // The toggle is the only way in, so the tap that opened the field lands
    // in it. Focus without scrolling: the bar is sticky at the top of the
    // results, so it is already in view wherever the list happens to sit.
    inputRef.current?.focus({ preventScroll: true })
  }, [])

  return (
    <div className="sticky top-0 z-20 -mx-5 px-5 pt-4 pb-4" data-swipe-ignore>
      <form
        className="t-search-reveal relative"
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
          className="rounded-full border-border bg-card pr-11 pl-11 shadow-[0_8px_24px_rgb(0_0_0/0.18)]"
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
    </div>
  )
}
