import SwiftUI

struct CurrentExerciseAccessory: View {
    private let store = AppStore.shared
    let exercise: ExerciseSummary
    let onOpen: () -> Void
    let compact: Bool

    private var draft: PersistedActiveExerciseDraft? {
        TrainingSessionBridge.draftExercise(store.trainingRecords.data.activeWorkout, exercise.id)
    }

    private var repsText: String {
        if let set = draft?.sets.first(where: { $0.observation?.completed != true }) {
            if let reps = set.observation?.reps {
                return "\(Num.trimmed(reps)) reps"
            }
            if let target = set.target?.reps {
                return set.setType == .warmup ? "Warm-up · \(target.label) reps" : "\(target.label) reps"
            }
        }
        if let reps = draft?.sets.reversed().compactMap({ $0.observation?.reps }).first {
            return "\(Num.trimmed(reps)) reps"
        }
        if let target = draft?.sets.compactMap({ $0.target?.reps }).first {
            return "\(target.label) reps"
        }
        return "— reps"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: compact ? 8 : 10) {
                ExerciseMediaView(exerciseId: exercise.id, animated: true)
                    .frame(width: compact ? 30 : 42, height: compact ? 30 : 42)
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 7 : 10, style: .continuous))

                VStack(alignment: .leading, spacing: compact ? 0 : 2) {
                    Text(exercise.name.capitalized)
                        .font(Theme.sans(compact ? 13 : 16, weight: .bold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    Text(repsText)
                        .font(Theme.sans(compact ? 10 : 11, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                }
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)

                setTimer
            }
            .padding(.horizontal, compact ? 10 : 12)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .frame(height: compact ? 50 : 62)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(exercise.name.capitalized), Current exercise")
        .accessibilityHint("Opens the current exercise")
        // A fixed-height bar accessory: text grows while it still fits.
        // No animation of its own: the system morphs the bar between its two
        // placements, and each placement is a separate copy of this view.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var setTimer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let session = store.activeWorkout.session
            let restUntil = session?.restUntil.map { Date(epochMillis: $0) }
            let remaining = restUntil.map { $0.timeIntervalSince(context.date) } ?? -1
            let isResting = remaining > 0
            let anchor = session.map {
                Date(epochMillis: $0.setPhaseStartedAt ?? $0.startedAt)
            } ?? context.date
            let seconds = isResting
                ? Int(remaining.rounded(.up))
                : Swift.max(0, Int(context.date.timeIntervalSince(anchor).rounded(.down)))

            VStack(alignment: .trailing, spacing: compact ? 0 : 1) {
                Text(isResting ? "REST" : "SET")
                    .font(Theme.sans(compact ? 7 : 8, weight: .black))
                    .kerning(0.8)
                    .foregroundStyle(isResting ? Theme.primary : Theme.mutedForeground)
                Text(WorkoutClock.format(seconds))
                    .font(Theme.sans(compact ? 11 : 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: compact ? 42 : 52, alignment: .trailing)
            // A tick that lands inside the bar's morph must not crossfade the
            // old reading over the new one.
            .contentTransition(.identity)
            .transaction { $0.animation = nil }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isResting ? "Rest timer, \(WorkoutClock.format(seconds))" : "Set timer, \(WorkoutClock.format(seconds))")
        }
    }
}

struct ActiveExerciseDrawer: View {
    private let store = AppStore.shared
    private let activeWorkout = ActiveWorkoutStore.shared
    let exercise: ExerciseSummary
    let session: ActiveWorkoutSession
    let restSeconds: Double
    let onDetail: () -> Void
    let hasNextExercise: Bool
    let onFinishExercise: () -> Void
    let onFinish: () -> Void
    let onDismiss: () -> Void
    @State private var revealDetails = false
    @State private var resting = false
    /// The rest's last seconds: the timer has left its corner for the
    /// exercise's place, big enough to read from across the gym.
    @State private var finalSeconds = false
    @Namespace private var timerSpace
    // `.ignoresSafeArea()` below zeroes out the geometry proxy's own
    // safeAreaInsets, so the top clearance comes from the app-wide value
    // captured before anything here started ignoring the safe area.
    @Environment(\.appSafeAreaInsets) private var appSafeAreaInsets

    var body: some View {
        Group {
            if let liveSession = activeWorkout.session,
               ActiveWorkout.progress(liveSession).isComplete {
                CompletedWorkoutDrawer(
                    session: liveSession,
                    onFinish: onFinish,
                    onDismiss: onDismiss
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                // Dragging the player down is the zoom transition's own
                // dismissal: the system follows the finger and throws the
                // player back into the accessory it grew from.
                GeometryReader { proxy in
                    playerSurface(proxy)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.24), value: store.activeWorkout.session.map { ActiveWorkout.progress($0).isComplete } ?? false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.22).delay(0.12)) {
                revealDetails = true
            }
        }
        .accessibilityAddTraits(.isModal)
        // The zoom dismissal is a drag; VoiceOver's scrub closes it too.
        .accessibilityAction(.escape, onDismiss)
    }

