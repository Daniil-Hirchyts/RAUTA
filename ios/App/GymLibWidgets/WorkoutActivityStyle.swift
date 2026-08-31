import SwiftUI
import UIKit

extension Color {
    init(_ color: WorkoutActivityColor) {
        self.init(red: color.red, green: color.green, blue: color.blue)
    }
}

/// The prepared demonstration frame for a content state, already carrying the
/// app's dark treatment and composited onto ``WorkoutActivityPalette.surface``
/// — so it must be drawn on that exact color to look seamless.
@available(iOS 16.1, *)
func exerciseFrameImage(named name: String) -> Image? {
    guard
        let url = WorkoutActivityStore.frameURL(named: name),
        let image = UIImage(contentsOfFile: url.path)
    else { return nil }

    return Image(uiImage: image)
}

/// The demonstration thumbnail, falling back to the app's mark when the frame
/// has not been prepared — an exercise with no art, or no reachable App Group.
@available(iOS 16.1, *)
struct ExerciseFrame: View {
    var name: String
    var side: CGFloat

    var body: some View {
        Group {
            if let image = exerciseFrameImage(named: name) {
                image.resizable().scaledToFit()
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: side * 0.42, weight: .semibold))
                    .foregroundStyle(Color(WorkoutActivityPalette.accent))
            }
        }
        .frame(width: side, height: side)
        .background(Color(WorkoutActivityPalette.surface))
        .clipShape(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous))
    }
}

/// The workout clock. A running session hands WidgetKit the instant to count
/// from and never touches it again; a paused one shows the frozen reading.
@available(iOS 16.1, *)
struct WorkoutTimerText: View {
    var state: WorkoutActivityAttributes.ContentState

    var body: some View {
        Group {
            if let start = state.timerStart, !state.isPaused {
                Text(start, style: .timer)
            } else {
                Text(state.elapsedText)
            }
        }
        .monospacedDigit()
    }
}

/// One dot per exercise, filled as each is completed and outlined while it is
/// the one being performed. Long workouts fall back to the count alone rather
/// than a row of dots too small to read.
@available(iOS 16.1, *)
struct ProgressDots: View {
    var state: WorkoutActivityAttributes.ContentState

    private static let maximumDots = 10

    var body: some View {
        if state.totalCount > 0, state.totalCount <= Self.maximumDots {
            HStack(spacing: 4) {
                ForEach(0..<state.totalCount, id: \.self) { index in
                    Capsule()
                        .fill(
                            index < state.completedCount
                                ? Color(WorkoutActivityPalette.accent)
                                : Color(WorkoutActivityPalette.accent).opacity(0.22)
                        )
                        .frame(width: index == state.completedCount ? 14 : 7, height: 5)
                }
            }
        }
    }
}
