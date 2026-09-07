import { useState } from "react"
import { ArrowRight, SlidersHorizontal, X } from "lucide-react"
import { Rauta } from "./rauta"
import { RautaSpeech } from "./rauta-speech"
import { AppModal } from "./app-modal"
import { Button } from "./ui/button"
import { useTrainingProfile } from "@/store/use-training-profile"
import { GOAL_CHOICES } from "@/lib/training-profile"

export function WorkoutCompanion({
  onCreate,
  onSettings,
  onResume,
}: {
  onCreate: () => void
  onSettings: () => void
  onResume?: () => void
}) {
  const [open, setOpen] = useState(false)
  const profile = useTrainingProfile((state) => state.profile)
  const close = () => setOpen(false)
  const act = (action: () => void) => {
    close()
    action()
  }
  return (
    <>
      <div className="mx-(--app-content-inset) flex items-center gap-1.5">
        <Rauta
          mood={onResume ? "focused" : "calm"}
          size={108}
          label="Open RAUTA actions"
          onActivate={() => setOpen(true)}
        />
        <button
          className="min-w-0 flex-1 py-2 text-left active:scale-[0.985]"
          type="button"
          onClick={() => setOpen(true)}
          aria-label="Train with RAUTA"
        >
          <RautaSpeech>
            <strong className="block text-[15px] leading-snug tracking-tight">
              {onResume
                ? "Your workout is waiting. Want to continue?"
                : profile.name
                  ? `Ready, ${profile.name}? I can shape today's session.`
                  : "Tell me what we're training today."}
            </strong>
            <span className="mt-1.5 flex items-center gap-1.5 text-[11px] text-muted-foreground">
              {GOAL_CHOICES[profile.goal].title} · {profile.preferredSessionDurationMinutes} min
              <ArrowRight aria-hidden="true" className="size-3.5 text-primary" />
            </span>
          </RautaSpeech>
        </button>
      </div>
      <AppModal open={open} onClose={close} label="RAUTA actions">
        <div className="relative p-2">
          <button
            autoFocus
            type="button"
            aria-label="Close RAUTA actions"
            onClick={close}
            className="absolute top-0 right-0 grid size-11 place-items-center rounded-full active:bg-muted"
          >
            <X className="size-5" />
          </button>
          <h2 className="pr-9 text-xl font-bold">RAUTA is ready.</h2>
          <p className="mt-2 mb-5 text-sm text-muted-foreground">
            Choose your exercises, or tune your training preferences.
          </p>
          <div className="space-y-2">
            {onResume ? (
              <Button className="w-full" onClick={() => act(onResume)}>
                Resume workout <ArrowRight className="size-4" />
              </Button>
            ) : null}
            <Button
              className="w-full"
              variant={onResume ? "secondary" : "default"}
              onClick={() => act(onCreate)}
            >
              Choose exercises <ArrowRight className="size-4" />
            </Button>
            <Button
              className="w-full"
              variant="ghost"
              onClick={() => act(onSettings)}
            >
              <SlidersHorizontal className="size-4" /> My preferences
            </Button>
          </div>
        </div>
      </AppModal>
    </>
  )
}
