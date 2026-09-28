import SwiftUI

/// The player's clock, between the exercise and its sets: the rest running
/// down in large numerals with a bar draining under it, or, between rests, how
/// long the current set has been going.
struct PlayerTimerStrip: View {
    private let store = AppStore.shared
    /// The rest this exercise prescribes, which the bar drains from.
    let restSeconds: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let session = store.activeWorkout.session
            let restUntil = session?.restUntil.map { Date(epochMillis: $0) }
            let remaining = restUntil.map { $0.timeIntervalSince(context.date) } ?? -1
            let resting = remaining > 0
            let anchor = session.map {
                Date(epochMillis: $0.setPhaseStartedAt ?? $0.startedAt)
            } ?? context.date
            let seconds = resting
                ? Int(remaining.rounded(.up))
                : max(0, Int(context.date.timeIntervalSince(anchor).rounded(.down)))
            let fraction = resting && restSeconds > 0 ? min(1, remaining / restSeconds) : 0

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 12) {
                    Text(resting ? "REST" : "SET")
                        .font(Theme.sans(12, weight: .black))
                        .kerning(1.6)
                        .foregroundStyle(resting ? Theme.primary : Theme.mutedForeground)
                        .frame(width: 44, alignment: .leading)
                    Text(WorkoutClock.format(seconds))
                        .font(Theme.readout(40))
                        .foregroundStyle(Theme.foreground)
                        .contentTransition(.numericText(countsDown: resting))
                        .animation(.snappy(duration: 0.25), value: seconds)
                    Spacer(minLength: 0)
                    Text(resting ? "of \(WorkoutClock.format(Int(restSeconds)))" : "on this set")
                        .font(Theme.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                }
                // The bar keeps its room between rests, so the page never
                // moves when one begins.
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.foreground.opacity(0.08))
                        Capsule()
                            .fill(Theme.primary)
                            .frame(width: proxy.size.width * fraction)
                            .animation(.linear(duration: 0.25), value: fraction)
                    }
                }
                .frame(height: 3)
                .opacity(resting ? 1 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background {
                GradientCard(radius: Theme.Radius.xl2, accent: resting ? Theme.primary : Theme.gold, strength: resting ? 0.8 : 0.4)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(resting ? "Rest" : "Current set")
            .accessibilityValue(WorkoutClock.spoken(seconds))
        }
    }
}

/// The last seconds of a countdown, in numerals big enough to read from across
/// the room: they take over the space they are laid over, one number at a
/// time, and say "Go" as the time runs out.
struct FinalCountdown: View {
    /// When the countdown ends. Nil, or long past, shows nothing.
    let until: Date?
    /// How many seconds before the end the numbers take over.
    var window: TimeInterval = 5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let remaining = until.map { $0.timeIntervalSince(context.date) } ?? -10
            let second = Int(remaining.rounded(.up))
            let counting = remaining > 0 && remaining <= window
            let going = remaining <= 0 && remaining > -1

            ZStack {
                if counting || going {
                    RoundedRectangle(cornerRadius: Theme.Radius.xl3, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.xl3, style: .continuous)
                                .fill(Theme.background.opacity(0.45))
                        }
                        .transition(.opacity)

                    Group {
                        if going {
                            Text("GO")
                                .font(Theme.readout(150))
                                .foregroundStyle(Theme.primary)
                        } else {
                            Text("\(second)")
                                .font(Theme.readout(230))
                                .foregroundStyle(second <= 3 ? Theme.primary : Theme.foreground)
                        }
                    }
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .id(going ? -1 : second)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .scale(scale: 1.35).combined(with: .opacity),
                                removal: .scale(scale: 0.8).combined(with: .opacity)
                            )
                    )
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: going ? -1 : (counting ? second : 99))
            .accessibilityHidden(true)
        }
        .allowsHitTesting(false)
    }
}

/// Minutes and seconds the way every workout clock shows them.
enum WorkoutClock {
    static func format(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return "\(value / 60):\(String(format: "%02d", value % 60))"
    }

    static func spoken(_ seconds: Int) -> String {
        let value = max(0, seconds)
        let minutes = value / 60
        let rest = value % 60
        if minutes == 0 { return "\(rest) seconds" }
        return rest == 0 ? "\(minutes) minutes" : "\(minutes) minutes \(rest) seconds"
    }
}