    private func playerSurface(_ proxy: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            GeometryReader { mediaProxy in
                let mediaSize = max(
                    0,
                    min(336, min(proxy.size.width - 32, mediaProxy.size.height))
                )

                // A tap rather than a button: a button holds on to a touch that
                // starts on it, and this is the biggest thing a drag down to
                // close the player starts on.
                ExerciseMediaView(exerciseId: exercise.id, animated: true)
                    .frame(width: mediaSize, height: mediaSize)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDetail)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Open \(exercise.name) details")
                    // In the rest's last seconds the exercise steps aside for
                    // the timer, which takes its place.
                    .opacity(finalSeconds ? 0 : 1)
                    .scaleEffect(finalSeconds ? 0.9 : 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .overlay {
                        if finalSeconds {
                            FinalCountdown(until: restEnds)
                                .frame(width: min(336, proxy.size.width - 32), height: mediaSize)
                                .matchedGeometryEffect(id: "rest-timer", in: timerSpace)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                    }
            }
            .padding(.top, Swift.max(appSafeAreaInsets.top, 18) + 60)
            .frame(maxWidth: .infinity)
            .layoutPriority(-1)

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name.capitalized)
                        .font(Theme.sans(24, weight: .bold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(trainedMusclesText)
                        .font(Theme.sans(13, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                LikeButton(
                    liked: store.favorites.isFavorite(exercise.id),
                    label: store.favorites.isFavorite(exercise.id)
                        ? "Remove \(exercise.name) from favorites"
                        : "Add \(exercise.name) to favorites",
                    size: 36,
                    iconSize: 18,
                    chromeless: true
                ) {
                    store.favorites.toggleFavorite(exercise.id)
                }

            }
            .padding(.horizontal, Theme.Metrics.contentInset)
            .padding(.top, 18)

            ActiveSetLog(
                exerciseId: exercise.id,
                restSeconds: restSeconds,
                hasNextExercise: hasNextExercise,
                onFinishExercise: onFinishExercise
            )
                // A new exercise is a new log: its counter, measure and station
                // are loaded afresh rather than carried over from the last one.
                .id(exercise.id)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(revealDetails ? 1 : 0)
                .offset(y: revealDetails ? 0 : 18)
                .padding(.top, 12)
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.bottom, Swift.max(proxy.safeAreaInsets.bottom, 14))
        }
        // The clock, in the corner beside RAUTA. Its own layer, so its
        // ticking never touches RAUTA or the menu RAUTA holds open.
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .leading) {
                if !finalSeconds {
                    PlayerCornerTimer()
                        .matchedGeometryEffect(id: "rest-timer", in: timerSpace)
                        .opacity(revealDetails ? 1 : 0)
                }
            }
            .frame(height: 52)
            .padding(.top, Swift.max(appSafeAreaInsets.top, 18) + 2)
            .padding(.leading, Theme.Metrics.contentInset + 4)
        }
        // RAUTA keeps the workout: it holds its actions and keeps the rest.
        .overlay(alignment: .topTrailing) {
            playerRauta
                .padding(.top, Swift.max(appSafeAreaInsets.top, 18) + 2)
                .padding(.trailing, Theme.Metrics.contentInset + 4)
        }
        .task(id: store.activeWorkout.session?.restUntil) { await followFinalSeconds() }
        .background {
            ZStack {
                Theme.background
                LinearGradient(
                    colors: [Theme.primary.opacity(0.34), Theme.oxblood.opacity(0.38), .clear],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                AppGrain()
            }
            .ignoresSafeArea()
        }
    }

    private var paused: Bool { store.activeWorkout.session?.runningSince == nil }

    private var restEnds: Date? {
        store.activeWorkout.session?.restUntil.map { Date(epochMillis: $0) }
    }

    private var playerRauta: some View {
        // Quiet here: the rest ring and RAUTA's face say enough while you
        // train, and its menu is one tap away.
        AppMenuButton(label: "Workout actions", compact: true, mood: resting ? .calm : .focused, speaks: false) {
            Button {
                Haptics.trigger(.selection)
                paused ? store.activeWorkout.resume() : store.activeWorkout.pause()
            } label: {
                Label(paused ? "Resume workout" : "Pause workout", systemImage: paused ? "play.fill" : "pause.fill")
            }
            if resting {
                Button {
                    Haptics.trigger(.selection, sound: .up)
                    store.activeWorkout.extendRest(by: 30, exerciseName: exercise.name)
                } label: {
                    Label("30 seconds more", systemImage: "plus.circle")
                }
                Button {
                    Haptics.trigger(.selection)
                    store.activeWorkout.endRest()
                } label: {
                    Label("Skip rest", systemImage: "forward.fill")
                }
            }
            Button(action: onFinishExercise) {
                Label(hasNextExercise ? "Next exercise" : "Finish exercise", systemImage: "forward.end.fill")
            }
            Button(action: onFinish) {
                Label("Finish workout", systemImage: "flag.checkered")
            }
        }
        .background { RestRing(until: session.restUntil, total: restSeconds) }
        .task(id: store.activeWorkout.session?.restUntil) { await followRest() }
    }

