import { useState } from "react"

import { cn } from "@/lib/utils"

/**
 * A count whose digits pop in when it changes.
 *
 * Arriving is not changing. A number that is simply the first thing a page
 * puts on screen has not come from anywhere, and animating it into place
 * makes the page look like it is still settling — the readout in the corner
 * of the muscle map was enough to make the whole figure read as drifting. So
 * the first value is drawn at rest, and only the ones that replace it move.
 */
export function AnimatedNumber({
  format = String,
  still = false,
  value,
}: {
  format?: (value: number) => string
  /** This change is not one to animate. A dial passing over a notch a frame
   *  restarts the pop before it has played, and the digits never reach full
   *  strength — while it is being turned the number stays put and legible. */
  still?: boolean
  value: number
}) {
  const text = format(value)
  const characters = text.split("")
  // Comparing against the last value rendered, rather than against the first
  // one, so a count that returns to where it started still animates. Setting
  // state during render is how React stores what the previous render saw: the
  // re-run happens before anything is committed, so the digits reach the DOM
  // already carrying the class and the animation starts from their mount
  // rather than from a class arriving on digits that had settled.
  const [shown, setShown] = useState(value)
  const [changed, setChanged] = useState(false)

  if (shown !== value) {
    setShown(value)
    setChanged(!still)
  }

  return (
    <span
      aria-label={text}
      className={cn("t-digit-group", changed && "is-animating")}
      key={text}
    >
      {characters.map((character, index) => (
        <span
          aria-hidden="true"
          className="t-digit"
          data-stagger={
            index === characters.length - 2
              ? "1"
              : index === characters.length - 1
                ? "2"
                : undefined
          }
          key={`${text}-${index}`}
        >
          {character}
        </span>
      ))}
    </span>
  )
}
