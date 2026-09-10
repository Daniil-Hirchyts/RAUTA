import { useMemo, useRef, useState } from "react"
import { Rauta } from "./rauta"
import type { RautaAction } from "./rauta-panel"
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
  onResume,
}: {
  onCreate: () => void
  onCreatePlan: (sourceProgramId?: string) => void
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
  const eligibility = remainingWeekEligibility(trainingData, now, workouts)
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
        if (result.status === "adjusted") {
          setOpen(false)
        }
      })
    )
  }
  const act = (action: () => void) => {
    close()
    action()
  }
  const blocked =
    plan.hasPlan && eligibility.status === "blocked"
      ? eligibility.message
      : null
  // What RAUTA is saying: the outcome of the last thing it did, the offer it
  // is making, or the state of the week. Opening the panel is a question —
  // "what can you do?" — so an answer that is a refusal is given there.
  const line =
    outcome?.message ??
    (onResume
      ? "Your workout is waiting. Want to continue?"
      : ((canAdjust ? offer : null) ??
        (canPlanNext ? nextOffer : null) ??
        // A week that is already planned is the answer to "what now?"; why the
        // logged sets cannot be used only matters when there is nothing better
        // to say.
        (open && !plan.nextWeekReady && blocked ? blocked : null) ??
        plan.line ??
        (profile.name
          ? `Ready, ${profile.name}? I can shape today's session.`
          : "Tell me what we're training today.")))

  const actions: RautaAction[] = [
    ...(canAdjust || working
      ? [
          {
            label: working ? (
              <MatrixLoader
                label="Adjusting your week"
                rounded
                variant="orbit"
              />
            ) : (
              "Adjust remaining week"
            ),
            onSelect: adjust,
            primary: true,
            disabled: working,
          },
        ]
      : []),
    ...(canPlanNext && nextSourceId
      ? [
          {
            label: "Extend training plan",
            onSelect: () => act(() => onCreatePlan(nextSourceId)),
            primary: true,
            disabled: working,
          },
        ]
      : []),
    {
      label: plan.hasPlan ? "New training plan" : "Create training plan",
      onSelect: () => act(() => onCreatePlan()),
      primary: !onResume && !canAdjust && !canPlanNext,
      disabled: working,
    },
    {
      label: "Choose exercises",
      onSelect: () => act(onCreate),
      disabled: working,
    },
  ]

  return (
    <Rauta
      actions={actions}
      alert={outcome?.status === "blocked"}
      label="Open RAUTA actions"
      meta={`${GOAL_CHOICES[profile.goal].title} · ${profile.preferredSessionDurationMinutes} min`}
      mood={onResume ? "focused" : plan.line ? "proud" : "calm"}
      onOpenChange={(next) => {
        if (!busy.current) setOpen(next)
      }}
      open={open}
      reactionKey={outcome ? `${outcome.status}:${outcome.message}` : undefined}
      size={104}
      speech={line}
    />
  )
}
