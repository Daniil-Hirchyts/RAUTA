import {
  createDefaultTrainingProfile,
  type PersistedTrainingProfileState,
  type TrainingProfile,
} from "@/store/use-training-profile"

/** Someone who has already been through first-run setup, for the tests that
 *  are about everything after it. */
export function completedOnboardingState(
  profile: Partial<TrainingProfile> = {}
): PersistedTrainingProfileState {
  return {
    profile: { ...createDefaultTrainingProfile(), ...profile },
    onboarding: { completed: true, completedAt: "2026-09-01T12:00:00.000Z" },
  }
}
