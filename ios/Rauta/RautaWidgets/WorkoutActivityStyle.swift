import SwiftUI

extension Color {
    init(_ color: WorkoutActivityColor) {
        self.init(red: color.red, green: color.green, blue: color.blue)
    }
}

/// What a workout looks like when there is room for one shape and nothing
/// else. Deliberately not a runner — this is a weights app, and the Island's
/// smallest presentation is the only thing some glances ever see.
struct WorkoutGlyph: View {
    var isPaused: Bool

    var body: some View {
        if isPaused {
            Image(systemName: "pause.fill")
        } else {
            Image(systemName: "dumbbell.fill")
        }
    }
}

/// RAUTA on the card and in the Island, moving, in one loop per phase of the
/// workout: focused through the warm-up, determined through a set, breathing
/// through a rest, calm while paused, proud at the end. A change of phase
/// crossfades from one loop to the next. A soft light of the accent sits
/// behind it, so a near-black character reads on the dark card; in the
/// Island's smallest places a paused workout also wears a pause badge.
struct RautaActivitySprite: View {
    var state: WorkoutActivityAttributes.ContentState
    var resting: Bool
    var size: CGFloat
    /// Whether it moves. The Island's compact and minimal places hold the
    /// phase's pose instead: there is no room in them for a loop to read.
    var animated = true

    private var loop: String {
        if resting { return "recovering" }
        switch state.phase {
        case .done: return "proud"
        case .rest: return "recovering"
        case .paused: return "calm"
        case .warmup: return "focused"
        case .set, nil: return state.isPaused ? "calm" : "determined"
        }
    }

    var body: some View {
        ZStack {
            RautaTimerSprite(
                loop: loop,
                epoch: state.animationEpoch ?? Date(timeIntervalSince1970: 0),
                size: size,
                still: !animated
            )
            .id(loop)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.45), value: loop)
        .background {
            Circle()
                .fill(Color(state.accent).opacity(0.16))
                .blur(radius: size * 0.18)
        }
        .opacity(state.isPaused ? 0.7 : 1)
        .overlay(alignment: .bottomTrailing) {
            if state.isPaused, size < 40 {
                ZStack {
                    Circle().fill(Color(state.accent))
                    Image(systemName: "pause.fill")
                        .font(.system(size: size * 0.2, weight: .black))
                        .foregroundStyle(Color(WorkoutActivityPalette.background))
                }
                .frame(width: size * 0.42, height: size * 0.42)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The workout clock. A running session hands WidgetKit the instant to count
/// from and never touches it again; a paused one shows the frozen reading.
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
                                ? Color(state.accent)
                                : Color(state.accent).opacity(0.22)
                        )
                        .frame(width: index == state.completedCount ? 14 : 7, height: 5)
                }
            }
        }
    }
}
