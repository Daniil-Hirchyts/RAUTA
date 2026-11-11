import SwiftUI

struct ConditionalNativeBottomAccessory<Accessory: View>: ViewModifier {
    let isVisible: Bool
    let accessory: () -> Accessory

    init(
        isVisible: Bool,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.isVisible = isVisible
        self.accessory = accessory
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if isVisible {
            content.tabViewBottomAccessory {
                accessory()
            }
        } else {
            content
        }
    }
}

/// The exercise player grows out of the accessory above the tab bar, the way a
/// mini player opens into Now Playing, and drags back down into it.
enum ExercisePlayerZoom {
    static let sourceID = "exercise-player"
}

struct NativeExerciseBottomAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let exercise: ExerciseSummary
    @Binding var isPresented: Bool
    let onCompactChange: (Bool) -> Void

    private var compact: Bool { placement == .inline }

    var body: some View {
        CurrentExerciseAccessory(
            exercise: exercise,
            onOpen: {
                Haptics.trigger(.selection)
                withAnimation(Theme.Motion.settleSlow) {
                    isPresented = true
                }
            },
            compact: compact
        )
        .appZoomSource(ExercisePlayerZoom.sourceID, cornerRadius: compact ? 25 : 31)
        .padding(.horizontal, compact ? 4 : Theme.Metrics.contentInset)
        .task(id: compact) {
            // The native tab/accessory morph can briefly keep both placement
            // hosts alive. Yield once so a disappearing host is cancelled and
            // only the currently mounted placement drives RAUTA's compactness.
            await Task.yield()
            guard !Task.isCancelled else { return }
            onCompactChange(compact)
        }
    }
}

struct NativeWorkoutCompleteAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let session: ActiveWorkoutSession
    @Binding var isPresented: Bool
    let onCompactChange: (Bool) -> Void

    private var compact: Bool { placement == .inline }

    var body: some View {
        Button {
            Haptics.trigger(.selection)
            withAnimation(Theme.Motion.settleSlow) {
                isPresented = true
            }
        } label: {
            HStack(spacing: compact ? 8 : 10) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: compact ? 18 : 22, weight: .semibold))
                    .foregroundStyle(Theme.primary)

                VStack(alignment: .leading, spacing: compact ? 0 : 2) {
                    Text(session.workoutName)
                        .font(Theme.sans(compact ? 13 : 16, weight: .bold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    Text("All exercises complete")
                        .font(Theme.sans(compact ? 10 : 11, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(ActiveWorkout.formatDuration(ActiveWorkout.elapsedMs(session)))
                        .font(Theme.sans(compact ? 11 : 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.foreground)
                        .contentTransition(.identity)
                        .transaction { $0.animation = nil }
                }
            }
            .padding(.horizontal, compact ? 10 : 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: compact ? 50 : 62)
        .appZoomSource(ExercisePlayerZoom.sourceID, cornerRadius: compact ? 25 : 31)
        .padding(.horizontal, compact ? 4 : Theme.Metrics.contentInset)
        .accessibilityLabel("Workout complete, open workout summary")
        .task(id: compact) {
            // See `NativeExerciseBottomAccessory`: only the surviving native
            // placement host may update the shared RAUTA compact state.
            await Task.yield()
            guard !Task.isCancelled else { return }
            onCompactChange(compact)
        }
    }
}

/// A warm-up put away while it runs: what to do now and the time left, and a
/// tap to bring it back.
struct NativeWarmupAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let session: ActiveWorkoutSession
    let onOpen: () -> Void
    let onCompactChange: (Bool) -> Void

    private var compact: Bool { placement == .inline }
    private var start: Date { Date(epochMillis: session.startedAt) }
    private var until: Date { Date(epochMillis: session.warmupUntil ?? session.startedAt) }

    var body: some View {
        let steps = WarmupRoutine.steps(
            for: session.exerciseIds,
            seconds: until.timeIntervalSince(start),
            seed: session.workoutId
        )
        Button {
            Haptics.trigger(.selection)
            WorkoutAudio.touch(.open)
            onOpen()
        } label: {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let current = WarmupRoutine.current(steps, elapsed: context.date.timeIntervalSince(start))
                let remaining = max(0, until.timeIntervalSince(context.date))
                HStack(spacing: compact ? 8 : 10) {
                    Image(systemName: "figure.flexibility")
                        .font(.system(size: compact ? 18 : 22, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(width: compact ? 30 : 42)

                    VStack(alignment: .leading, spacing: compact ? 0 : 2) {
                        Text("Warm-up")
                            .font(Theme.sans(compact ? 13 : 16, weight: .bold))
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(1)
                        Text(current?.step.move ?? "Nearly there")
                            .font(Theme.sans(compact ? 10 : 11, weight: .medium))
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(WorkoutClock.format(Int(remaining.rounded(.up))))
                        .font(Theme.sans(compact ? 11 : 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.foreground)
                        .contentTransition(.identity)
                        .transaction { $0.animation = nil }
                }
                .padding(.horizontal, compact ? 10 : 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .frame(height: compact ? 50 : 62)
        .padding(.horizontal, compact ? 4 : Theme.Metrics.contentInset)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warm-up running")
        .accessibilityHint("Shows the warm-up")
        .task(id: compact) {
            // See `NativeExerciseBottomAccessory`: only the surviving native
            // placement host may update the shared RAUTA compact state.
            await Task.yield()
            guard !Task.isCancelled else { return }
            onCompactChange(compact)
        }
    }
}
