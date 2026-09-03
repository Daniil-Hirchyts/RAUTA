import { useState, type ReactNode } from "react"

import { AppModal } from "@/components/app-modal"
import { Button } from "@/components/ui/button"
import { triggerHaptic } from "@/lib/haptics"

export type ConfirmationKind =
  "clear-data" | "delete-workout" | "discard-session" | "finish-workout"

const CONFIRMATION_COPY: Record<
  ConfirmationKind,
  {
    action: string
    description: string
    title: string
    tone: "default" | "destructive"
  }
> = {
  "clear-data": {
    action: "Continue",
    description:
      "Every workout, favorite, equipment preset, and preference is removed from this device and iCloud.",
    title: "Clear all data?",
    tone: "destructive",
  },
  "delete-workout": {
    action: "Delete workout",
    description: "This workout will be permanently removed from this device.",
    title: "Delete workout?",
    tone: "destructive",
  },
  "discard-session": {
    action: "Discard session",
    description:
      "The timer and everything checked off are lost. The workout itself stays saved.",
    title: "Discard this session?",
    tone: "destructive",
  },
  "finish-workout": {
    action: "Finish workout",
    description:
      "Your session progress and elapsed time will be saved to your history.",
    title: "Finish workout?",
    tone: "default",
  },
}

/**
 * Every confirmation in the app is this modal: a question about a single tap
 * is not worth a screen of its own, and the answer reads better with the page
 * it applies to still on screen behind it. `kind` drives it — null is closed.
 */
export function ConfirmModal({
  kind,
  onCancel,
  onConfirm,
}: {
  kind: ConfirmationKind | null
  onCancel: () => void
  onConfirm: () => void
}) {
  // Clearing everything asks twice: the second pass is the one that says the
  // data is not coming back.
  const [clearConfirmed, setClearConfirmed] = useState(false)
  const [asked, setAsked] = useState(kind)
  if (kind !== asked) {
    setAsked(kind)
    if (kind) setClearConfirmed(false)
  }

  const copy = kind ? CONFIRMATION_COPY[kind] : null
  const finalClear = kind === "clear-data" && clearConfirmed
  const title = finalClear ? "This cannot be undone" : (copy?.title ?? "")
  const description = finalClear
    ? "Export a backup first if you may need any of it later."
    : copy?.description
  const action = finalClear ? "Delete everything" : copy?.action

  let body: ReactNode = null
  if (copy) {
    body = (
      <>
        <div className="px-3 pt-3 pb-1 text-center">
          <h2 className="text-lg font-black tracking-[-0.02em]">{title}</h2>
          <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
            {description}
          </p>
        </div>
        <div className="mt-4 flex items-center gap-2">
          <Button className="flex-1" onClick={onCancel} variant="ghost">
            Cancel
          </Button>
          <Button
            className="flex-1"
            onClick={() => {
              if (kind === "clear-data" && !clearConfirmed) {
                triggerHaptic("medium")
                setClearConfirmed(true)
                return
              }
              triggerHaptic(kind === "finish-workout" ? "success" : "warning")
              onConfirm()
            }}
            variant={copy.tone === "destructive" ? "destructive" : "default"}
          >
            {action}
          </Button>
        </div>
      </>
    )
  }

  return (
    <AppModal label={title} onClose={onCancel} open={kind !== null}>
      {body}
    </AppModal>
  )
}
