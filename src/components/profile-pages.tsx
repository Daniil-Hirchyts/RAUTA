import { useRef, useState, type ReactNode } from "react"
import { ChevronLeft, FlipHorizontal2, Plus, Weight, X } from "lucide-react"

import { AppControlMorph } from "@/components/app-morph"
import {
  AppControlButton,
  AppControls,
  AppHeaderButton,
  AppScreen,
  AppShellHeader,
  AppSurface,
} from "@/components/app-shell"
import { type BodySide } from "@/components/body-map"
import { EquipmentPresetEditor } from "@/components/equipment-presets"
import { EquipmentLoadSettings } from "@/components/equipment-load-settings"
import { FlowProgress } from "@/components/flow-progress"
import { MorphingActionSlot } from "@/components/morphing-action-slot"
import {
  AgeKnob,
  ExperiencePicker,
  GoalPicker,
  HealthDisclosure,
  HealthPicker,
  MusclePriorityPicker,
  ProfileEquipmentPicker,
  ProfileEquipmentPresets,
  ProfileNameField,
  SessionDurationKnob,
} from "@/components/profile-controls"
import { ProfileCompanion } from "@/components/profile-companion"
import { Button } from "@/components/ui/button"
import { triggerHaptic } from "@/lib/haptics"
import { loadConfigurableEquipment } from "@/lib/resistance"
import { countLabel } from "@/lib/text"
import { cn } from "@/lib/utils"
import { useFilters } from "@/store/use-filters"
import { useTrainingProfile } from "@/store/use-training-profile"

type ProfileFlowStep = {
  /** The header title, and the whole question the step asks. */
  title: string
  content: ReactNode
  /** One line under a control that would otherwise sit alone on the screen. */
  caption?: string
  /** Rendered in the surface's bottom dock, over the scroller. */
  dock?: ReactNode
}

/**
 * One question per screen, answered one after another.
 *
 * A settings row opens a group of these rather than a dialog or a page with
 * everything stacked on it: a single question can be centred, read at a
 * glance and answered with one tap, and the progress dots say how much is
 * left. First-run setup is the same flow with every step in it, so setting the
 * app up and changing your mind later are the same screens in the same order.
 */
function ProfileStepFlow({
  finishAriaLabel,
  finishLabel,
  name,
  onBack,
  onFinish,
  onSkip,
  steps,
}: {
  finishAriaLabel: string
  finishLabel: string
  /** Used for the command band's transition key and nothing else. */
  name: string
  /** Leaving the first step. Absent when the flow is the page underneath. */
  onBack?: () => void
  onFinish: () => void
  onSkip?: () => void
  steps: ProfileFlowStep[]
}) {
  const scrollRef = useRef<HTMLDivElement>(null)
  const [index, setIndex] = useState(0)
  const step = steps[Math.min(index, steps.length - 1)]
  const last = index >= steps.length - 1

  const back = () => {
    triggerHaptic("selection")
    if (index > 0) setIndex((current) => current - 1)
    else onBack?.()
  }

  return (
    <AppScreen bottomControls>
      <AppSurface>
        <AppShellHeader
          key={`header:${step.title}`}
          above={
            steps.length > 1 ? (
              <FlowProgress stage={index + 1} steps={steps.length} />
            ) : undefined
          }
          left={
            index > 0 || onBack ? (
              <AppHeaderButton
                aria-label={index > 0 ? "Previous step" : "Back"}
                onClick={back}
              >
                <ChevronLeft />
              </AppHeaderButton>
            ) : null
          }
          right={
            onSkip ? (
              <AppHeaderButton aria-label="Skip setup" onClick={onSkip}>
                <X />
              </AppHeaderButton>
            ) : null
          }
          scrollRef={scrollRef}
          title={step.title}
        />

        {/* Auto margins rather than centring: one control sits in the middle of
            the screen, and a long list still scrolls from the top. The bottom
            padding clears the surface's own fade — and the preset dock, on the
            step that has one. */}
        <div
          className={cn(
            "app-scroll-region flex min-h-0 flex-1 flex-col overflow-y-auto px-(--app-content-inset) pt-5",
            step.dock ? "pb-28" : "pb-14"
          )}
          ref={scrollRef}
          tabIndex={-1}
          aria-label={step.title}
          key={step.title}
        >
          <div className="profile-step-content my-auto w-full shrink-0">
            <ProfileCompanion step={step.title} />
            {step.content}
            {step.caption ? (
              <p className="mt-3 px-1 text-center text-sm text-muted-foreground">
                {step.caption}
              </p>
            ) : null}
          </div>
        </div>

        {step.dock ? (
          <div className="app-surface-bottom-dock equipment-presets-dock">
            {step.dock}
          </div>
        ) : null}
      </AppSurface>

      <AppControls transitionKey={`${name}:${index}`}>
        <AppControlMorph className="app-command-fill" role="primary">
          <Button
            // Naming the step it leads to keeps a repeated tap on the same word
            // from reading as the same press twice.
            aria-label={
              last ? finishAriaLabel : `Continue to ${steps[index + 1].title}`
            }
            className="w-full"
            onClick={() => {
              if (last) {
                onFinish()
                return
              }
              triggerHaptic("medium")
              setIndex((current) => current + 1)
            }}
            size="cta"
          >
            {last ? finishLabel : "Continue"}
          </Button>
        </AppControlMorph>
      </AppControls>
    </AppScreen>
  )
}

