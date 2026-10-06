import SwiftUI

struct WatchWorkoutView: View {
    @Environment(WatchSessionModel.self) private var session
    @Environment(WatchWorkoutManager.self) private var workout
    /// Always On: seconds are not shown while the wrist is down.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    /// A moment of RAUTA being pleased, after a set counts.
    @State private var celebrating = false

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
        .task(id: session.confirmedSets) {
            guard session.confirmedSets > 0 else { return }
            celebrating = true
            try? await Task.sleep(for: .seconds(2.5))
            celebrating = false
        }
    }

    /// What RAUTA is doing: at work through a set, breathing through a rest,
    /// pleased for a moment when a set counts, proud at the end.
    private func mood(_ snapshot: RautaWatchWorkoutSnapshot) -> RautaSprite.Loop {
        if snapshot.exerciseEntryId == nil && snapshot.exerciseId == nil { return .proud }
        if celebrating { return .happy }
        if session.restUntil != nil { return .recovering }
        return .determined
    }

    private func activeWorkout(_ snapshot: RautaWatchWorkoutSnapshot) -> some View {
        TabView {
            nowPage(snapshot)

            if snapshot.exerciseEntryId != nil {
                setPage(snapshot)
            }
        }
        .tabViewStyle(.verticalPage)
    }

    // MARK: Now

    /// Where the workout is up to: the warm-up, the rest, or the set — and
    /// the one control that matters for it.
    private func nowPage(_ snapshot: RautaWatchWorkoutSnapshot) -> some View {
        VStack(spacing: 8) {
            header(snapshot)

            if snapshot.exerciseEntryId == nil && snapshot.exerciseId == nil {
                finished
            } else if let warmupUntil = session.warmupUntil, warmupUntil > Date() {
                countdown(
                    title: "WARM-UP",
                    until: warmupUntil,
                    total: nil,
                    actions: [("Skip", "forward.end.fill", { session.control(.endWarmup) })]
                )
            } else if let restUntil = session.restUntil {
                countdown(
                    title: "REST",
                    until: restUntil,
                    total: snapshot.restSeconds,
                    actions: [
                        ("+30 s", "plus", { session.control(.extendRest, seconds: 30) }),
                        ("Skip", "forward.end.fill", { session.control(.endRest) }),
                    ]
                )
            } else {
                timePanel(snapshot)
                setLine(snapshot)
            }

            if let issue = session.connectionIssue ?? workout.issue {
                Text(issue)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                pauseButton(snapshot)
            }
        }
    }

    private func header(_ snapshot: RautaWatchWorkoutSnapshot) -> some View {
        HStack(spacing: 8) {
            RautaSprite(loop: mood(snapshot))
                .frame(width: 38, height: 38)
                .background(RautaGlow())

            VStack(alignment: .leading, spacing: 1) {
                Text(progressCaption(snapshot))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(WatchPalette.primary)
                    .lineLimit(1)

                Text(snapshot.exerciseName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
    }

    /// "EXERCISE 2 OF 5" when the phone says so; the workout's name otherwise.
    private func progressCaption(_ snapshot: RautaWatchWorkoutSnapshot) -> String {
        if let number = snapshot.exerciseNumber, let count = snapshot.exerciseCount, count > 0 {
            return "EXERCISE \(number) OF \(count)"
        }
        return snapshot.workoutName.uppercased()
    }

    private func timePanel(_ snapshot: RautaWatchWorkoutSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 60 : 1)) { context in
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(duration(session.elapsedSeconds(at: context.date), showsSeconds: !isLuminanceReduced))
                    .font(.system(size: 36, weight: .black, design: .rounded))
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

    /// The set coming up: which, and what the plan asks of it.
    private func setLine(_ snapshot: RautaWatchWorkoutSnapshot) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(snapshot.setCount > 0
                     ? "SET \(Swift.min(snapshot.setIndex, snapshot.setCount)) OF \(snapshot.setCount)"
                     : "NEXT SET")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(loadText(snapshot.loadKg)) × \(snapshot.reps)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            if let sets = snapshot.sets, !sets.isEmpty, sets.count <= 10 {
                HStack(spacing: 4) {
                    ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
                        Capsule()
                            .fill(set.done ? WatchPalette.primary : WatchPalette.primary.opacity(0.22))
                            .frame(width: index == snapshot.setIndex - 1 ? 14 : 7, height: 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            }
        }
    }

    /// A countdown — the warm-up or a rest — with a ring that drains and the
    /// controls that change it.
    private func countdown(
        title: String,
        until: Date,
        total: Double?,
        actions: [(label: String, symbol: String, action: () -> Void)]
    ) -> some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: isLuminanceReduced ? 1 : 1.0 / 20, paused: false)) { context in
                let remaining = Swift.max(0, until.timeIntervalSince(context.date))
                let fraction = total.map { $0 > 0 ? remaining / $0 : 0 } ?? 1
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.12), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: Swift.min(1, Swift.max(0, fraction)))
                        .stroke(WatchPalette.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(title)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                        Text(clock(remaining))
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 74, height: 74)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title.capitalized), \(Int(remaining.rounded())) seconds left")
            }

            HStack(spacing: 8) {
                ForEach(actions, id: \.label) { item in
                    Button(action: item.action) {
                        Label(item.label, systemImage: item.symbol)
                            .labelStyle(.titleOnly)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                    .tint(WatchPalette.primary)
                }
            }
        }
    }

    private func pauseButton(_ snapshot: RautaWatchWorkoutSnapshot) -> some View {
        Button {
            session.control(snapshot.isPaused ? .resume : .pause)
        } label: {
            Image(systemName: snapshot.isPaused ? "play.fill" : "pause.fill")
        }
        .accessibilityLabel(snapshot.isPaused ? "Resume workout" : "Pause workout")
    }

    // MARK: Log

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
                value: loadText(session.loadKg),
                decrementDisabled: session.loadKg <= 0,
                decrement: { session.setLoad(session.loadKg - 0.5) },
                increment: { session.setLoad(session.loadKg + 0.5) },
                crown: Binding(get: { session.loadKg }, set: { session.setLoad($0) }),
                crownRange: 0...500,
                crownStep: 0.5
            )

            SetAdjuster(
                title: "Reps",
                systemImage: "repeat",
                value: String(session.reps),
                decrementDisabled: session.reps <= 1,
                decrement: { session.setReps(session.reps - 1) },
                increment: { session.setReps(session.reps + 1) },
                crown: Binding(
                    get: { Double(session.reps) },
                    set: { session.setReps(Int($0.rounded())) }
                ),
                crownRange: 1...100,
                crownStep: 1
            )

            Button {
                session.markSetDone()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                    Text("Set done")
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var finished: some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(WatchPalette.primary)

            Text("All exercises done")
                .font(.headline.weight(.bold))

            Text("Finish and review it on iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var waitingView: some View {
        VStack(spacing: 8) {
            RautaSprite(loop: .calm)
                .frame(width: 66, height: 66)
                .background(RautaGlow())

            Text("RAUTA")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(WatchPalette.primary)

            Text("Ready for your workout")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Text("Start a workout on iPhone and it opens here.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Words

    private func loadText(_ kg: Double) -> String {
        let rounded = kg.rounded()
        if abs(kg - rounded) < 0.001 {
            return "\(Int(rounded)) kg"
        }
        return String(format: "%.1f kg", kg)
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return total >= 60 ? String(format: "%d:%02d", total / 60, total % 60) : "\(total)"
    }

    private func duration(_ seconds: TimeInterval, showsSeconds: Bool) -> String {
        let total = Swift.max(0, Int(seconds.rounded(.down)))
        guard !showsSeconds else { return ElapsedClock.format(seconds: total) }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? String(format: "%d:%02d", hours, minutes) : "\(minutes) min"
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

/// A soft light of the accent behind RAUTA, so a near-black character reads
/// on the watch's black.
private struct RautaGlow: View {
    var body: some View {
        Circle()
            .fill(WatchPalette.primary.opacity(0.18))
            .blur(radius: 10)
            .accessibilityHidden(true)
    }
}

/// The iPhone app's accent. Read through ``WatchAccentStore``, which SwiftUI
/// observes, so the watch redraws the moment the phone sends a new one.
@MainActor
enum WatchPalette {
    private static var accent: RautaWatchAccent { WatchAccentStore.shared.accent }

    static var primary: Color { Color(hex: accent.primary) }
    static var primaryGradientStart: Color { Color(hex: accent.gradientStart) }
    static var primaryGradientEnd: Color { Color(hex: accent.gradientEnd) }
    /// A label on the accent: white or near-black, whichever reads.
    static var onPrimary: Color { accent.whiteLabel ? .white : Color(hex: RautaBrand.onPrimary) }
}
