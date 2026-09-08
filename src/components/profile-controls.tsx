import { useState, type KeyboardEvent } from "react"
import { ChevronRight, X } from "lucide-react"

import { AnimatedCheck } from "@/components/animated-check"
import { AppModal } from "@/components/app-modal"
import { BodyMap, type BodySide } from "@/components/body-map"
import { EquipmentGrid } from "@/components/equipment-grid"
import { EquipmentPresets } from "@/components/equipment-presets"
import { Button } from "@/components/ui/button"
import { CoverflowCarousel } from "@/components/ui/coverflow-carousel"
import { DotPattern } from "@/components/ui/dot-pattern"
import { RotaryKnob } from "@/components/ui/rotary-knob"
import { triggerHaptic } from "@/lib/haptics"
import { countLabel } from "@/lib/text"
import {
  EXPERIENCE_CHOICES,
  EXPERIENCE_LEVELS,
  GOAL_CHOICES,
  HEALTH_LIMITATIONS,
  HEALTH_LIMITATION_LABELS,
  PRIORITY_LEVEL_LABELS,
  PRIORITY_PAINT_WEIGHTS,
  PROFILE_AGE,
  PROFILE_AGE_SCALE,
  SELECTABLE_PRIORITY_LEVELS,
  SESSION_DURATION,
  SESSION_DURATION_SCALE,
  SUPPORTED_GOALS,
  type SupportedTrainingGoal,
} from "@/lib/training-profile"
import { cn } from "@/lib/utils"
import { useFilters } from "@/store/use-filters"
import {
  MAX_PROFILE_NAME_LENGTH,
  useTrainingProfile,
} from "@/store/use-training-profile"
import type { MuscleId } from "@/types"

/**
 * The controls the training profile is edited with, shared by first-run setup
 * and by Settings. Each one reads and writes the profile store directly, so
 * the two surfaces are two ways into the same value rather than two copies of
 * it.
 */

function moveRadio(event: KeyboardEvent<HTMLDivElement>) {
  const delta = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[
    event.key
  ]
  if (delta === undefined) return
  const choices = [
    ...event.currentTarget.querySelectorAll<HTMLButtonElement>(
      '[role="radio"]'
    ),
  ]
  const current = choices.indexOf(document.activeElement as HTMLButtonElement)
  if (current < 0) return
  event.preventDefault()
  const next = choices[(current + delta + choices.length) % choices.length]
  next.focus()
  next.click()
}

export function ProfileNameField() {
  const storedName = useTrainingProfile((state) => state.profile.name)
  const updateProfile = useTrainingProfile((state) => state.updateProfile)
  // The field keeps its own copy while it is being typed: what is stored is
  // trimmed, and a controlled input reading that back could never hold the
  // space in "Alex Smith" long enough to type the rest of it.
  const [draft, setDraft] = useState(storedName)
  const [seen, setSeen] = useState(storedName)
  if (seen !== storedName) {
    setSeen(storedName)
    // Only when the profile changed somewhere else — an import, a cloud copy.
    if (storedName !== draft.trim()) setDraft(storedName)
  }

  return (
    <div className="group relative w-full">
      <input
        aria-label="Your name"
        autoComplete="given-name"
        className="w-full bg-transparent pb-3 text-center font-heading text-[2.25rem] leading-tight font-black tracking-[-0.03em] caret-primary outline-none placeholder:font-black placeholder:text-muted-foreground/30"
        enterKeyHint="done"
        maxLength={MAX_PROFILE_NAME_LENGTH}
        onChange={(event) => {
          setDraft(event.target.value)
          updateProfile({ name: event.target.value })
        }}
        onKeyDown={(event) => {
          if (event.key === "Enter") {
            event.currentTarget.blur()
          }
        }}
        placeholder="Your name"
        value={draft}
      />
      {/* A rail rather than a box: it lights along its whole length on focus,
          and stays lit once the field has something in it. */}
      <span className="absolute inset-x-0 bottom-0 h-px rounded-full bg-border" />
      <span
        className={cn(
          "absolute inset-x-0 bottom-0 h-[3px] origin-center rounded-full bg-primary-gradient transition-transform duration-500 ease-out group-focus-within:scale-x-100",
          draft.trim() === "" ? "scale-x-0" : "scale-x-100"
        )}
      />
      {draft !== "" && (
        <button
          aria-label="Clear name"
          className="interactive-spring hit-target absolute right-0 bottom-4 grid size-8 place-items-center rounded-full border border-border bg-card text-muted-foreground active:bg-card/90"
          data-haptics="off"
          onClick={() => {
            triggerHaptic("selection")
            setDraft("")
            updateProfile({ name: "" })
          }}
          type="button"
        >
          <X className="size-4" />
        </button>
      )}
    </div>
  )
}

