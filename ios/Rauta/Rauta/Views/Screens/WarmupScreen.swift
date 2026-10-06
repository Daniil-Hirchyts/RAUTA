import SwiftUI

/// The warm-up that opens every workout, over the whole app until it is done:
/// the time left in large numerals, then the step to do now — the part of the
/// body lit on the body map, and in a few words what to do with it — and the
/// step after it underneath.
///
/// It runs on the session's own deadline, so leaving the app or locking the
/// phone loses nothing; the end is sounded by ``RestAlerts`` like a rest's.
/// When it runs out, or on "Start training", the player opens on the first
/// exercise.
///
/// It can be put away — the chevron, or a swipe down — and keeps running
/// while it is: the bar above the tabs counts it down and brings it back.
struct WarmupScreen: View {
    private let store = AppStore.shared
    let session: ActiveWorkoutSession
    let onDone: () -> Void
    let onHide: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// It covers the whole screen, bars included, so it keeps clear of the
    /// status bar and home indicator itself.
    @Environment(\.appSafeAreaInsets) private var safeAreaInsets
    @State private var shown = false
    @State private var finishing = false
    /// How far a swipe down has pulled the page.
    @State private var pull: CGFloat = 0

    private var until: Date {
        Date(epochMillis: session.warmupUntil ?? session.startedAt)
    }
    private var start: Date { Date(epochMillis: session.startedAt) }

    private var steps: [WarmupRoutine.Step] {
        WarmupRoutine.steps(
            for: session.exerciseIds,
            seconds: until.timeIntervalSince(start),
            seed: session.workoutId
        )
    }

