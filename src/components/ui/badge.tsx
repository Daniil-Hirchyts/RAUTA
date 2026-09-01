/* eslint-disable react-refresh/only-export-components */
import { mergeProps } from "@base-ui/react/merge-props"
import { useRender } from "@base-ui/react/use-render"
import { cva, type VariantProps } from "class-variance-authority"

import { cn } from "@/lib/utils"

const badgeVariants = cva(
  "group/badge interactive-spring inline-flex h-6 w-fit shrink-0 items-center justify-center gap-1 overflow-hidden rounded-3xl border border-transparent px-2.5 py-0.5 text-xs font-medium whitespace-nowrap focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:brightness-110 has-data-[icon=inline-end]:pr-1.5 has-data-[icon=inline-start]:pl-1.5 aria-invalid:border-destructive aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40 [&>svg]:pointer-events-none [&>svg]:size-3!",
  {
    variants: {
      variant: {
        default:
          "bg-primary text-primary-foreground [a]:active:brightness-125 [a]:active:bg-[color-mix(in_oklch,var(--primary),white_24%)]",
        secondary:
          "bg-secondary text-secondary-foreground [a]:active:brightness-125 [a]:active:bg-secondary/90",
        destructive:
          "bg-destructive/10 text-destructive focus-visible:ring-destructive/20 dark:bg-destructive/20 dark:focus-visible:ring-destructive/40 [a]:active:brightness-125",
        outline:
          "border-border text-foreground [a]:active:brightness-125 [a]:active:bg-muted/80 [a]:active:text-white",
        ghost:
          "active:brightness-125 active:bg-muted/80 active:text-white dark:active:bg-muted/70",
        link: "text-primary underline-offset-4 active:brightness-135 active:underline",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  }
)

function Badge({
  className,
  variant = "default",
  render,
  ...props
}: useRender.ComponentProps<"span"> & VariantProps<typeof badgeVariants>) {
  return useRender({
    defaultTagName: "span",
    props: mergeProps<"span">(
      {
        className: cn(badgeVariants({ variant }), className),
      },
      props
    ),
    render,
    state: {
      slot: "badge",
      variant,
    },
  })
}

export { Badge, badgeVariants }