    /// Moves the timer to the exercise's place for the rest's last seconds and
    /// back to its corner once "Go" has shown.
    private func followFinalSeconds() async {
        func show(_ value: Bool) {
            guard finalSeconds != value else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { finalSeconds = value }
        }
        guard let until = restEnds else { return show(false) }
        let untilShowing = until.timeIntervalSinceNow - FinalCountdown.window
        if untilShowing > 0 {
            show(false)
            try? await Task.sleep(for: .seconds(untilShowing))
            guard !Task.isCancelled else { return }
        }
        guard FinalCountdown.isShowing(until: until) else { return show(false) }
        show(true)
        let untilGone = until.timeIntervalSinceNow + FinalCountdown.goHold
        if untilGone > 0 { try? await Task.sleep(for: .seconds(untilGone)) }
        guard !Task.isCancelled else { return }
        show(false)
    }

    /// Resting while the deadline is ahead; RAUTA eases off until it passes.
    private func followRest() async {
        guard let until = store.activeWorkout.session?.restUntil else {
            resting = false
            return
        }
        let remaining = until / 1_000 - Date().timeIntervalSince1970
        guard remaining > 0 else {
            resting = false
            return
        }
        resting = true
        try? await Task.sleep(for: .seconds(remaining))
        if !Task.isCancelled { resting = false }
    }

    private var trainedMusclesText: String {
        let labels = exercise.muscles.map(\.label)
        return labels.isEmpty ? "Full body" : labels.joined(separator: " · ")
    }
}

/// The rest, drawn around RAUTA and running out as it ends: the one keeping
/// the timer wears it.
private struct RestRing: View {
    let until: Double?
    let total: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let remaining = until.map { $0 / 1_000 - context.date.timeIntervalSince1970 } ?? 0
            let fraction = total > 0 ? min(1, max(0, remaining / total)) : 0
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 52, height: 52)
                .opacity(fraction > 0 ? 1 : 0)
                .animation(.linear(duration: 0.2), value: fraction)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct CompletedWorkoutDrawer: View {
    private let store = AppStore.shared
    let session: ActiveWorkoutSession
    let onFinish: () -> Void
    let onDismiss: () -> Void

    private var liveSession: ActiveWorkoutSession {
        store.activeWorkout.session ?? session
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: Swift.max(proxy.safeAreaInsets.top, 18) + 48)

                RautaCharacter(mood: .focused)
                    .frame(width: 118, height: 118)
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text(liveSession.workoutName)
                        .font(Theme.sans(30, weight: .bold))
                        .foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Text("All exercises complete")
                        .font(Theme.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)

                    AppButton("Finish workout", size: .cta, expands: true, action: onFinish)
                        .frame(maxWidth: 280)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 28)

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(ActiveWorkout.formatDuration(ActiveWorkout.elapsedMs(liveSession)))
                        .font(Theme.readout(72))
                        .monospacedDigit()
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)
                }
                .padding(.top, 34)

                HStack(spacing: 28) {
                    workoutMetric(
                        value: "\(ActiveWorkout.progress(liveSession).completed)",
                        label: "Exercises"
                    )
                    workoutMetric(
                        value: liveSession.runningSince == nil ? "Paused" : "Running",
                        label: "Workout"
                    )
                }
                .padding(.top, 16)
                .padding(.horizontal, 28)

                Spacer(minLength: Swift.max(proxy.safeAreaInsets.bottom, 24))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background {
                ZStack {
                    Theme.background
                    LinearGradient(
                        colors: [Theme.primary.opacity(0.34), Theme.oxblood.opacity(0.38), .clear],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                    AppGrain()
                }
                .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
        // The zoom dismissal is a drag; VoiceOver's scrub closes it too.
        .accessibilityAction(.escape, onDismiss)
    }

    private func workoutMetric(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.sans(20, weight: .bold))
                .foregroundStyle(Theme.foreground)
            Text(label.uppercased())
                .font(Theme.sans(9, weight: .black))
                .kerning(1.5)
                .foregroundStyle(Theme.mutedForeground)
        }
        .frame(maxWidth: .infinity)
    }
}
