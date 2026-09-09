import { useState } from "react"
import { ChevronLeft, SlidersHorizontal } from "lucide-react"

import { AppControlMorph } from "@/components/app-morph"
import {
  AppControls,
  AppHeaderButton,
  AppScreen,
  AppShellHeader,
  AppSurface,
} from "@/components/app-shell"
import { Rauta } from "@/components/rauta"
import { Button } from "@/components/ui/button"
import { Calendar } from "@/components/ui/calendar"
import { MatrixLoader } from "@/components/ui/matrix-loader"
import { toISODate } from "@/lib/date"
import { triggerHaptic } from "@/lib/haptics"
import {
  createTrainingPlanForDates,
  type PlanBlock,
  type PlanBlockPage,
} from "@/lib/training-plan"
import { useTrainingProfile } from "@/store/use-training-profile"
import { experienceLabel, GOAL_CHOICES } from "@/lib/training-profile"

const FIX_LABELS: Record<PlanBlockPage, string> = {
  "profile-basics": "Open my details",
  "profile-training": "Open training preferences",
  "profile-health": "Open health",
  "profile-equipment": "Open my equipment",
  "profile-priorities": "Open muscle priorities",
}

/**
 * Create training week.
 *
 * The only question here is the one the profile cannot answer: which days are
 * free this week. Goal, experience, age, health, session length, priorities
 * and equipment are already saved, and the adapter reads them straight out of
 * their stores — so this page never asks for any of them a second time.
 */
export function PlanWeekPage({
  onBack,
  onCreated,
  onOpenProfilePage,
  sourceProgramId,
}: {
  onBack: () => void
  onCreated: (programId: string) => void
  onOpenProfilePage: (page: PlanBlockPage) => void
  sourceProgramId?: string
}) {
  const profile = useTrainingProfile((state) => state.profile)
  const continuing = Boolean(sourceProgramId)
  const [dates, setDates] = useState<Date[]>(() => {
    const monday = new Date()
    monday.setHours(0, 0, 0, 0)
    monday.setDate(monday.getDate() + ((8 - monday.getDay()) % 7 || 7))
    return [0, 2, 4].map((offset) => {
      const date = new Date(monday)
      date.setDate(date.getDate() + offset)
      return date
    })
  })
  const [working, setWorking] = useState(false)
  const [block, setBlock] = useState<Pick<
    PlanBlock,
    "message" | "page" | "issues"
  > | null>(null)

  const create = () => {
    if (working) return
    setWorking(true)
    setBlock(null)
    // One frame for the button to settle before a synchronous solve blocks it.
    requestAnimationFrame(() => {
      let outcome
      try {
        outcome = createTrainingPlanForDates({
          dates: dates.map(toISODate),
          sourceProgramId,
        })
      } catch (error) {
        setWorking(false)
        setBlock({
          message: error instanceof Error ? error.message : String(error),
          page: null,
          issues: [],
        })
        triggerHaptic("warning")
        return
      }
      setWorking(false)
      if (outcome.status === "blocked") {
        setBlock(outcome)
        triggerHaptic("warning")
        return
      }
      triggerHaptic("success")
      onCreated(outcome.programId)
    })
  }

  return (
    <AppScreen bottomControls>
      <AppSurface>
        <AppShellHeader
          left={
            <AppHeaderButton aria-label="Back to workouts" onClick={onBack}>
              <ChevronLeft />
            </AppHeaderButton>
          }
          title={continuing ? "Extend training plan" : "Create training plan"}
        />

        <div className="app-scroll-region min-h-0 flex-1 overflow-y-auto px-(--app-content-inset) pt-5 pb-6">
          <div className="flex items-center gap-1.5">
            <Rauta
              size={92}
              speech={
                continuing
                  ? "Pick future dates. I'll use your logged sets for them."
                  : "Pick your dates. I'll use your saved preferences for the rest."
              }
            />
            <div className="min-w-0 flex-1 py-3">
              <strong className="block text-[15px] leading-snug tracking-tight">
                {continuing
                  ? "Choose every date you want to add."
                  : "Choose every date you want in this plan."}
              </strong>
              <span className="mt-1.5 block text-[11px] text-muted-foreground">
                {GOAL_CHOICES[profile.goal].title} ·{" "}
                {profile.preferredSessionDurationMinutes} min ·{" "}
                {experienceLabel(profile.trainingExperience)}
              </span>
            </div>
          </div>

          <div className="mt-6 overflow-hidden rounded-3xl border border-border bg-card p-1">
            <Calendar
              className="mx-auto w-full"
              disabled={{ before: new Date(new Date().setHours(0, 0, 0, 0)) }}
              mode="multiple"
              onSelect={(selected) => {
                triggerHaptic("selection")
                setBlock(null)
                setDates(selected ?? [])
              }}
              selected={dates}
            />
          </div>

          <p className="mt-3 px-1 text-sm leading-relaxed text-muted-foreground">
            {dates.length === 0
              ? "Pick at least one date."
              : `${dates.length} training date${dates.length === 1 ? "" : "s"} selected. You can move to another month and keep adding dates.`}
          </p>

          {block ? (
            <PlanBlockNotice
              block={block}
              onOpenProfilePage={onOpenProfilePage}
            />
          ) : null}
        </div>
      </AppSurface>

      <AppControls transitionKey={`plan-week:${working}`}>
        <AppControlMorph className="w-full" role="primary">
          <Button
            className="w-full shadow-xl shadow-black/25"
            disabled={dates.length === 0 || working}
            onClick={create}
            size="cta"
          >
            {working ? (
              <MatrixLoader
                label={continuing ? "Extending your plan" : "Building your plan"}
                rounded
                variant="orbit"
              />
            ) : continuing ? (
              "Extend plan"
            ) : (
              "Create plan"
            )}
          </Button>
        </AppControlMorph>
      </AppControls>
    </AppScreen>
  )
}

function PlanBlockNotice({
  block,
  onOpenProfilePage,
}: {
  block: Pick<PlanBlock, "message" | "page" | "issues">
  onOpenProfilePage: (page: PlanBlockPage) => void
}) {
  const page = block.page
  return (
    <div
      className="mt-5 rounded-3xl border border-primary/45 bg-[color-mix(in_oklch,var(--card),var(--primary)_8%)] p-4"
      role="alert"
    >
      <p className="text-xs font-black tracking-[0.16em] text-primary uppercase">
        No plan yet
      </p>
      <p className="mt-2 text-[15px] leading-snug font-medium">
        {block.message}
      </p>
      {page ? (
        <Button
          className="mt-3 w-full"
          onClick={() => onOpenProfilePage(page)}
          variant="secondary"
        >
          <SlidersHorizontal className="size-4" />
          {FIX_LABELS[page]}
        </Button>
      ) : null}
    </div>
  )
}
