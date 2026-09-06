import { type ReactNode } from "react"
import { ChevronRight } from "lucide-react"

import { cn } from "@/lib/utils"

/** Every row in every section shares one box, so the dividers line up and a
 *  switch row is exactly as tall as the link row above it. */
const ROW =
  "flex min-h-16 w-full items-center gap-3 border-b border-border px-4 py-3 text-left last:border-b-0"

export function SettingsSection({
  children,
  title,
}: {
  children: ReactNode
  title: string
}) {
  return (
    <section>
      <h2 className="mb-2 px-1 text-xs font-bold tracking-[0.16em] text-muted-foreground uppercase">
        {title}
      </h2>
      <div className="overflow-hidden rounded-3xl border border-border bg-card shadow-sm shadow-black/10">
        {children}
      </div>
    </section>
  )
}

function RowIcon({ children }: { children: ReactNode }) {
  return (
    <span className="grid size-5 shrink-0 place-items-center text-primary [&_svg]:size-5">
      {children}
    </span>
  )
}

function RowLabel({
  description,
  title,
}: {
  description?: string
  title: string
}) {
  return (
    <div className="min-w-0 flex-1">
      <p className="text-base leading-snug font-semibold">{title}</p>
      {description ? (
        <p className="mt-0.5 text-sm leading-snug text-muted-foreground">
          {description}
        </p>
      ) : null}
    </div>
  )
}

export function SettingsRow({
  children,
  description,
  icon,
  title,
}: {
  children?: ReactNode
  description?: string
  icon: ReactNode
  title: string
}) {
  return (
    <div className={ROW}>
      <RowIcon>{icon}</RowIcon>
      <RowLabel description={description} title={title} />
      {children}
    </div>
  )
}

export function SettingsAction({
  description,
  icon,
  onClick,
  title,
  tone = "default",
  value,
}: {
  description?: string
  icon: ReactNode
  onClick: () => void
  title: string
  tone?: "default" | "destructive"
  /** What the row is currently set to, read before the chevron the way a
   *  system settings list reads. */
  value?: string
}) {
  return (
    <button
      className={cn(
        ROW,
        "interactive-spring active:bg-muted/80",
        tone === "destructive" && "text-primary"
      )}
      data-haptics="off"
      onClick={onClick}
      type="button"
    >
      <RowIcon>{icon}</RowIcon>
      <RowLabel description={description} title={title} />
      {value ? (
        <span className="max-w-[45%] truncate text-sm font-medium text-muted-foreground">
          {value}
        </span>
      ) : null}
      <ChevronRight
        className={cn(
          "size-5 shrink-0",
          tone === "destructive" ? "text-primary" : "text-muted-foreground"
        )}
      />
    </button>
  )
}