/** Name and age share a screen: they are the two things the app needs before
 *  it can say anything about you, neither is a question worth a screen of its
 *  own, and the dial reads better with something above it than with the whole
 *  page to itself. */
const ABOUT_STEP: ProfileFlowStep = {
  title: "About you",
  content: (
    <div className="flex flex-col gap-4">
      <ProfileNameField />
      <AgeKnob label={null} />
    </div>
  ),
}
/** Health rides along with experience: both are statements about the body
 *  that is going to train, neither is answered often, and for most people the
 *  health half is one glance at a row that already says "Ready to train". */
const EXPERIENCE_STEP: ProfileFlowStep = {
  title: "Experience",
  content: (
    <div className="flex flex-col gap-5">
      <ExperiencePicker />
      <HealthDisclosure />
    </div>
  ),
}
const GOAL_STEP: ProfileFlowStep = { title: "Goal", content: <GoalPicker /> }
const DURATION_STEP: ProfileFlowStep = {
  title: "Session length",
  content: <SessionDurationKnob label={null} />,
}
const GYM_STEP: ProfileFlowStep = {
  title: "Your gym",
  content: <ProfileEquipmentPicker />,
  dock: <ProfileEquipmentPresets className="px-(--app-content-inset)" />,
}
/** The same question on a screen of its own, for the one place that arrives
 *  at it directly: a refusal to plan sends people straight here to change the
 *  answer that caused it. */
const HEALTH_STEP: ProfileFlowStep = {
  title: "Health",
  content: <HealthPicker />,
}

const PROFILE_STEPS = [ABOUT_STEP, EXPERIENCE_STEP]
const TRAINING_STEPS = [GOAL_STEP, DURATION_STEP]

export function ProfileBasicsPage({ onBack }: { onBack: () => void }) {
  return (
    <ProfileStepFlow
      finishAriaLabel="Done with profile"
      finishLabel="Done"
      name="profile"
      onBack={onBack}
      onFinish={onBack}
      steps={PROFILE_STEPS}
    />
  )
}

export function TrainingPreferencesPage({ onBack }: { onBack: () => void }) {
  return (
    <ProfileStepFlow
      finishAriaLabel="Done with training"
      finishLabel="Done"
      name="training"
      onBack={onBack}
      onFinish={onBack}
      steps={TRAINING_STEPS}
    />
  )
}

export function HealthEligibilityPage({ onBack }: { onBack: () => void }) {
  return (
    <ProfileStepFlow
      finishAriaLabel="Done with health"
      finishLabel="Done"
      name="health"
      onBack={onBack}
      onFinish={onBack}
      steps={[HEALTH_STEP]}
    />
  )
}

/** The equipment you have, on its own page because a grid of pictures is not
 *  something to stuff into a settings list. Everything on it is live: there is
 *  nothing to save, only somewhere to go back to. */
