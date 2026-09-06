import { useState, type ReactNode } from "react"

import { AnimatedCheck } from "@/components/animated-check"
import { BodyMap } from "@/components/body-map"
import { EquipmentGrid } from "@/components/equipment-grid"
import { EquipmentPresets } from "@/components/equipment-presets"
import { DotPattern } from "@/components/ui/dot-pattern"
import { Input } from "@/components/ui/input"
import { RotaryKnob } from "@/components/ui/rotary-knob"
import { triggerHaptic } from "@/lib/haptics"
import {
  EXPERIENCE_CHOICES,
  EXPERIENCE_LEVELS,
  GOAL_CHOICES,
  HEALTH_LIMITATIONS,
  HEALTH_LIMITATION_LABELS,
  PRIORITY_LEVEL_LABELS,
  PRIORITY_PAINT_WEIGHTS,
  PROFILE_AGE,
  SELECTABLE_PRIORITY_LEVELS,
  SESSION_DURATION,
  SUPPORTED_GOALS,
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

export function ChoiceRow({
  checked,
  description,
  onClick,
  role = "radio",
  title,
}: {
  checked: boolean
  description?: string
  onClick: () => void
  role?: "radio" | "checkbox"
  title: string
}) {
  return (
    <button
      aria-checked={checked}
      className={cn(
        "interactive-spring flex w-full items-center gap-3 rounded-2xl border p-3.5 text-left",
        checked
          ? "border-primary/50 bg-[color-mix(in_oklch,var(--card),var(--primary)_10%)]"
          : "border-border bg-card active:bg-muted/80"
      )}
      data-haptics="off"
      onClick={() => {
        triggerHaptic("selection")
        onClick()
      }}
      role={role}
      type="button"
    >
      <span className="min-w-0 flex-1">
        <span className="block text-base font-bold">{title}</span>
        {description ? (
          <span className="mt-0.5 block text-sm leading-snug text-muted-foreground">
            {description}
          </span>
        ) : null}
      </span>
      <AnimatedCheck checked={checked} className="size-7 shrink-0" />
    </button>
  )
}

function ChoiceGroup({
  children,
  label,
  role = "radiogroup",
}: {
  children: ReactNode
  label: string
  role?: "radiogroup" | "group"
}) {
  return (
    <div aria-label={label} className="space-y-2.5" role={role}>
      {children}
    </div>
  )
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
    <Input
      aria-label="Your name"
      autoComplete="given-name"
      enterKeyHint="done"
      maxLength={MAX_PROFILE_NAME_LENGTH}
      onChange={(event) => {
        setDraft(event.target.value)
        updateProfile({ name: event.target.value })
      }}
      placeholder="Name (optional)"
      value={draft}
    />
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
    <ChoiceGroup label="Training experience">
      {EXPERIENCE_LEVELS.map((level) => (
        <ChoiceRow
          checked={experience === level}
          description={EXPERIENCE_CHOICES[level].description}
          key={level}
          onClick={() => updateProfile({ trainingExperience: level })}
          title={EXPERIENCE_CHOICES[level].title}
        />
      ))}
    </ChoiceGroup>
  )
}

export function GoalPicker() {
  const goal = useTrainingProfile((state) => state.profile.goal)
  const updateProfile = useTrainingProfile((state) => state.updateProfile)

  return (
    <ChoiceGroup label="Training goal">
      {SUPPORTED_GOALS.map((option) => (
        <ChoiceRow
          checked={goal === option}
          description={GOAL_CHOICES[option].description}
          key={option}
          onClick={() => updateProfile({ goal: option })}
          title={GOAL_CHOICES[option].title}
        />
      ))}
    </ChoiceGroup>
  )
}

export function HealthPicker() {
  const health = useTrainingProfile((state) => state.profile.health)
  const setHealthy = useTrainingProfile((state) => state.setHealthy)
  const toggleHealthLimitation = useTrainingProfile(
    (state) => state.toggleHealthLimitation
  )
  const reasons = health.status === "unsupported" ? health.reasons : []

  return (
    <div className="space-y-2.5">
      {/* Said before the choice rather than under it: this is the boundary the
          planner works inside, not a footnote about it. */}
      <p className="px-1 text-sm leading-relaxed text-muted-foreground">
        Plans are only built for you while none of these apply. Browsing and
        building your own workouts always works.
      </p>
      <ChoiceRow
        checked={health.status === "healthy"}
        description="Nothing that changes how you should train"
        onClick={setHealthy}
        title="Ready to train"
      />
      <p className="px-1 text-xs font-bold tracking-[0.16em] text-muted-foreground uppercase">
        Or what applies
      </p>
      <ChoiceGroup label="Health limitations" role="group">
        {HEALTH_LIMITATIONS.map((limitation) => (
          <ChoiceRow
            checked={reasons.includes(limitation)}
            key={limitation}
            onClick={() => toggleHealthLimitation(limitation)}
            role="checkbox"
            title={HEALTH_LIMITATION_LABELS[limitation]}
          />
        ))}
      </ChoiceGroup>
    </div>
  )
}

/** The map is the whole control: a tap prioritises a muscle, tapping the same
 *  muscle again walks it through the scale and back off. How much of the week
 *  a muscle is asking for is said in how strongly it is painted, so nothing has
 *  to sit under the figure and push it around. */
export function MusclePriorityPicker({ className }: { className?: string }) {
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
            onToggle={cycleMuscle}
            selectedMuscles={selectedMuscles}
          />
        </div>
      </div>
      <PriorityLegend />
    </div>
  )
}

/** What the shades on the figure mean. Static, one line, and the only place
 *  the level names appear — there is nothing here to press by mistake. */
function PriorityLegend() {
  return (
    <p
      aria-hidden="true"
      className="flex shrink-0 items-center justify-center gap-4 pb-1 text-xs font-bold tracking-[0.16em] text-muted-foreground uppercase"
    >
      {SELECTABLE_PRIORITY_LEVELS.map((level) => (
        <span className="flex items-center gap-1.5" key={level}>
          <span
            className="size-2.5 rounded-full"
            style={{
              background: `color-mix(in oklab, var(--primary) ${PRIORITY_PAINT_WEIGHTS[level] * 100}%, #37373b)`,
            }}
          />
          {PRIORITY_LEVEL_LABELS[level]}
        </span>
      ))}
    </p>
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
