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
                    ExerciseFrame(name: context.state.exerciseFrame, side: 54)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        WorkoutTimerText(state: context.state)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color(WorkoutActivityPalette.text))
                            .frame(maxWidth: 92, alignment: .trailing)
                        Text(context.state.progressText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(WorkoutActivityPalette.mutedText))
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.exerciseName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(WorkoutActivityPalette.text))
                            .lineLimit(2)
                        if !context.state.exerciseMuscles.isEmpty {
                            Text(context.state.exerciseMuscles)
                                .font(.system(size: 12))
                                .foregroundStyle(Color(WorkoutActivityPalette.mutedText))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        ProgressDots(state: context.state)
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
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
                    .foregroundStyle(Color(WorkoutActivityPalette.accent))
            }
            .keylineTint(Color(WorkoutActivityPalette.accent))
        }
    }
}

/// "Paused", "Complete", or the exercise waiting after this one — whichever
/// tells the glancing user the most.
@available(iOS 16.1, *)
private struct StatusLabel: View {
    var state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if state.isPaused {
            label("Paused", color: WorkoutActivityPalette.accent)
        } else if state.isComplete {
            label("Complete", color: WorkoutActivityPalette.accent)
        } else if !state.nextExerciseName.isEmpty {
            HStack(spacing: 4) {
                Text("Next")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(WorkoutActivityPalette.accent))
                Text(state.nextExerciseName)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(WorkoutActivityPalette.mutedText))
                    .lineLimit(1)
            }
        }
    }

    private func label(_ text: String, color: WorkoutActivityColor) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Color(color))
    }
}

@available(iOS 16.1, *)
private struct LockScreenCard: View {
    var attributes: WorkoutActivityAttributes
    var state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(attributes.workoutName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(WorkoutActivityPalette.accent))
                        .lineLimit(1)
                    Text(attributes.workoutDate)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(WorkoutActivityPalette.mutedText))
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                WorkoutTimerText(state: state)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Color(WorkoutActivityPalette.text))
                    .frame(maxWidth: 118, alignment: .trailing)
            }

            HStack(spacing: 12) {
                ExerciseFrame(name: state.exerciseFrame, side: 60)

                VStack(alignment: .leading, spacing: 3) {
                    Text(state.exerciseName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(WorkoutActivityPalette.text))
                        .lineLimit(2)
                    if !state.exerciseMuscles.isEmpty {
                        Text(state.exerciseMuscles)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(WorkoutActivityPalette.mutedText))
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        ProgressDots(state: state)
                        Text(state.progressText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(WorkoutActivityPalette.mutedText))
                    }
                    .padding(.top, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            StatusLabel(state: state)
        }
        .padding(14)
    }
}
