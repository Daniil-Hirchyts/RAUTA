import ImageIO
import SwiftUI

struct WatchWorkoutView: View {
    @EnvironmentObject private var session: WatchSessionModel
    @EnvironmentObject private var workout: WatchWorkoutManager
    /// Always On: seconds are not shown while the wrist is down.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        Group {
            if let snapshot = session.snapshot {
                activeWorkout(snapshot)
            } else {
                waitingView
            }
        }
        .background(Color.black.ignoresSafeArea())
        // The workout session follows the phone in `WatchWorkoutManager`, not
        // here: a view is not there when the app runs in the background.
        // A logged set is felt as well as seen.
        .sensoryFeedback(.success, trigger: session.confirmedSets)
        .sensoryFeedback(.error, trigger: session.failedSets)
    }

    private func activeWorkout(_ snapshot: RautaWatchWorkoutSnapshot) -> some View {
        TabView {
            overviewPage(snapshot)

            if snapshot.exerciseEntryId != nil {
                setPage(snapshot)
            } else {
                finishedPage
            }
        }
        .tabViewStyle(.verticalPage)
    }

    private func overviewPage(_ snapshot: RautaWatchWorkoutSnapshot) -> some View {
        VStack(spacing: 10) {
            header(snapshot)
            timePanel(snapshot)
            metrics(snapshot)

            if let issue = session.connectionIssue ?? workout.issue {
                Text(issue)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.65))
                .accessibilityLabel("Set controls on next page")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func header(_ snapshot: RautaWatchWorkoutSnapshot) -> some View {
        HStack(spacing: 8) {
            AnimatedRauta()
                .frame(width: 38, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.workoutName.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(WatchPalette.primary)
                    .lineLimit(1)

                Text(snapshot.exerciseName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
    }

    private func timePanel(_ snapshot: RautaWatchWorkoutSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 60 : 1)) { context in
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(duration(session.elapsedSeconds(at: context.date), showsSeconds: !isLuminanceReduced))
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Spacer(minLength: 0)

                if snapshot.isPaused {
                    Text("PAUSED")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(WatchPalette.primary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Heart, energy and where the exercise is up to. No distance: this is a
    /// strength session, and a walking figure next to metres read as a run.
    private func metrics(_ snapshot: RautaWatchWorkoutSnapshot) -> some View {
        HStack(spacing: 8) {
            MetricValue(
                icon: "heart.fill",
                value: workout.heartRate.map { String(Int($0.rounded())) } ?? "--",
                unit: "BPM"
            )
            MetricValue(
                icon: "flame.fill",
                value: String(Int(workout.activeKilocalories.rounded())),
                unit: "KCAL"
            )
            MetricValue(
                icon: "dumbbell.fill",
                value: snapshot.setCount > 0
                    ? "\(Swift.min(snapshot.setIndex, snapshot.setCount))/\(snapshot.setCount)"
                    : "--",
                unit: "SETS"
            )
        }
    }

    private func setPage(_ snapshot: RautaWatchWorkoutSnapshot) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.setCount > 0
                     ? "SET \(Swift.min(snapshot.setIndex, snapshot.setCount)) / \(snapshot.setCount)"
                     : "CURRENT SET")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(snapshot.exerciseName)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            SetAdjuster(
                title: "Load",
                systemImage: "scalemass.fill",
                value: loadText,
                decrementDisabled: session.loadKg <= 0,
                decrement: { session.loadKg = Swift.max(0, session.loadKg - 0.5) },
                increment: { session.loadKg = Swift.min(500, session.loadKg + 0.5) },
                crown: $session.loadKg,
                crownRange: 0...500,
                crownStep: 0.5
            )

            SetAdjuster(
                title: "Reps",
                systemImage: "repeat",
                value: String(session.reps),
                decrementDisabled: session.reps <= 1,
                decrement: { session.reps = Swift.max(1, session.reps - 1) },
                increment: { session.reps = Swift.min(100, session.reps + 1) },
                crown: Binding(
                    get: { Double(session.reps) },
                    set: { session.reps = Int($0.rounded()) }
                ),
                crownRange: 1...100,
                crownStep: 1
            )

            Button {
                session.markSetDone()
            } label: {
                HStack(spacing: 8) {
                    if session.isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(WatchPalette.onPrimary)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                    }

                    Text(session.isSaving ? "Saving…" : "Mark set done")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(WatchPalette.onPrimary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    LinearGradient(
                        colors: [WatchPalette.primaryGradientStart, WatchPalette.primaryGradientEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(session.isSaving)
            .opacity(session.isSaving ? 0.72 : 1)

            if let issue = session.connectionIssue {
                Text(issue)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var finishedPage: some View {
        VStack(spacing: 10) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(WatchPalette.primary)

            Text("Workout complete")
                .font(.headline.weight(.bold))

            Text("Finish and review it on iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
    }

    private var waitingView: some View {
        VStack(spacing: 8) {
            AnimatedRauta()
                .frame(width: 58, height: 66)

            Text("RAUTA")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(WatchPalette.primary)

            Text("Ready for your workout")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Text("Start a workout on iPhone. Rauta will bring the current exercise and set here.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadText: String {
        let rounded = session.loadKg.rounded()
        if abs(session.loadKg - rounded) < 0.001 {
            return "\(Int(rounded)) kg"
        }
        return String(format: "%.1f kg", session.loadKg)
    }

    private func duration(_ seconds: TimeInterval, showsSeconds: Bool) -> String {
        let total = Swift.max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        guard showsSeconds else {
            return hours > 0 ? String(format: "%d:%02d", hours, minutes) : "\(minutes) min"
        }
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%02d:%02d", minutes, secs)
    }

}

private struct MetricValue: View {
    var icon: String
    var value: String
    var unit: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WatchPalette.primary)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(unit)
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
    }
}

private struct SetAdjuster: View {
    var title: String
    var systemImage: String
    var value: String
    var decrementDisabled: Bool
    var decrement: () -> Void
    var increment: () -> Void
    /// The Digital Crown turns the value once it is tapped into focus; until
    /// then the crown keeps paging, as it does everywhere else in the app.
    var crown: Binding<Double>
    var crownRange: ClosedRange<Double>
    var crownStep: Double

    var body: some View {
        HStack(spacing: 9) {
            adjustButton(systemImage: "minus", disabled: decrementDisabled, action: decrement)

            VStack(spacing: 1) {
                Label(title.uppercased(), systemImage: systemImage)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(value)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .focusable()
            .digitalCrownRotation(
                crown,
                from: crownRange.lowerBound,
                through: crownRange.upperBound,
                by: crownStep,
                sensitivity: .low,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: increment()
                case .decrement: if !decrementDisabled { decrement() }
                @unknown default: break
                }
            }

            adjustButton(systemImage: "plus", disabled: false, action: increment)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
    }

    private func adjustButton(systemImage: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white.opacity(disabled ? 0.35 : 0.95))
                .frame(width: 42, height: 42)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(disabled ? 0.05 : 0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(systemImage == "minus" ? "Decrease \(title)" : "Increase \(title)")
    }
}

private struct AnimatedRauta: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Always On: the wrist is down, and a looping float only costs power.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var floating = false

    private var still: Bool { reduceMotion || isLuminanceReduced }

    private static let artwork: CGImage? = {
        guard let url = Bundle.main.url(forResource: "RautaWatch", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()

    var body: some View {
        Group {
            if let artwork = Self.artwork {
                Image(decorative: artwork, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFit()
            }
        }
        .offset(y: still ? 0 : (floating ? -2 : 2))
        .rotationEffect(.degrees(still ? 0 : (floating ? 1.5 : -1.5)))
        .scaleEffect(still ? 1 : (floating ? 1.02 : 0.98))
        // Keyed on `still`, so the loop starts only while it may run and a
        // change of setting replaces it rather than stacking a second one.
        .animation(
            still ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
            value: floating
        )
        .task(id: still) {
            floating = false
            guard !still else { return }
            await Task.yield()
            floating = true
        }
        .accessibilityHidden(true)
    }
}

/// The iPhone app's accent. Read through ``WatchAccentStore``, which SwiftUI
/// observes, so the watch redraws the moment the phone sends a new one.
@MainActor
enum WatchPalette {
    private static var accent: RautaWatchAccent { WatchAccentStore.shared.accent }

    static var primary: Color { Color(watchHex: accent.primary) }
    static var primaryGradientStart: Color { Color(watchHex: accent.gradientStart) }
    static var primaryGradientEnd: Color { Color(watchHex: accent.gradientEnd) }
    /// A label on the accent: white or near-black, whichever reads.
    static var onPrimary: Color { accent.whiteLabel ? .white : Color(watchHex: 0x060606) }
}

private extension Color {
    init(watchHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