    var body: some View {
        let steps = steps
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let remaining = max(0, until.timeIntervalSince(context.date))
            let total = max(1, until.timeIntervalSince(start))
            let current = WarmupRoutine.current(steps, elapsed: elapsed)
            let finalSeconds = FinalCountdown.isShowing(until: until, at: context.date)

            VStack(spacing: 0) {
                header(remaining: remaining, progress: min(1, elapsed / total))
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topLeading) {
                        AppHeaderButton(systemImage: "chevron.down", label: "Hide warm-up", action: hide)
                    }

                Spacer(minLength: 12)

                if let current {
                    step(current.step, index: current.index, count: steps.count, elapsed: elapsed, finalSeconds: finalSeconds)
                    Group {
                        if current.index + 1 < steps.count {
                            upNext("NEXT", steps[current.index + 1].title)
                        } else if let first = session.exerciseIds.first.flatMap({ ExerciseCatalogue.byId[$0] }) {
                            upNext("THEN", WorkoutAgenda.name(first))
                        }
                    }
                    .padding(.top, 18)
                    .opacity(finalSeconds ? 0 : 1)
                }

                Spacer(minLength: 12)

                controls
            }
            .padding(.horizontal, Theme.Metrics.contentInset)
            .padding(.top, safeAreaInsets.top)
            .padding(.bottom, max(safeAreaInsets.bottom, 14) + 4)
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .animation(.spring(response: 0.5, dampingFraction: 0.84), value: finalSeconds)
            .onChange(of: current?.index) { before, after in
                // The next step: two notes, heard with the phone on the floor.
                guard let before, let after, after > before else { return }
                var rng = SystemRandomNumberGenerator()
                WorkoutAudio.play(RautaPhrase.step(using: &rng), on: .workout, level: 0.4, felt: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { background }
        // The whole page follows a pull, the way a sheet does, and shows
        // the app beneath it.
        .offset(y: pull)
        .contentShape(Rectangle())
        .simultaneousGesture(swipeToHide)
        .task(id: session.warmupUntil) { await runOut() }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86).delay(0.05)) { shown = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Pieces

    private func header(remaining: TimeInterval, progress: Double) -> some View {
        VStack(spacing: 8) {
            Text("WARM-UP")
                .font(Theme.sans(12, weight: .black))
                .kerning(2)
                .foregroundStyle(Theme.primary)
            Text(WorkoutClock.format(Int(remaining.rounded(.up))))
                .font(Theme.readout(64))
                .foregroundStyle(Theme.foreground)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy(duration: 0.25), value: Int(remaining.rounded(.up)))
                .accessibilityLabel("Warm-up left, \(WorkoutClock.spoken(Int(remaining.rounded(.up))))")
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.foreground.opacity(0.1))
                    // Only the length animates: a page being pulled must not
                    // leave the bar trailing behind it.
                    Capsule()
                        .fill(Theme.primary)
                        .animation(.linear(duration: 0.5)) { $0.frame(width: proxy.size.width * progress) }
                }
            }
            .frame(width: 180, height: 4)
        }
    }

    /// The step: the body map lighting what it works, its name, and what to
    /// do. In the last seconds the map steps aside for the countdown.
    private func step(_ step: WarmupRoutine.Step, index: Int, count: Int, elapsed: Double, finalSeconds: Bool) -> some View {
        let left = max(0, Int((step.end - elapsed).rounded(.up)))
        return VStack(spacing: 12) {
            WarmupBodyMap(muscles: step.muscles)
                .frame(height: 250)
                .opacity(finalSeconds ? 0 : 1)
                .scaleEffect(finalSeconds ? 0.92 : 1)
                .overlay {
                    if finalSeconds {
                        FinalCountdown(until: until)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
            VStack(spacing: 8) {
                Text(step.title)
                    .font(Theme.sans(24, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.center)
                Text(step.instruction)
                    .font(Theme.sans(16, weight: .medium))
                    .foregroundStyle(Theme.foreground.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 330)
                Text("Step \(index + 1) of \(count) · \(WorkoutClock.format(left)) left")
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
                    .contentTransition(.numericText(countsDown: true))
                    .padding(.top, 2)
            }
            .id(step.id)
            .transition(.opacity.combined(with: .offset(y: 8)))
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: step.id)
        .accessibilityElement(children: .combine)
    }

    private func upNext(_ label: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(Theme.sans(10, weight: .black))
                .kerning(1.4)
                .foregroundStyle(Theme.mutedForeground)
            Text(title)
                .font(Theme.sans(15, weight: .semibold))
                .foregroundStyle(Theme.foreground.opacity(0.85))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            AppButton(variant: .secondary, size: .cta, accessibilityLabel: "One more minute of warm-up") {
                Haptics.trigger(.selection, sound: .up)
                store.activeWorkout.extendWarmup(by: 60)
            } label: {
                Label("1 min", systemImage: "plus")
            }
            .frame(width: 124)

            AppButton("Start training", size: .cta, expands: true) {
                finish(early: true)
            }
        }
    }

    /// Pulled down, the page follows the finger with a little resistance;
    /// let go far enough and it is put away, otherwise it springs back.
    private var swipeToHide: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard value.translation.height > 0,
                      value.translation.height > abs(value.translation.width)
                else { return }
                pull = value.translation.height * 0.55
            }
            .onEnded { value in
                let flung = value.predictedEndTranslation.height > 260
                if value.translation.height > 140 || (flung && value.translation.height > 40) {
                    hide()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { pull = 0 }
                }
            }
    }

    private func hide() {
        Haptics.trigger(.selection)
        WorkoutAudio.touch(.close)
        onHide()
    }

    private var background: some View {
        ZStack {
            Theme.background
            LinearGradient(
                colors: [Theme.primary.opacity(0.3), Theme.oxblood.opacity(0.34), .clear],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            AppGrain()
        }
        .ignoresSafeArea()
    }

    // MARK: Ending

    /// Waits out the warm-up, lets "Go" show for a beat, then moves on.
    private func runOut() async {
        let wait = until.timeIntervalSinceNow + 0.9
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        guard !Task.isCancelled else { return }
        finish(early: false)
    }

    private func finish(early: Bool) {
        guard !finishing else { return }
        finishing = true
        // Run out, it has already been sounded by the clock that ended it.
        if early { WorkoutAudio.play(.warmupOver) }
        store.activeWorkout.endWarmup()
        onDone()
    }
}

/// The front and back of the body, the muscles a warm-up step works lit, the
/// rest resting. The light moves as the steps change.
private struct WarmupBodyMap: View {
    let muscles: [MuscleId]

    var body: some View {
        HStack(spacing: 6) {
            figure(.front)
            figure(.back)
        }
        .animation(.easeInOut(duration: 0.5), value: muscles)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Warming up: " + muscles.map(\.label).joined(separator: ", "))
    }

    private func figure(_ side: BodySide) -> some View {
        BodyFigure(
            view: BodyPaths.view(side),
            selectedMuscles: muscles,
            selectedColor: Theme.primary,
            showsSelectionGlow: false,
            compact: true
        )
        .frame(maxWidth: .infinity)
    }
}
