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
import { RautaStill } from "@/components/rauta"
import { RautaSpeech } from "@/components/rauta-speech"
import { Button } from "@/components/ui/button"
import { MatrixLoader } from "@/components/ui/matrix-loader"
import { triggerHaptic } from "@/lib/haptics"
import {
  createTrainingWeek,
  DEFAULT_TRAINING_DAYS,
  WEEK_DAYS,
  type PlanBlock,
  type PlanBlockPage,
} from "@/lib/training-plan"
import { cn } from "@/lib/utils"
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
}: {
  onBack: () => void
  onCreated: (programId: string) => void
  onOpenProfilePage: (page: PlanBlockPage) => void
}) {
  const profile = useTrainingProfile((state) => state.profile)
  const [days, setDays] = useState<number[]>([...DEFAULT_TRAINING_DAYS])
  const [working, setWorking] = useState(false)
  const [block, setBlock] = useState<PlanBlock | null>(null)

  const toggle = (offset: number) => {
    triggerHaptic("selection")
    setBlock(null)
    setDays((current) =>
      current.includes(offset)
        ? current.filter((day) => day !== offset)
        : [...current, offset].sort((left, right) => left - right)
    )
  }

  const create = () => {
    if (working) return
    setWorking(true)
    setBlock(null)
    // One frame for the button to settle before a synchronous solve blocks it.
    requestAnimationFrame(() => {
      let outcome
      try {
        outcome = createTrainingWeek({ days })
      } catch (error) {
        setWorking(false)
        setBlock({
          reason: "input",
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
          title="Create training week"
        />

        <div className="app-scroll-region min-h-0 flex-1 overflow-y-auto px-(--app-content-inset) pt-5 pb-6">
          <div className="flex items-center gap-1.5">
            <span aria-hidden="true" className="size-[92px] shrink-0">
              <RautaStill />
            </span>
            <RautaSpeech>
              <strong className="block text-[15px] leading-snug tracking-tight">
                Tell me which days you can train. I know the rest.
              </strong>
              <span className="mt-1.5 block text-[11px] text-muted-foreground">
                {GOAL_CHOICES[profile.goal].title} ·{" "}
                {profile.preferredSessionDurationMinutes} min ·{" "}
                {experienceLabel(profile.trainingExperience)}
              </span>
            </RautaSpeech>
          </div>

          {/* Seven across on a phone; four across on the narrowest screens,
              where a seventh column would leave each day too small to hit. */}
          <div
            aria-label="Days you can train"
            className="mt-6 grid grid-cols-4 gap-1.5 min-[360px]:grid-cols-7"
            role="group"
          >
            {WEEK_DAYS.map((day) => {
              const selected = days.includes(day.offset)
              return (
                <button
                  aria-checked={selected}
                  aria-label={day.long}
                  className={cn(
                    "interactive-spring flex h-16 min-w-0 flex-col items-center justify-center rounded-2xl border text-[13px] font-bold",
                    selected
                      ? "border-primary/55 bg-[color-mix(in_oklch,var(--card),var(--primary)_12%)] text-foreground"
                      : "border-border bg-card text-muted-foreground active:bg-muted/80"
                  )}
                  data-haptics="off"
                  key={day.offset}
                  onClick={() => toggle(day.offset)}
                  role="checkbox"
                  type="button"
                >
                  <span
                    aria-hidden="true"
                    className={cn(
                      "mb-1.5 size-1.5 rounded-full",
                      selected ? "bg-primary" : "bg-transparent"
                    )}
                  />
                  {day.short}
                </button>
              )
            })}
          </div>

          <p className="mt-3 px-1 text-sm leading-relaxed text-muted-foreground">
            {days.length === 0
              ? "Pick at least one day."
              : `${days.length} training day${days.length === 1 ? "" : "s"} next week. Everything else comes from your profile.`}
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
            disabled={days.length === 0 || working}
            onClick={create}
            size="cta"
          >
            {working ? (
              <MatrixLoader
                label="Building your week"
                rounded
                variant="orbit"
              />
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
  block: PlanBlock
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
