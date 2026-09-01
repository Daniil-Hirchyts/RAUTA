/* eslint-disable react-refresh/only-export-components */
import { Button as ButtonPrimitive } from "@base-ui/react/button"
import { cva, type VariantProps } from "class-variance-authority"

import { cn } from "@/lib/utils"

const buttonVariants = cva(
  "group/button interactive-spring inline-flex shrink-0 items-center justify-center rounded-4xl border border-transparent bg-clip-padding text-sm font-semibold whitespace-nowrap outline-none select-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/30 focus-visible:brightness-110 disabled:pointer-events-none aria-invalid:border-destructive aria-invalid:ring-3 aria-invalid:ring-destructive/20 dark:aria-invalid:border-destructive/50 dark:aria-invalid:ring-destructive/40 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
  {
    variants: {
      variant: {
        default:
          "border-primary bg-primary text-primary-foreground active:border-(--primary-softer) active:bg-[color-mix(in_oklch,var(--primary),white_24%)] active:brightness-125 disabled:border-border disabled:bg-muted disabled:text-muted-foreground",
        secondary:
          "border-border bg-secondary text-secondary-foreground active:bg-secondary/90 active:text-white active:brightness-125 disabled:bg-muted disabled:text-muted-foreground aria-expanded:bg-secondary aria-expanded:text-secondary-foreground",
        ghost:
          "border-border bg-card active:bg-card/90 active:text-white active:brightness-125 disabled:bg-muted disabled:text-muted-foreground aria-expanded:bg-muted aria-expanded:text-foreground",
        destructive:
          "border-primary bg-card text-primary focus-visible:border-primary focus-visible:ring-primary/30 active:border-primary active:bg-[color-mix(in_oklch,var(--card),var(--primary)_28%)] active:text-primary active:brightness-125 disabled:border-border disabled:bg-muted disabled:text-muted-foreground",
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

function Button({
  className,
  variant = "default",
  size = "default",
  ...props
}: ButtonPrimitive.Props & VariantProps<typeof buttonVariants>) {
  return (
    <ButtonPrimitive
      data-slot="button"
      className={cn(buttonVariants({ variant, size, className }))}
      {...props}
    />
  )
}

export { Button, buttonVariants }