export function ProfileEquipmentPage({
  onBack,
  onOpenLoadSteps,
}: {
  onBack: () => void
  onOpenLoadSteps: () => void
}) {
  const [presetEditorOpen, setPresetEditorOpen] = useState(false)
  const gymEquipment = useFilters((state) => state.gymEquipment)
  const setGymEquipment = useFilters((state) => state.setGymEquipment)
  const loadEquipment = loadConfigurableEquipment(gymEquipment)

  return (
    <AppScreen bottomControls>
      <AppSurface>
        <AppShellHeader
          left={
            <AppHeaderButton aria-label="Back" onClick={onBack}>
              <ChevronLeft />
            </AppHeaderButton>
          }
          subtitle={
            gymEquipment.length > 0
              ? countLabel(gymEquipment.length, "item")
              : null
          }
          title="Available equipment"
        />
        <section
          aria-label="Available equipment"
          className="app-scroll-region min-h-0 flex-1 overflow-y-auto px-(--app-content-inset) pt-5 pb-28"
          tabIndex={-1}
        >
          <ProfileEquipmentPicker />
        </section>
        {presetEditorOpen ? null : (
          <div className="app-surface-bottom-dock equipment-presets-dock">
            <ProfileEquipmentPresets className="px-(--app-content-inset)" />
          </div>
        )}
      </AppSurface>

      <AppControls
        transitionKey={`profile-equipment:${presetEditorOpen}:${gymEquipment.length}`}
      >
        {presetEditorOpen ? (
          <div className="flex items-center gap-2.5">
            <EquipmentPresetEditor
              className="flex-1"
              equipment={gymEquipment}
              onSaved={() => setPresetEditorOpen(false)}
            />
            <AppControlMorph role="primary">
              <AppControlButton
                aria-label="Close preset editor"
                onClick={() => setPresetEditorOpen(false)}
              >
                <X />
              </AppControlButton>
            </AppControlMorph>
          </div>
        ) : (
          <div className="relative flex min-w-0 items-center">
            <MorphingActionSlot visible={gymEquipment.length > 0}>
              <AppControlButton
                aria-label="Clear equipment selection"
                onClick={() => {
                  triggerHaptic("selection")
                  setGymEquipment([])
                }}
              >
                <X />
              </AppControlButton>
            </MorphingActionSlot>
            {/* Describing a stack is a different job from saying which ones
                you have, so it is a page of its own — reached from the band
                that already holds this page's actions. */}
            <AppControlMorph className="mr-2.5" role="load-steps">
              <AppControlButton
                aria-label="Set load steps"
                disabled={loadEquipment.length === 0}
                onClick={() => {
                  triggerHaptic("light")
                  onOpenLoadSteps()
                }}
              >
                <Weight />
              </AppControlButton>
            </AppControlMorph>
            <AppControlMorph className="mr-2.5" role="preset">
              <AppControlButton
                aria-expanded={presetEditorOpen}
                aria-label="Create equipment preset"
                disabled={gymEquipment.length === 0}
                onClick={() => setPresetEditorOpen(true)}
              >
                <Plus />
              </AppControlButton>
            </AppControlMorph>
            <AppControlMorph className="app-command-fill" role="primary">
              <Button
                aria-label="Done choosing equipment"
                className="w-full"
                onClick={onBack}
                size="cta"
              >
                Done
              </Button>
            </AppControlMorph>
          </div>
        )}
      </AppControls>
    </AppScreen>
  )
}

/** Load steps, on a page of their own.
 *
 * The equipment page is a grid of pictures to tap, answered in seconds;
 * describing what one machine's stack actually offers is a different question
 * asked of one thing at a time, and it was sitting underneath a grid nobody
 * scrolls past. Here it gets the deck the goal is picked from, and the dial
 * gets the room it wants. */
