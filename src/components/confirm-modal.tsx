import { useState, type ReactNode } from "react"

import { AppModal } from "@/components/app-modal"
import { Button } from "@/components/ui/button"
import { triggerHaptic } from "@/lib/haptics"
import { countLabel } from "@/lib/text"
import { useFavorites } from "@/store/use-favorites"
import { useFilters } from "@/store/use-filters"
import { useWorkouts } from "@/store/use-workouts"

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
  // The confirming button repeats the title's verb rather than saying
  // "Continue": what is about to happen should be readable from the button the
  // thumb is already over, without going back up to the question.
  "clear-data": {
    action: "Clear data",
    description: "",
    title: "Clear all data?",
    tone: "destructive",
  },
  "delete-workout": {
    action: "Delete workout",
    description:
      "The exercises stay in the library. Only this day's plan and its recorded time go.",
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

  const workoutCount = useWorkouts((state) => state.workouts.length)
  const favoriteCount = useFavorites((state) => state.favoriteIds.length)
  const presetCount = useFilters((state) => state.equipmentPresets.length)

  const copy = kind ? CONFIRMATION_COPY[kind] : null
  const finalClear = kind === "clear-data" && clearConfirmed
  // "This cannot be undone" only raises the voice. What someone needs in order
  // to answer is what they are about to lose, counted — and then, on the
  // second pass, the one fact the first screen cannot give them: this reaches
  // iCloud, so no other device and no reinstall is holding a copy.
  const title = finalClear ? "This clears iCloud too" : (copy?.title ?? "")
  const description =
    kind === "clear-data"
      ? finalClear
        ? "No other device keeps a copy, and reinstalling will not bring one back. Export a backup first if you might want any of this later."
        : `${countLabel(workoutCount, "workout")}, ${countLabel(favoriteCount, "favorite")} and ${countLabel(presetCount, "equipment preset")} are deleted, and your settings go back to their defaults.`
      : copy?.description
  const action = finalClear ? "Delete everything" : copy?.action

  let body: ReactNode = null
  if (copy) {
    body = (
      <>
        <div className="px-3 pt-3 pb-1 text-center">
          <h2 className="font-heading text-lg font-black tracking-[-0.02em]">{title}</h2>
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
