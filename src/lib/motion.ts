/**
 * The shell's shared motion vocabulary. Page transitions, the command band and
 * the modal all read from here so a change to the app's feel is one edit
 * rather than a hunt through components.
 */

/** The same curve `--ease-smooth-out` carries in CSS, in the tuple form
 *  motion wants. Keep the two in sync. */
export const EASE_SMOOTH_OUT = [0.22, 1, 0.36, 1] as const

/** A shared element crossing between two pages. Long enough to read as one
 *  object moving rather than two objects swapping, and it deliberately
 *  outlasts the page crossfade so the arriving element is still travelling
 *  when the page it came from has finished fading. */
export const MORPH_TRANSITION = {
  duration: 0.42,
  ease: EASE_SMOOTH_OUT,
} as const

/** A button changing its role — position and width — inside the command band,
 *  which never leaves the screen and so should settle faster than a page. */
export const CONTROL_MORPH_TRANSITION = {
  duration: 0.32,
  ease: EASE_SMOOTH_OUT,
} as const

/** The label inside a morphing button. Swapping text has to be quicker than
 *  the box carrying it, or the old word rides along into the new shape. */
export const CONTROL_LABEL_TRANSITION = {
  duration: 0.16,
  ease: EASE_SMOOTH_OUT,
} as const

export const MODAL_OPEN_TRANSITION = {
  duration: 0.25,
  ease: EASE_SMOOTH_OUT,
} as const

export const MODAL_CLOSE_TRANSITION = {
  duration: 0.15,
  ease: EASE_SMOOTH_OUT,
} as const