export function AgeKnob({ label = "Age" }: { label?: string | null }) {
  const age = useTrainingProfile((state) => state.profile.age)
  const updateProfile = useTrainingProfile((state) => state.updateProfile)

  return (
    <RotaryKnob
      ariaLabel="Age"
      label={label ?? undefined}
      max={PROFILE_AGE.max}
      min={PROFILE_AGE.min}
      onChange={(value) => updateProfile({ age: value })}
      scaleMax={PROFILE_AGE_SCALE.max}
      scaleMin={PROFILE_AGE_SCALE.min}
      step={PROFILE_AGE.step}
      unit="years"
      value={age}
    />
  )
}

export function SessionDurationKnob({
  label = "Session length",
}: {
  label?: string | null
}) {
  const minutes = useTrainingProfile(
    (state) => state.profile.preferredSessionDurationMinutes
  )
  const updateProfile = useTrainingProfile((state) => state.updateProfile)

  return (
    <RotaryKnob
      ariaLabel="Preferred session duration"
      label={label ?? undefined}
      max={SESSION_DURATION.max}
      min={SESSION_DURATION.min}
      onChange={(value) =>
        updateProfile({ preferredSessionDurationMinutes: value })
      }
      scaleMax={SESSION_DURATION_SCALE.max}
      scaleMin={SESSION_DURATION_SCALE.min}
      step={SESSION_DURATION.step}
      unit="minutes"
      value={minutes}
    />
  )
}

export function ExperiencePicker() {
  const experience = useTrainingProfile(
    (state) => state.profile.trainingExperience
  )
  const updateProfile = useTrainingProfile((state) => state.updateProfile)

  return (
    <div
      role="radiogroup"
      onKeyDown={moveRadio}
      aria-label="Training experience"
      className="space-y-2.5"
    >
      {EXPERIENCE_LEVELS.map((level, index) => (
        <button
          type="button"
          role="radio"
          aria-checked={experience === level}
          tabIndex={experience === level ? 0 : -1}
          key={level}
          data-haptics="off"
          className={cn(
            "interactive-spring flex w-full items-center gap-4 rounded-3xl border p-4 text-left transition-colors",
            experience === level
              ? "border-primary/60 bg-primary/10"
              : "border-border bg-card"
          )}
          onClick={() => {
            triggerHaptic("selection")
            updateProfile({ trainingExperience: level })
          }}
        >
          <span
            className="flex shrink-0 items-end gap-1 px-1"
            aria-hidden="true"
          >
            {[0, 1, 2].map((bar) => (
              <span
                key={bar}
                className={cn(
                  "w-1.5 rounded-full",
                  bar <= index ? "bg-primary" : "bg-foreground/20"
                )}
                style={{ height: 9 + bar * 7 }}
              />
            ))}
          </span>
          <span className="min-w-0 flex-1">
            <strong className="block text-base">
              {EXPERIENCE_CHOICES[level].title}
            </strong>
            <span className="mt-0.5 block text-[13px] leading-snug text-muted-foreground">
              {EXPERIENCE_CHOICES[level].description}
            </span>
          </span>
          <AnimatedCheck
            checked={experience === level}
            className="size-6 shrink-0"
          />
        </button>
      ))}
    </div>
  )
}

