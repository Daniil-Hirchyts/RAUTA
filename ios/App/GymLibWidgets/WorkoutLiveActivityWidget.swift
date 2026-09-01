import ActivityKit
import SwiftUI
import WidgetKit

/// The Lock Screen card and the Dynamic Island presentations of a workout in
/// progress. Everything rendered here comes from the activity's content state,
/// which the app pushes only when a frame would actually change — the timer is
/// the exception, and counts on its own from a date.
@available(iOS 16.2, *)
struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenCard(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color(WorkoutActivityPalette.background))
                .activitySystemActionForegroundColor(Color(WorkoutActivityPalette.accent))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExerciseFrame(name: context.state.exerciseFrame, side: 58)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    MuscleMapFrame(
                        name: context.state.muscleMapFrame,
                        width: 40,
                        height: 58
                    )
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        WorkoutTimerText(state: context.state)
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(Color(WorkoutActivityPalette.text))
                        Text(context.state.exerciseName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(WorkoutActivityPalette.mutedText))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        ProgressDots(state: context.state)
                        Text(context.state.progressText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(WorkoutActivityPalette.mutedText))
                        Spacer(minLength: 8)
                        StatusLabel(state: context.state)
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                Text(context.state.exerciseName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(WorkoutActivityPalette.accent))
                    .lineLimit(1)
                    .frame(maxWidth: 66, alignment: .leading)
            } compactTrailing: {
                WorkoutTimerText(state: context.state)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(WorkoutActivityPalette.text))
                    .frame(maxWidth: 52, alignment: .trailing)
            } minimal: {
                HStack(spacing: 2) {
                    WorkoutGlyph(isPaused: context.state.isPaused)
                        .font(.system(size: 10, weight: .bold))
                    WorkoutTimerText(state: context.state)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color(WorkoutActivityPalette.accent))
            }
            .keylineTint(Color(WorkoutActivityPalette.accent))
        }
    }
}

/// "Paused" or "Complete" — the only two things about the session that the
/// timer and the progress dots do not already say. What comes *after* this
/// exercise is deliberately absent: the card is for the set being performed
/// right now, and reading ahead is what the app is for.
@available(iOS 16.1, *)
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
            .foregroundStyle(Color(WorkoutActivityPalette.accent))
    }
}

/// Three columns across one row: the exercise on the left, the clock filling
/// the middle, and the muscles being worked on the right. The Lock Screen is
/// read at arm's length mid-set, so the timer is sized to be the thing the eye
/// lands on and everything else is arranged around it.
@available(iOS 16.1, *)
private struct LockScreenCard: View {
    var attributes: WorkoutActivityAttributes
    var state: WorkoutActivityAttributes.ContentState

    private static let panel: CGFloat = 84

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(attributes.workoutDate)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(Color(WorkoutActivityPalette.accent))
                    .lineLimit(1)
                Spacer(minLength: 8)
                StatusLabel(state: state)
            }

            HStack(alignment: .center, spacing: 10) {
                ExerciseFrame(name: state.exerciseFrame, side: Self.panel)

                VStack(alignment: .leading, spacing: 2) {
                    WorkoutTimerText(state: state)
                        .font(.system(size: 42, weight: .heavy))
                        .foregroundStyle(Color(WorkoutActivityPalette.text))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(state.exerciseName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(WorkoutActivityPalette.text))
                        .lineLimit(2)

                    Spacer(minLength: 2)

                    HStack(spacing: 7) {
                        ProgressDots(state: state)
                        Text(state.progressText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(WorkoutActivityPalette.mutedText))
                            .lineLimit(1)
                    }
                }
                .frame(height: Self.panel)

                MuscleMapFrame(
                    name: state.muscleMapFrame,
                    width: 52,
                    height: Self.panel
                )
            }
        }
        .padding(14)
    }
}
