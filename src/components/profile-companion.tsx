import { Rauta, type RautaMood } from "./rauta"
import { useTrainingProfile } from "@/store/use-training-profile"
import { EXPERIENCE_CHOICES, GOAL_CHOICES } from "@/lib/training-profile"

/** All copy and moods follow explicit profile state. No chat service or inferred answers. */
export function ProfileCompanion({ step }: { step: string }) {
  const profile = useTrainingProfile((state) => state.profile)
  const guidance: Record<string, { mood: RautaMood; text: string }> = {
    "About you": {
      mood: profile.name ? "curious" : "listening",
      text: profile.name
        ? `Good to meet you, ${profile.name}. Age ${profile.age} — adjust the dial if needed.`
        : "I'm RAUTA. Tell me your name, then turn the dial to your age.",
    },
    Experience: {
      mood: "focused",
      text:
        profile.health.status === "healthy"
          ? `${EXPERIENCE_CHOICES[profile.trainingExperience].title}. I’ll use this as your starting point.`
          : "Noted. I will leave the planning to you and stay out of the way.",
    },
    Goal: {
      mood: "happy",
      text: `${GOAL_CHOICES[profile.goal].title}. That's our direction.`,
    },
    "Session length": {
      mood: "calm",
      text: `${profile.preferredSessionDurationMinutes} minutes. I’ll plan around the time you have.`,
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
  // No box of its own: the character is pinned to the foot of the screen, and
  // the step's own content closes up over the space it used to sit in.
  return (
    <Rauta
      mood={current.mood}
      size={94}
      speech={current.text}
      reactionKey={reactionKey}
    />
  )
}
