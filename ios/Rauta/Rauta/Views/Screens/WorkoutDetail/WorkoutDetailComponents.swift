import SwiftUI

struct RunningWorkoutOverview: View {
    let session: ActiveWorkoutSession
    /// Working sets across the workout as it now stands.
    let sets: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.runningSince == nil ? "PAUSED" : "IN PROGRESS")
                        .font(Theme.sans(11, weight: .black))
                        .kerning(1.8)
                        .foregroundStyle(Theme.primary)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(ActiveWorkout.formatDuration(ActiveWorkout.elapsedMs(session)))
                            .font(Theme.readout(58))
                            .foregroundStyle(Theme.foreground)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "checklist")
                    .font(.system(size: 25, weight: .regular))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 58, height: 58)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 18)

            HStack(spacing: 0) {
                metric("square.stack.3d.up", value: String(sets), label: "Sets")
                Rectangle().fill(Theme.foreground.opacity(0.16)).frame(width: 1).padding(.vertical, 4)
                metric("clock", value: elapsedMinutes, label: "Minutes")
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Theme.primary.opacity(0.24), Theme.oxblood.opacity(0.86)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, Theme.Metrics.contentInset)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var elapsedMinutes: String {
        String(max(0, Int(ActiveWorkout.elapsedMs(session) / 60_000)))
    }

    private func metric(_ icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Theme.primary)
            Text(value).font(Theme.readout(22)).foregroundStyle(Theme.foreground)
            Text(label.uppercased())
                .font(Theme.sans(9, weight: .black))
                .kerning(1.6)
                .foregroundStyle(Theme.foreground.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }
}

struct WorkoutOverview: View {
    let workout: Workout
    let past: Bool
    let planned: PlannedSessionView?

    private var signal: Color { past ? Theme.success : Theme.primary }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(past ? "COMPLETED" : "EXERCISES")
                        .font(Theme.sans(11, weight: .black))
                        .kerning(1.8)
                        .foregroundStyle(signal)
                    Text(primaryValue)
                        .font(Theme.readout(58))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
                Spacer(minLength: 4)
                Image(systemName: past ? "checkmark.circle" : "checklist")
                    .font(.system(size: 25, weight: .regular))
                    .foregroundStyle(signal)
                    .frame(width: 58, height: 58)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 18)

            HStack(spacing: 0) {
                metric(
                    icon: past ? "clock" : "square.stack.3d.up",
                    value: secondaryValue,
                    label: past ? "Duration" : "Sets"
                )
                Rectangle()
                    .fill(Theme.foreground.opacity(0.16))
                    .frame(width: 1)
                    .padding(.vertical, 2)
                metric(
                    icon: past ? "waveform.path.ecg" : "clock",
                    value: tertiaryValue,
                    label: past ? "kcal" : "Minutes"
                )
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [signal.opacity(0.24), Theme.oxblood.opacity(0.86)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, Theme.Metrics.contentInset)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var primaryValue: String {
        if past {
            let completed = workout.completion?.completedExerciseIds.count ?? 0
            return "\(completed)/\(workout.exerciseIds.count)"
        }
        return String(format: "%02d", planned?.prescription.count ?? workout.exerciseIds.count)
    }

    private var secondaryValue: String {
        if past {
            guard let completion = workout.completion else { return "—" }
            return ActiveWorkout.formatDuration(completion.durationMs)
        }
        return planned.map { String($0.workingSets) } ?? "—"
    }

    private var tertiaryValue: String {
        if past {
            return workout.completion.map { String(Int($0.activeCalories)) } ?? "—"
        }
        return planned.map { String($0.minutes) } ?? "—"
    }

    private func metric(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(signal)
            Text(value)
                .font(Theme.readout(22))
                .foregroundStyle(Theme.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label.uppercased())
                .font(Theme.sans(9, weight: .black))
                .kerning(1.6)
                .foregroundStyle(Theme.foreground.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }
}

struct LiveExerciseCard: View {
    let exercise: ExerciseSummary
    let restSeconds: Double
    let onDetail: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onDetail) {
                GeometryReader { hero in
                    ZStack(alignment: .bottom) {
                        ExerciseMediaView(exerciseId: exercise.id, animated: true)
                            .frame(width: hero.size.width, height: hero.size.height)
                            .background(Theme.card)

                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .frame(width: hero.size.width, height: 118)
                            .mask(
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.72), .white],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        .zIndex(1)
                        .allowsHitTesting(false)

                        // The caption sits on frosted glass, which is light in Light
                        // Mode: ink on it there, and a halo of the shell behind it.
                        Text(exercise.name.capitalized)
                            .font(Theme.sans(18, weight: .heavy))
                            .foregroundStyle(Theme.foreground)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)
                            .shadow(color: Theme.shell.opacity(0.34), radius: 4, y: 1)
                            .frame(maxWidth: .infinity, alignment: .bottom)
                            .zIndex(2)
                    }
                    .frame(width: hero.size.width, height: hero.size.height)
                }
                .frame(height: min(380, DeviceScreen.width - Theme.Metrics.contentInset * 2))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.xl3, style: .continuous)
                        .strokeBorder(Theme.primary.opacity(0.30), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.20), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .appZoomSource("live-exercise:\(exercise.id)", cornerRadius: Theme.Radius.xl3)
            .accessibilityLabel("Open \(exercise.name) demonstration")

            ActiveSetLog(exerciseId: exercise.id, restSeconds: restSeconds)
        }
    }
}

