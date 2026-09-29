import SwiftUI

/// The player's clock, in its top corner beside RAUTA: the rest running down,
/// or, between rests, how long the current set has been going. Just the
/// numerals and a word over them; RAUTA's ring shows how much rest is left.
struct PlayerCornerTimer: View {
    private let store = AppStore.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
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

            VStack(alignment: .leading, spacing: 1) {
                Text(resting ? "REST" : "SET")
                    .font(Theme.sans(10, weight: .black))
                    .kerning(1.4)
                    .foregroundStyle(resting ? Theme.primary : Theme.mutedForeground)
                Text(WorkoutClock.format(seconds))
                    .font(Theme.readout(30))
                    .foregroundStyle(resting ? Theme.foreground : Theme.foreground.opacity(0.7))
                    .contentTransition(.numericText(countsDown: resting))
                    .animation(.snappy(duration: 0.25), value: seconds)
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(resting ? "Rest" : "Current set")
            .accessibilityValue(WorkoutClock.spoken(seconds))
        }
    }
}

/// The last seconds of a countdown, in numerals big enough to read from across
/// the room, one number at a time, saying "Go" as the time runs out. Just the
/// numerals: whatever they stand in for steps aside while they show.
struct FinalCountdown: View {
    /// How many seconds before the end the numbers take over.
    static let window: TimeInterval = 5
    /// How long "Go" stays after the end.
    static let goHold: TimeInterval = 0.9

    /// When the countdown ends. Nil, or long past, shows nothing.
    let until: Date?
    var window: TimeInterval = FinalCountdown.window

    /// Whether the numbers are showing at `date`: in the last seconds, or
    /// saying "Go" just after.
    static func isShowing(until: Date?, at date: Date = Date(), window: TimeInterval = FinalCountdown.window) -> Bool {
        guard let until else { return false }
        let remaining = until.timeIntervalSince(date)
        return remaining <= window && remaining > -goHold
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let remaining = until.map { $0.timeIntervalSince(context.date) } ?? -10
            let second = Int(remaining.rounded(.up))
            let counting = remaining > 0 && remaining <= window
            let going = remaining <= 0 && remaining > -Self.goHold

            ZStack {
                if counting || going {
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
    /// "1:05", or past an hour "1:02:05" — a set left running overnight
    /// still fits its corner.
    static func format(_ seconds: Int) -> String {
        let value = max(0, seconds)
        guard value >= 3_600 else {
            return "\(value / 60):\(String(format: "%02d", value % 60))"
        }
        return "\(value / 3_600):\(String(format: "%02d", value / 60 % 60)):\(String(format: "%02d", value % 60))"
    }

    static func spoken(_ seconds: Int) -> String {
        let value = max(0, seconds)
        let minutes = value / 60
        let rest = value % 60
        if minutes == 0 { return "\(rest) seconds" }
        return rest == 0 ? "\(minutes) minutes" : "\(minutes) minutes \(rest) seconds"
    }
}