export function EquipmentLoadPage({ onBack }: { onBack: () => void }) {
  return (
    <AppScreen bottomControls>
      <AppSurface>
        <AppShellHeader
          left={
            <AppHeaderButton aria-label="Back" onClick={onBack}>
              <ChevronLeft />
            </AppHeaderButton>
          }
          subtitle="The next weight your equipment actually offers"
          title="Load steps"
        />
        <section
          aria-label="Load steps"
          className="app-scroll-region flex min-h-0 flex-1 flex-col overflow-y-auto px-(--app-content-inset) pt-5 pb-14"
          tabIndex={-1}
        >
          {/* Centred the way the one-question steps are: the deck and the dial
              are the whole page, and they read better in the middle of it. */}
          <div className="m-auto w-full">
            <EquipmentLoadSettings />
          </div>
        </section>
      </AppSurface>

      <AppControls transitionKey="load-steps">
        <AppControlMorph className="app-command-fill" role="primary">
          <Button
            aria-label="Done with load steps"
            className="w-full"
            onClick={onBack}
            size="cta"
          >
            Done
          </Button>
        </AppControlMorph>
      </AppControls>
    </AppScreen>
  )
}

/** The same body map as the exercise picker, asking a different question: not
 *  what to train today, but what a generated week should keep coming back to. */
export function MusclePrioritiesPage({ onBack }: { onBack: () => void }) {
  // The page holds which way the figure is facing, because the button that
  // turns it lives down in the command band with the page's other actions.
  const [side, setSide] = useState<BodySide>("front")
  const priorities = useTrainingProfile(
    (state) => state.profile.priorityMuscles
  )
  const clearMusclePriorities = useTrainingProfile(
    (state) => state.clearMusclePriorities
  )

  return (
    <AppScreen bottomControls>
      <AppSurface>
        <AppShellHeader
          left={
            <AppHeaderButton aria-label="Back" onClick={onBack}>
              <ChevronLeft />
            </AppHeaderButton>
          }
          subtitle={
            priorities.length > 0
              ? `${countLabel(priorities.length, "muscle")} · tap to change`
              : "Tap a muscle to prioritise it"
          }
          title="Priority muscles"
        />
        <section
          aria-label="Priority muscles"
          className="flex min-h-0 flex-1 flex-col px-[clamp(0.75rem,4vw,1rem)] pt-[calc(4.25rem+env(safe-area-inset-top)+0.75rem)] pb-[clamp(0.75rem,2vh,1.25rem)]"
        >
          <MusclePriorityPicker onSideChange={setSide} side={side} />
        </section>
      </AppSurface>

      <AppControls transitionKey={`priorities:${priorities.length > 0}`}>
        <div className="relative flex min-w-0 items-center">
          <MorphingActionSlot visible={priorities.length > 0}>
            <AppControlButton
              aria-label="Clear priority muscles"
              onClick={() => {
                triggerHaptic("selection")
                clearMusclePriorities()
              }}
            >
              <X />
            </AppControlButton>
          </MorphingActionSlot>
          {/* Turning the figure is an action like the other two, so it sits
              with them rather than floating over the map it turns. */}
          <AppControlMorph className="mr-2.5" role="flip">
            <AppControlButton
              aria-label={`Show ${side === "front" ? "back" : "front"}`}
              onClick={() => {
                triggerHaptic("selection")
                setSide(side === "front" ? "back" : "front")
              }}
            >
              <FlipHorizontal2 />
            </AppControlButton>
          </AppControlMorph>
          <AppControlMorph className="app-command-fill" role="primary">
            <Button
              aria-label="Done choosing priority muscles"
              className="w-full"
              onClick={onBack}
              size="cta"
            >
              Done
            </Button>
          </AppControlMorph>
        </div>
      </AppControls>
    </AppScreen>
  )
}

/** Setup asks the same questions as the Settings groups, in the same order and
 *  on the same screens — there is no separate first-run product to learn. */
const SETUP_STEPS = [...PROFILE_STEPS, ...TRAINING_STEPS, GYM_STEP]

export function OnboardingPage({ onFinish }: { onFinish: () => void }) {
  const completeOnboarding = useTrainingProfile(
    (state) => state.completeOnboarding
  )

  const finish = (haptic: "success" | "light") => {
    triggerHaptic(haptic)
    completeOnboarding()
    onFinish()
  }

  return (
    <ProfileStepFlow
      finishAriaLabel="Finish setup"
      finishLabel="Start training"
      name="setup"
      onFinish={() => finish("success")}
      onSkip={() => finish("light")}
      steps={SETUP_STEPS}
    />
  )
}
