import { useMemo, useRef, useState } from "react"
import { ArrowRight, CalendarRange, SlidersHorizontal, X } from "lucide-react"
import { Rauta } from "./rauta"
import { RautaSpeech } from "./rauta-speech"
import { AppModal } from "./app-modal"
import { Button } from "./ui/button"
import { MatrixLoader } from "./ui/matrix-loader"
import {
  adjustRemainingWeek,
  nextWeekEligibility,
  remainingWeekEligibility,
  type RemainingWeekOutcome,
} from "@/lib/training-adaptation"
import { triggerHaptic } from "@/lib/haptics"
import { useWorkouts } from "@/store/use-workouts"
import { useTrainingProfile } from "@/store/use-training-profile"
import { useTrainingRecords } from "@/store/use-training-records"
import { GOAL_CHOICES } from "@/lib/training-profile"
import { toISODate } from "@/lib/date"
import {
  activeProgramRecord,
  activePlannedSessions,
  isPlannedSessionRecorded,
} from "@/lib/training-plan"

/**
 * What RAUTA has to say, decided from application state alone.
 *
 * There is no conversation and no network behind any of this: a plan either
 * has sessions left this week or it does not, and the line follows from that.
 */
function planLine(input: {
  today: string
  todaySession: string | null
  remaining: number
  hasPlan: boolean
  nextWeekReady: boolean
}) {
  if (input.todaySession) return `${input.todaySession} is ready.`
  if (input.nextWeekReady) return "Your next week is ready."
  if (input.remaining === 1) return "One session left this week."
  if (input.remaining > 1) return `${input.remaining} sessions fit this week.`
  if (input.hasPlan) return "This week's plan is done. Ask me for the next one."
  return null
}

export function WorkoutCompanion({
  onCreate,
  onCreatePlan,
  onSettings,
  onResume,
}: {
  onCreate: () => void
  onCreatePlan: (sourceProgramId?: string) => void
  onSettings: () => void
  onResume?: () => void
}) {
  const [open, setOpen] = useState(false)
  const [working, setWorking] = useState(false)
  const busy = useRef(false)
  const [outcome, setOutcome] = useState<RemainingWeekOutcome | null>(null)
  const profile = useTrainingProfile((state) => state.profile)
  const trainingData = useTrainingRecords((state) => state.data)
  const workouts = useWorkouts((state) => state.workouts)
  const now = new Date().toISOString()
  const eligibility = remainingWeekEligibility(
    trainingData,
    now,
    workouts
  )
  const nextEligibility = nextWeekEligibility(trainingData, now, workouts)
  const canAdjust = !onResume && eligibility.status === "eligible"
  const canPlanNext = !onResume && nextEligibility.status === "eligible"
  const nextSourceId =
    nextEligibility.status === "eligible" ? nextEligibility.source.id : null
  const offer = "I can adjust the rest of your week from what you logged."
  const nextOffer = "This week is done. Let’s plan the next one."
  const today = toISODate(new Date())

  const plan = useMemo(() => {
    const sessions = activePlannedSessions(trainingData).filter(
      (session) => !isPlannedSessionRecorded(session.sessionId, trainingData)
    )
    const ahead = sessions.filter((session) => session.date >= today)
    const active = activeProgramRecord(trainingData)
    const nextWeekReady =
      active?.revision?.reason === "next_week" &&
      ahead.length > 0 &&
      ahead.every((session) => session.date > today)
    return {
      line: planLine({
        today,
        todaySession:
          ahead.find((session) => session.date === today)?.title ?? null,
        remaining: ahead.length,
        hasPlan: Boolean(trainingData.activeProgramId),
        nextWeekReady,
      }),
      hasPlan: Boolean(trainingData.activeProgramId),
      nextWeekReady,
    }
  }, [today, trainingData])

  const close = () => {
    if (!busy.current) setOpen(false)
  }
  const adjust = () => {
    if (busy.current) return
    busy.current = true
    setWorking(true)
    setOutcome(null)
    // Let the existing loader paint before the synchronous engine runs.
    requestAnimationFrame(() =>
      requestAnimationFrame(() => {
        const result = adjustRemainingWeek()
        busy.current = false
        setWorking(false)
        setOutcome(result)
        triggerHaptic(result.status === "adjusted" ? "success" : "warning")
        if (result.status === "adjusted") setOpen(false)
      })
    )
  }
  const act = (action: () => void) => {
    close()
    action()
  }
  return (
    <>
      <div className="mx-(--app-content-inset) flex items-center gap-1.5">
        <Rauta
          mood={onResume ? "focused" : plan.line ? "proud" : "calm"}
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
                : (outcome?.message ??
                  (canAdjust ? offer : null) ??
                  (canPlanNext ? nextOffer : null) ??
                  plan.line ??
                  (profile.name
                    ? `Ready, ${profile.name}? I can shape today's session.`
                    : "Tell me what we're training today."))}
            </strong>
            <span className="mt-1.5 flex items-center gap-1.5 text-[11px] text-muted-foreground">
              {GOAL_CHOICES[profile.goal].title} ·{" "}
              {profile.preferredSessionDurationMinutes} min
              <ArrowRight
                aria-hidden="true"
                className="size-3.5 text-primary"
              />
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
          <h2 className="pr-9 text-xl font-bold">
            {working ? "Adjusting your week." : "RAUTA is ready."}
          </h2>
          <p
            className="mt-2 mb-5 text-sm text-muted-foreground"
            role={outcome?.status === "blocked" ? "alert" : "status"}
          >
            {outcome?.message ??
              (canAdjust
                ? offer
                : canPlanNext
                  ? nextOffer
                  : plan.nextWeekReady
                    ? plan.line
                : plan.hasPlan && eligibility.status === "blocked"
                  ? eligibility.message
                  : "Let me plan the week, choose your own exercises, or tune your training preferences.")}
          </p>
          <div className="space-y-2">
            {canAdjust || working ? (
              <Button className="w-full" disabled={working} onClick={adjust}>
                {working ? (
                  <MatrixLoader
                    label="Adjusting your week"
                    rounded
                    variant="orbit"
                  />
                ) : (
                  "Adjust remaining week"
                )}
              </Button>
            ) : null}
            {canPlanNext && nextSourceId ? (
              <Button
                className="w-full"
                disabled={working}
                onClick={() => act(() => onCreatePlan(nextSourceId))}
              >
                <CalendarRange className="size-4" />
                Plan next week
              </Button>
            ) : null}
            {onResume ? (
              <Button
                className="w-full"
                disabled={working}
                onClick={() => act(onResume)}
              >
                Resume workout <ArrowRight className="size-4" />
              </Button>
            ) : null}
            <Button
              className="w-full"
              disabled={working}
              variant={
                onResume || canAdjust || canPlanNext ? "secondary" : "default"
              }
              onClick={() => act(onCreatePlan)}
            >
              <CalendarRange className="size-4" />
              {plan.hasPlan ? "New training week" : "Create training week"}
            </Button>
            <Button
              className="w-full"
              disabled={working}
              variant="secondary"
              onClick={() => act(onCreate)}
            >
              Choose exercises <ArrowRight className="size-4" />
            </Button>
            <Button
              className="w-full"
              disabled={working}
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