/** Goal artwork is deliberately separate from RAUTA: the card communicates
 *  the training direction at a glance, while the mascot remains the companion
 *  that guides the flow. All six assets share the same transparent visual
 *  treatment and live with the rest of the app's public artwork. */
const GOAL_ART: Record<SupportedTrainingGoal, string> = {
  hypertrophy: "/assets/goals/hypertrophy.webp",
  strength: "/assets/goals/strength.webp",
  strength_hypertrophy: "/assets/goals/strength-hypertrophy.webp",
  general_fitness: "/assets/goals/general-fitness.webp",
  fat_loss_support: "/assets/goals/fat-loss-support.webp",
  muscular_endurance: "/assets/goals/muscular-endurance.webp",
}

function GoalArt({ goal }: { goal: SupportedTrainingGoal }) {
  return (
    <span className="absolute inset-0 bg-muted">
      <span className="absolute inset-0 bg-[radial-gradient(circle_at_68%_78%,color-mix(in_oklch,var(--primary)_34%,transparent),transparent_58%)]" />
      <img
        alt=""
        aria-hidden="true"
        className="absolute inset-0 h-full w-full object-contain p-1.5 transition-transform duration-300"
        draggable={false}
        src={GOAL_ART[goal]}
      />
    </span>
  )
}

/** The goal is the one answer in setup that is a direction rather than a
 *  number, so it is asked for as a deck of pictures turned one at a time: the
 *  card facing you is the goal, and there is nothing to confirm. */
export function GoalPicker() {
  const goal = useTrainingProfile((state) => state.profile.goal)
  const updateProfile = useTrainingProfile((state) => state.updateProfile)

  return (
    <CoverflowCarousel
      // Full width of the screen rather than of the content column: the deck
      // is meant to run off both edges.
      className="-mx-(--app-content-inset)"
      label="Training goal"
      onChange={(next) => updateProfile({ goal: next })}
      slides={SUPPORTED_GOALS.map((option) => ({
        description: GOAL_CHOICES[option].description,
        id: option,
        media: <GoalArt goal={option} />,
        title: GOAL_CHOICES[option].title,
      }))}
      value={goal}
    />
  )
}

/** One list, not a card apiece.
 *
 * These are five lines of the same question, and boxing each of them turns a
 * short answer into a page of scenery. The first line is the answer almost
 * everyone gives; ticking any of the others is what takes it away. */
function HealthOptions() {
  const health = useTrainingProfile((state) => state.profile.health)
  const setHealthy = useTrainingProfile((state) => state.setHealthy)
  const toggleHealthLimitation = useTrainingProfile(
    (state) => state.toggleHealthLimitation
  )
  const reasons = health.status === "unsupported" ? health.reasons : []

  return (
    <div
      aria-label="Health"
      className="divide-y divide-border overflow-hidden rounded-2xl border border-border bg-card"
      role="group"
    >
      <HealthOption
        checked={health.status === "healthy"}
        onClick={setHealthy}
        role="radio"
        title="Nothing to train around"
      />
      {HEALTH_LIMITATIONS.map((limitation) => (
        <HealthOption
          checked={reasons.includes(limitation)}
          key={limitation}
          onClick={() => toggleHealthLimitation(limitation)}
          role="checkbox"
          title={HEALTH_LIMITATION_LABELS[limitation]}
        />
      ))}
    </div>
  )
}

function HealthOption({
  checked,
  onClick,
  role,
  title,
}: {
  checked: boolean
  onClick: () => void
  role: "radio" | "checkbox"
  title: string
}) {
  return (
    <button
      aria-checked={checked}
      className="flex w-full items-center gap-3 px-3.5 py-3 text-left active:bg-muted/60"
      data-haptics="off"
      onClick={() => {
        triggerHaptic("selection")
        onClick()
      }}
      role={role}
      type="button"
    >
      <span
        className={cn(
          "min-w-0 flex-1 text-[15px]",
          checked ? "font-bold" : "text-muted-foreground"
        )}
      >
        {title}
      </span>
      <AnimatedCheck checked={checked} className="size-6 shrink-0" />
    </button>
  )
}

