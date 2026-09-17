import ActivityKit
import SwiftUI
import WidgetKit

/// The Lock Screen card and the Dynamic Island presentations of a workout in
/// progress. Everything rendered here comes from the activity's content state,
/// which the app pushes only when visible workout state changes — the timer is
/// the exception, and counts on its own from a date.
struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenCard(
                workoutDate: context.attributes.workoutDate,
                state: context.state
            )
                .activityBackgroundTint(Color(WorkoutActivityPalette.background))
                .activitySystemActionForegroundColor(Color(context.state.accent))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            RautaActivityMark(isPaused: context.state.isPaused, accent: context.state.accent)
                                .frame(width: 22, height: 22)

                            Text(context.attributes.workoutDate)
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)

                            Spacer(minLength: 6)
                            StatusLabel(state: context.state)
                        }
                        .foregroundStyle(Color(context.state.accent))

                        WorkoutTimerText(state: context.state)
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .tracking(-1.2)
                            .foregroundStyle(Color(WorkoutActivityPalette.text))

                        Text(context.state.exerciseName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(WorkoutActivityPalette.text).opacity(0.82))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        ProgressDots(state: context.state)
                        Spacer(minLength: 8)
                        Text(context.state.progressText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(WorkoutActivityPalette.mutedText))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 1)
                }
            } compactLeading: {
                RautaActivityMark(isPaused: context.state.isPaused, accent: context.state.accent)
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                WorkoutTimerText(state: context.state)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(WorkoutActivityPalette.text))
                    .frame(maxWidth: 56, alignment: .trailing)
            } minimal: {
                RautaActivityMark(isPaused: context.state.isPaused, accent: context.state.accent)
                    .frame(width: 18, height: 18)
            }
            .keylineTint(Color(context.state.accent))
        }
    }
}

/// "Paused" or "Complete" — the only two things about the session that the
/// timer and the progress dots do not already say. What comes *after* this
/// exercise is deliberately absent: the card is for the set being performed
/// right now, and reading ahead is what the app is for.
private struct StatusLabel: View {
    var state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if state.isPaused {
            label("Paused")
        } else if state.isComplete {
            label("Complete")
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Color(state.accent))
    }
}

/// A text-first Lock Screen card. The timer is sized for an arm's-length glance;
/// the current exercise remains beneath it, while artwork stays in the app where
/// it has room to be useful.
private struct LockScreenCard: View {
    var workoutDate: String
    var state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: "calendar.fill")
                    .font(.system(size: 10, weight: .black))
                Text(workoutDate)
                    .lineLimit(1)
                Spacer(minLength: 8)
                StatusLabel(state: state)
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color(state.accent))

            WorkoutTimerText(state: state)
                .font(.system(size: 70, weight: .black, design: .rounded))
                .tracking(-2.2)
                .foregroundStyle(Color(WorkoutActivityPalette.text))
                .frame(maxWidth: .infinity, minHeight: 84, maxHeight: 84, alignment: .leading)
                .layoutPriority(1)

            HStack(spacing: 6) {
                WorkoutGlyph(isPaused: state.isPaused)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color(state.accent))

                Text(state.exerciseName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(WorkoutActivityPalette.text).opacity(0.88))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 7) {
                ProgressDots(state: state)
                Spacer(minLength: 6)
                Text(state.progressText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(WorkoutActivityPalette.mutedText))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 160, alignment: .topLeading)
        .background(
            ZStack {
                ContainerRelativeShape()
                    .fill(Color.white.opacity(0.03))
                LinearGradient(
                    colors: [
                        Color(state.accent).opacity(0.09),
                        Color.clear,
                        Color.white.opacity(0.025)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(ContainerRelativeShape())
            }
        )
        .overlay {
            ContainerRelativeShape()
                .stroke(Color(state.accent).opacity(0.28), lineWidth: 1)
        }
    }
}
