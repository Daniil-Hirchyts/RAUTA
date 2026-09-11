import SwiftUI

extension Color {
    init(_ color: WorkoutActivityColor) {
        self.init(red: color.red, green: color.green, blue: color.blue)
    }
}

/// What a workout looks like when there is room for one shape and nothing
/// else. Deliberately not a runner — this is a weights app, and the Island's
/// smallest presentation is the only thing some glances ever see.
@available(iOS 16.1, *)
struct WorkoutGlyph: View {
    var isPaused: Bool

    var body: some View {
        if isPaused {
            Image(systemName: "pause.fill")
        } else if #available(iOS 18.0, *) {
            Image(systemName: "dumbbell.fill")
        } else {
            // `dumbbell.fill` only arrived in iOS 18; below that a flame is
            // the closest symbol that is not a person.
            Image(systemName: "flame.fill")
        }
    }
}

/// The RAUTA mark used by the Dynamic Island. The full Rive runtime belongs in
/// the app; WidgetKit gets a lightweight rendered pose so the Island stays
/// fast and deterministic while still carrying the same character identity.
@available(iOS 16.1, *)
struct RautaActivityMark: View {
    var isPaused: Bool

    var body: some View {
        Image("RautaIsland")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .opacity(isPaused ? 0.68 : 1)
            .shadow(
                color: Color(WorkoutActivityPalette.accent).opacity(isPaused ? 0.08 : 0.18),
                radius: 3
            )
            .overlay(alignment: .bottomTrailing) {
                if isPaused {
                    ZStack {
                        Circle()
                            .fill(Color(WorkoutActivityPalette.accent))
                        Image(systemName: "pause.fill")
                            .font(.system(size: 4.5, weight: .black))
                            .foregroundStyle(Color(WorkoutActivityPalette.background))
                    }
                    .frame(width: 8, height: 8)
                }
            }
            .accessibilityHidden(true)
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
        .lineLimit(1)
        .minimumScaleFactor(0.55)
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
