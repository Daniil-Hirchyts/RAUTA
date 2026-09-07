import { useState } from "react"
import { Rauta, type RautaMood } from "./rauta"
import { RautaSpeech } from "./rauta-speech"
import { useTrainingProfile } from "@/store/use-training-profile"
import { GOAL_CHOICES } from "@/lib/training-profile"

/** All copy and moods follow explicit profile state. No chat service or inferred answers. */
export function ProfileCompanion({ step }: { step: string }) {
  const profile = useTrainingProfile((state) => state.profile)
  const [greeted, setGreeted] = useState(false)
  const guidance: Record<string, { mood: RautaMood; text: string }> = {
    "Your name": {
      mood: "listening",
      text: profile.name
        ? `Good to meet you, ${profile.name}.`
        : "I'm RAUTA. Let's make this yours.",
    },
    Age: { mood: "curious", text: "Turn the dial. One notch, one year." },
    Experience: { mood: "focused", text: "Start where you are today." },
    Goal: {
      mood: "happy",
      text: `${GOAL_CHOICES[profile.goal].title}. That's our direction.`,
    },
    "Session length": {
      mood: "calm",
      text: "Choose the time you can make for yourself.",
    },
    "Your gym": {
      mood: "curious",
      text: "Pick the equipment you actually have.",
    },
    Health: {
      mood: "calm",
      text: "Your limits matter. You can always build your own workout.",
    },
  }
  const current = guidance[step] ?? guidance.Goal
  const reactionKey = `${profile.name}:${profile.age}:${profile.trainingExperience}:${profile.goal}:${profile.preferredSessionDurationMinutes}:${profile.health.status}`
  return (
    <div className="mb-6 flex items-center gap-2 px-1">
      <Rauta
        mood={greeted ? "happy" : current.mood}
        size={94}
        reactionKey={reactionKey}
        onActivate={() => setGreeted((value) => !value)}
      />
      <RautaSpeech className="min-w-0 flex-1">
        <p
          className="text-[14px] leading-relaxed text-foreground/90"
          aria-live="polite"
        >
          {greeted
            ? "I'm here. Move me around, then choose what feels right."
            : current.text}
        </p>
      </RautaSpeech>
    </div>
  )
}
