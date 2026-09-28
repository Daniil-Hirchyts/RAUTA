import SwiftUI

/// The warm-up that opens every workout, over the whole app until it is done:
/// the time left in large numerals, the move to do now playing big, and the
/// one after it underneath.
///
/// It runs on the session's own deadline, so leaving the app or locking the
/// phone loses nothing; the end is sounded by ``RestAlerts`` like a rest's.
/// When it runs out, or on "Start training", the player opens on the first
/// exercise.
struct WarmupScreen: View {
    private let store = AppStore.shared
    let session: ActiveWorkoutSession
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// It covers the whole screen, bars included, so it keeps clear of the
    /// status bar and home indicator itself.
    @Environment(\.appSafeAreaInsets) private var safeAreaInsets
    @State private var shown = false
    @State private var finishing = false

    private var until: Date {
        Date(epochMillis: session.warmupUntil ?? session.startedAt)
    }
    private var start: Date { Date(epochMillis: session.startedAt) }

    private var moves: [WarmupRoutine.Move] {
        WarmupRoutine.moves(
            for: session.exerciseIds,
            seconds: until.timeIntervalSince(start),
            seed: session.workoutId
        )
    }

    var body: some View {
        let moves = moves
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let remaining = max(0, until.timeIntervalSince(context.date))
            let total = max(1, until.timeIntervalSince(start))
            let current = WarmupRoutine.current(moves, elapsed: elapsed)

            VStack(spacing: 0) {
                header(remaining: remaining, progress: min(1, elapsed / total))
                    .padding(.top, 12)

                Spacer(minLength: 12)

                if let current {
                    move(current.move, index: current.index, count: moves.count, elapsed: elapsed)
                    if current.index + 1 < moves.count {
                        upNext(moves[current.index + 1])
                            .padding(.top, 18)
                    } else if let first = session.exerciseIds.first.flatMap({ ExerciseCatalogue.byId[$0] }) {
                        upNext(title: "THEN", exercise: first)
                            .padding(.top, 18)
                    }
                }

                Spacer(minLength: 12)

                controls
            }
            .padding(.horizontal, Theme.Metrics.contentInset)
            .padding(.top, safeAreaInsets.top)
            .padding(.bottom, max(safeAreaInsets.bottom, 14) + 4)
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { background }
        .contentShape(Rectangle())
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
                    Capsule()
                        .fill(Theme.primary)
                        .frame(width: proxy.size.width * progress)
                        .animation(.linear(duration: 0.5), value: progress)
                }
            }
            .frame(width: 180, height: 4)
        }
    }

    private func move(_ move: WarmupRoutine.Move, index: Int, count: Int, elapsed: Double) -> some View {
        let name = ExerciseCatalogue.byId[move.exerciseId].map { WorkoutAgenda.name($0) } ?? "Move"
        let left = max(0, Int((move.end - elapsed).rounded(.up)))
        return VStack(spacing: 10) {
            ExerciseMediaView(exerciseId: move.exerciseId, animated: true)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 300, maxHeight: 300)
                .overlay { FinalCountdown(until: until) }
                .id(move.exerciseId)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            Text(name)
                .font(Theme.sans(24, weight: .bold))
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text("Move \(index + 1) of \(count) · \(WorkoutClock.format(left)) on this one")
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(Theme.mutedForeground)
                .contentTransition(.numericText(countsDown: true))
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: move.exerciseId)
        .accessibilityElement(children: .combine)
    }

    private func upNext(_ move: WarmupRoutine.Move) -> some View {
        Group {
            if let exercise = ExerciseCatalogue.byId[move.exerciseId] {
                upNext(title: "NEXT", exercise: exercise)
            }
        }
    }

    private func upNext(title: String, exercise: ExerciseSummary) -> some View {
        HStack(spacing: 12) {
            ExerciseMediaView(exerciseId: exercise.id)
                .padding(3)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(Theme.muted.opacity(0.7)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.sans(10, weight: .black))
                    .kerning(1.4)
                    .foregroundStyle(Theme.mutedForeground)
                Text(WorkoutAgenda.name(exercise))
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: 340)
        .background { GradientCard(radius: Theme.Radius.xl, accent: Theme.primary, strength: 0.4) }
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            AppButton(variant: .secondary, size: .cta, accessibilityLabel: "One more minute of warm-up") {
                Haptics.trigger(.selection)
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
        if early { WorkoutAudio.play(.warmupOver) }
        Haptics.trigger(.success)
        store.activeWorkout.endWarmup()
        onDone()
    }
}
