/* eslint-disable react-refresh/only-export-components */
import { Button as ButtonPrimitive } from "@base-ui/react/button"
import { cva, type VariantProps } from "class-variance-authority"

import { triggerHaptic } from "@/lib/haptics"
import { cn } from "@/lib/utils"

const buttonVariants = cva(
  "group/button interactive-spring inline-flex shrink-0 items-center justify-center rounded-4xl border border-transparent bg-clip-padding text-sm font-semibold whitespace-nowrap outline-none select-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/30 focus-visible:brightness-110 aria-invalid:border-destructive aria-invalid:ring-3 aria-invalid:ring-destructive/20 dark:aria-invalid:border-destructive/50 dark:aria-invalid:ring-destructive/40 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
  {
    variants: {
      variant: {
        default:
          "border-primary bg-primary text-primary-foreground aria-disabled:border-border aria-disabled:bg-muted aria-disabled:text-muted-foreground not-aria-disabled:active:border-(--primary-softer) not-aria-disabled:active:bg-[color-mix(in_oklch,var(--primary),white_24%)] not-aria-disabled:active:brightness-125",
        secondary:
          "border-border bg-secondary text-secondary-foreground aria-disabled:bg-muted aria-disabled:text-muted-foreground aria-expanded:bg-secondary aria-expanded:text-secondary-foreground not-aria-disabled:active:bg-secondary/90 not-aria-disabled:active:text-white not-aria-disabled:active:brightness-125",
        ghost:
          "border-border bg-card aria-disabled:bg-muted aria-disabled:text-muted-foreground aria-expanded:bg-muted aria-expanded:text-foreground not-aria-disabled:active:bg-card/90 not-aria-disabled:active:text-white not-aria-disabled:active:brightness-125",
        destructive:
          "border-primary bg-card text-primary focus-visible:border-primary focus-visible:ring-primary/30 aria-disabled:border-border aria-disabled:bg-muted aria-disabled:text-muted-foreground not-aria-disabled:active:border-primary not-aria-disabled:active:bg-[color-mix(in_oklch,var(--card),var(--primary)_28%)] not-aria-disabled:active:text-primary not-aria-disabled:active:brightness-125",
      },
      // Every size clears the 44px touch minimum. "cta" and "icon-cta" are the
      // bottom-controls row, sized from the same token the surface reserves
      // space with, so the footer and the gap left for it cannot disagree.
      size: {
        default:
          "h-11 gap-1.5 px-3.5 text-[15px] has-data-[icon=inline-end]:pr-3 has-data-[icon=inline-start]:pl-3",
        icon: "size-11 text-primary",
        cta: "h-(--app-controls-height) gap-1.5 rounded-2xl px-5 text-base font-semibold",
        // The square controls were drawn at exactly half their box, i.e. a
        // circle; say that rather than restating the number.
        "icon-cta":
          "size-(--app-controls-height) shrink-0 rounded-full text-primary",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
)

/** Restart the refusal shake even if one is already playing, so a second
 *  impatient tap answers as clearly as the first. */
function shake(element: HTMLElement) {
  element.removeAttribute("data-shake")
  // Reading layout between the two writes is what makes the browser treat
  // this as a new animation rather than a continuation of the running one.
  void element.offsetWidth
  element.setAttribute("data-shake", "true")
  // The attribute has to go once the shake is over: while it is there it owns
  // the element's `animation`, which is also where the press spring lives if
  // the button becomes pressable again.
  element.addEventListener(
    "animationend",
    () => element.removeAttribute("data-shake"),
    { once: true }
  )
}

function Button({
  className,
  variant = "default",
  size = "default",
  disabled,
  onPointerDownCapture,
  ...props
}: ButtonPrimitive.Props & VariantProps<typeof buttonVariants>) {
  return (
    <ButtonPrimitive
      data-slot="button"
      className={cn(buttonVariants({ variant, size, className }))}
      disabled={disabled}
      // A disabled button that cannot be pressed also cannot say why: the tap
      // lands on nothing and reads as a dead app. `focusableWhenDisabled`
      // keeps the control out of the native `disabled` state — it is marked
      // `aria-disabled` instead, which still blocks activation — so the press
      // reaches us and can be answered with a shake.
      focusableWhenDisabled={Boolean(disabled)}
      // The button's own handlers are suppressed while disabled, and the
      // capture phase runs before them.
      onPointerDownCapture={(event) => {
        onPointerDownCapture?.(event)
        if (!disabled) return
        shake(event.currentTarget)
        triggerHaptic("warning")
      }}
      {...props}
      // Direct-touch haptics install a transparent native switch over a
      // button to reach iOS Safari's feedback; a refused press answers with
      // its own haptic instead, and must not route a click through that
      // overlay.
      {...(disabled ? { "data-haptics": "off" } : null)}
    />
  )
}

export { Button, buttonVariants }