/** The question on its own, for the screen that asks nothing else. */
export function HealthPicker() {
  return (
    <div className="space-y-3">
      {/* Said before the choice rather than under it: this is the boundary the
          planner works inside, not a footnote about it. */}
      <p className="px-1 text-sm leading-relaxed text-muted-foreground">
        Plans are only built for you while none of these apply. Browsing and
        building your own workouts always works.
      </p>
      <HealthOptions />
    </div>
  )
}

/** Health folded into the answer above it.
 *
 * For almost everyone the answer is "nothing that changes how I train", and a
 * whole screen to say so is a screen spent on nothing — so it rides along with
 * experience as one row that states the answer it already has. The question
 * itself is a dialog rather than a panel that unfolds: the step is meant to
 * fit the screen, and pushing everything under it down the page to ask an
 * optional question is what a dialog exists to avoid.
 *
 * It deliberately is not a card. Under three cards that are the question on
 * this screen, a fourth box reads as a fourth thing to pick — so the row drops
 * to a line of type with the answer set against a rule, which is a footnote to
 * the choice above it rather than one more option in it. */
export function HealthDisclosure() {
  const health = useTrainingProfile((state) => state.profile.health)
  const limited = health.status === "unsupported"
  const [open, setOpen] = useState(false)
  const close = () => setOpen(false)

  return (
    <>
      <button
        aria-expanded={open}
        aria-haspopup="dialog"
        className="interactive-spring flex w-full items-center gap-3 px-1 py-1 text-left"
        data-haptics="off"
        onClick={() => {
          triggerHaptic("light")
          setOpen(true)
        }}
        type="button"
      >
        <span className="shrink-0 text-sm font-semibold text-muted-foreground">
          Health
        </span>
        <span aria-hidden="true" className="h-px min-w-4 flex-1 bg-border" />
        <span
          className={cn(
            "max-w-[60%] truncate text-sm font-semibold",
            limited ? "text-primary" : "text-foreground"
          )}
        >
          {limited
            ? countLabel(health.reasons.length, "limitation")
            : "Nothing to train around"}
        </span>
        <ChevronRight
          className={cn(
            "size-4 shrink-0",
            limited ? "text-primary" : "text-muted-foreground"
          )}
        />
      </button>

      <AppModal label="Health" onClose={close} open={open}>
        <div className="px-3 pt-3 pb-1 text-center">
          <h2 className="font-heading text-lg font-black tracking-[-0.02em]">
            Anything to train around?
          </h2>
          <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
            Plans are only built for you while none of these apply. Browsing and
            building your own workouts always works.
          </p>
        </div>
        <div className="mt-4">
          <HealthOptions />
        </div>
        <Button className="mt-2 w-full" onClick={close}>
          Done
        </Button>
      </AppModal>
    </>
  )
}

/** The map is the whole control: a tap prioritises a muscle, tapping the same
 *  muscle again walks it through the scale and back off. How much of the week
 *  a muscle is asking for is said in how strongly it is painted, so nothing has
 *  to sit under the figure and push it around. */