struct WorkoutExerciseRow: View {
    let exercise: ExerciseSummary
    let index: Int
    let prescription: PlannedExercisePrescription?
    let status: ExerciseStatus?
    let canFindAlternative: Bool
    let canRemove: Bool
    let onOpen: () -> Void
    let onAlternative: () -> Void
    let onToggle: () -> Void
    let onRemove: () -> Void
    /// Moves the row one place (-1 up, +1 down); nil where it cannot move.
    var onMove: ((Int) -> Void)? = nil

    var body: some View {
        card
            .appZoomSource("workout-exercise:\(exercise.id)", cornerRadius: Theme.Radius.xl2)
            // Attached to the card rather than the padded row so the actions
            // stay inside the content inset, where the hand-rolled ones sat.
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if canRemove {
                    Button(role: .destructive) {
                        Haptics.trigger(.selection)
                        onRemove()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .accessibilityLabel("Remove \(exercise.name)")
                }
                if canFindAlternative {
                    Button {
                        Haptics.trigger(.selection)
                        onAlternative()
                    } label: {
                        Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .tint(Theme.primary)
                    .accessibilityLabel("Replace \(exercise.name)")
                }
            }
            .padding(.horizontal, Theme.Metrics.contentInset)
            // Dragging to reorder has no VoiceOver form of its own.
            .accessibilityActions {
                if let onMove {
                    Button("Move up") { onMove(-1) }
                    Button("Move down") { onMove(1) }
                }
            }
    }

    private var card: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Group {
                    if let status {
                        Button(action: onToggle) {
                            AnimatedCheck(checked: status == .completed)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            status == .completed
                                ? "Mark \(exercise.name) as not done"
                                : "Mark \(exercise.name) as done"
                        )
                    } else {
                        Text(String(format: "%02d", index + 1))
                            .font(Theme.sans(16, weight: .bold))
                            .kerning(0.65)
                            .foregroundStyle(Theme.primary)
                    }
                }
                .frame(width: 50)
                .frame(maxHeight: .infinity)

                Button(action: onOpen) {
                    ExerciseMediaView(exerciseId: exercise.id, animated: true)
                        .frame(width: 136, height: 136)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(exercise.name) demonstration")

                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name.capitalized)
                        .font(Theme.sans(17, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(3)
                    Text(Wording.titleCase(exercise.equipment))
                        .font(Theme.sans(14, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
                .padding(.leading, 14)
                .padding(.trailing, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .frame(height: 148)

            if let prescription {
                WorkoutPrescriptionStrip(prescription: prescription)
            }
        }
        .contentShape(Rectangle())
        .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.primary, strength: 0.6) }
        .clipShape(
            RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous)
        )
    }
}

private struct WorkoutPrescriptionStrip: View {
    let prescription: PlannedExercisePrescription

    private var reps: String { prescription.reps.label }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                metric("Sets", String(prescription.sets), accent: true)
                metric("Reps", reps)
                metric("RIR", Num.trimmed(prescription.rir))
                if let loadKg = prescription.loadKg {
                    let each = prescription.loadBasis == .perImplement ? " each" : ""
                    metric("Load", "\(Resistance.formatKg(loadKg)) kg\(each)")
                }
                metric("Rest", "\(Int(prescription.restSeconds.rounded()))s")
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 15)
        }
        .background {
            LinearGradient(
                colors: [Theme.primary.opacity(0.09), .clear],
                startPoint: .leading,
                endPoint: UnitPoint(x: 0.78, y: 0.5)
            )
        }
    }

    private func metric(_ label: String, _ value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(Theme.sans(10, weight: .black))
                .kerning(1.8)
                .foregroundStyle(Theme.foreground.opacity(0.62))
            Text(value)
                .font(Theme.readout(15))
                .foregroundStyle(accent ? Theme.primarySofter : Theme.foreground)
                .lineLimit(1)
        }
    }
}

struct WorkoutSessionDock: View {
    let session: ActiveWorkoutSession
    let exercise: ExerciseSummary?
    let onNext: (() -> Void)?
    let onPause: () -> Void
    let onResume: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.runningSince == nil ? "PAUSED" : "IN PROGRESS")
                    .font(Theme.sans(10, weight: .bold))
                    .kerning(1.4)
                    .foregroundStyle(Theme.primary)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(ActiveWorkout.formatDuration(ActiveWorkout.elapsedMs(session)))
                        .font(Theme.readout(32))
                        .foregroundStyle(Theme.foreground)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)

            HStack(spacing: 6) {
                Button {
                    Haptics.trigger(.medium)
                    session.runningSince == nil ? onResume() : onPause()
                } label: {
                    Image(systemName: session.runningSince == nil ? "play.fill" : "pause.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                }
                .buttonStyle(.glassControl(.clear, .circle(diameter: 38)))
                .accessibilityLabel(session.runningSince == nil ? "Resume workout" : "Pause workout")

                Button {
                    Haptics.trigger(.light)
                    onNext?()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(onNext == nil ? Theme.mutedForeground : Theme.foreground)
                }
                .buttonStyle(
                    .glassControl(
                        onNext == nil ? .inert : .clear,
                        .circle(diameter: 38)
                    )
                )
                .disabled(onNext == nil)
                .accessibilityLabel(exercise.map { "Skip \($0.name)" } ?? "Next exercise")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 88)
        .glassSurface(.regular, in: shape)
        .padding(.horizontal, Theme.Metrics.contentInset)
        .padding(.bottom, Theme.Metrics.contentInset)
    }
}