export function MusclePriorityPicker({
  className,
  onSideChange,
  side,
}: {
  className?: string
  /** The figure is turned from the command band, where the rest of this
   *  screen's actions already are — nothing floats over the map. */
  onSideChange?: (side: BodySide) => void
  side?: BodySide
}) {
  const priorities = useTrainingProfile(
    (state) => state.profile.priorityMuscles
  )
  const cycleMusclePriority = useTrainingProfile(
    (state) => state.cycleMusclePriority
  )
  const selectedMuscles = priorities.map((entry) => entry.muscleId)
  const intensity = Math.min(selectedMuscles.length / 6, 1)
  const muscleWeights = Object.fromEntries(
    priorities.map((entry) => [
      entry.muscleId,
      PRIORITY_PAINT_WEIGHTS[entry.level],
    ])
  )

  const cycleMuscle = (muscle: MuscleId) => {
    cycleMusclePriority(muscle)
    const level = useTrainingProfile
      .getState()
      .profile.priorityMuscles.find((entry) => entry.muscleId === muscle)?.level
    // The tap that hands a muscle back to the engine's normal weighting is a
    // smaller event than the ones that pick a level.
    triggerHaptic(level ? "selection" : "light")
  }

  return (
    <div className={cn("flex min-h-0 flex-1 flex-col", className)}>
      <div className="relative min-h-0 flex-1">
        <DotPattern
          className="[mask-image:radial-gradient(ellipse_at_center,black_28%,transparent_80%)] transition-[fill,fill-opacity] duration-500"
          cr={1.1}
          cx={9}
          cy={9}
          height={18}
          style={{
            fill: `color-mix(in oklch, var(--muted-foreground), var(--primary) ${25 + intensity * 50}%)`,
            fillOpacity: 0.36 + intensity * 0.28,
          }}
          width={18}
        />
        <div className="relative z-10 h-full">
          <BodyMap
            muscleWeights={muscleWeights}
            onSideChange={onSideChange}
            onToggle={cycleMuscle}
            selectedMuscles={selectedMuscles}
            showFlipButton={false}
            side={side}
          />
        </div>
      </div>
      <PriorityLegend />
    </div>
  )
}

/** The resting fill of a muscle nobody has asked for, taken from
 *  `.muscle-region`: the palest end of the scale is the figure's own grey, not
 *  a washed-out orange. */
const RESTING_FILL = "#37373b"

/** The same mix the figure paints itself with, so the bar below it is a
 *  sample of the map rather than a picture of one. */
function priorityPaint(weight: number) {
  return `color-mix(in oklab, var(--primary) ${weight * 100}%, ${RESTING_FILL})`
}

/** What the shades on the figure mean, drawn as the scale itself: one bar
 *  running from the grey every muscle rests at, through the two levels a tap
 *  can ask for. It reads the way a key reads — from nothing to most — even
 *  though a tap walks it the other way, and it is graded rather than blocked
 *  out because the eye compares a muscle against the whole range, not against
 *  a swatch. There is nothing here to press by mistake. */
function PriorityLegend() {
  const stops = [
    // A muscle nobody has asked for is not painted at all, so this end of the
    // scale is the resting fill itself rather than the palest paint.
    { label: PRIORITY_LEVEL_LABELS.normal, weight: 0 },
    ...[...SELECTABLE_PRIORITY_LEVELS].reverse().map((level) => ({
      label: PRIORITY_LEVEL_LABELS[level],
      weight: PRIORITY_PAINT_WEIGHTS[level],
    })),
  ]

  return (
    <div aria-hidden="true" className="mx-auto w-full max-w-64 shrink-0 pb-1">
      <div
        className="h-2.5 rounded-full shadow-[inset_0_0_0_1px_color-mix(in_oklab,white_10%,transparent)]"
        style={{
          background: `linear-gradient(90deg, ${stops
            .map(
              (stop, index) =>
                `${priorityPaint(stop.weight)} ${((index / (stops.length - 1)) * 100).toFixed(1)}%`
            )
            .join(", ")})`,
        }}
      />
      <p className="mt-1.5 flex justify-between text-[10px] font-bold tracking-[0.16em] text-muted-foreground uppercase">
        {stops.map((stop) => (
          <span key={stop.label}>{stop.label}</span>
        ))}
      </p>
    </div>
  )
}

/** The equipment you have, picked with the same grid and the same presets the
 *  exercise browser uses. */
export function ProfileEquipmentPicker() {
  const gymEquipment = useFilters((state) => state.gymEquipment)
  const toggleGymEquipment = useFilters((state) => state.toggleGymEquipment)

  return <EquipmentGrid onToggle={toggleGymEquipment} selected={gymEquipment} />
}

export function ProfileEquipmentPresets({ className }: { className?: string }) {
  const gymEquipment = useFilters((state) => state.gymEquipment)
  const setGymEquipment = useFilters((state) => state.setGymEquipment)

  return (
    <EquipmentPresets
      className={className}
      onChange={setGymEquipment}
      value={gymEquipment}
    />
  )
}
