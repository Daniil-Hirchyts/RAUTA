import SwiftUI

struct AgentCardView: View {
    let card: AgentCard
    let itemId: UUID
    let undo: AgentItem.UndoState?
    let fresh: Bool
    let agent: RautaAgent

    var body: some View {
        switch card {
        case .change(let title, let detail, let systemImage):
            AgentChangeCard(title: title, detail: detail, systemImage: systemImage, undo: undo) {
                Task { await agent.undo(itemId) }
            }
        case .proposal(let proposal):
            AgentProposalCardView(proposal: proposal, fresh: fresh, agent: agent)
        case .sessions(let title, let rows):
            AgentSessionsCard(title: title, rows: rows, fresh: fresh) { agent.openWorkout($0) }
        case .exercises(let title, let ids):
            AgentExercisesCard(title: title, ids: ids) { agent.openExercise($0) }
        case .facts(let title, let lines):
            AgentFactsCard(title: title, lines: lines)
        case .permission(let permission):
            AgentPermissionCard(permission: permission) {
                Task { await agent.grant(permission) }
            }
        case .download:
            AgentDownloadCard()
        }
    }
}

/// An icon in a small lit disc, the mark every agent card leads with.
struct AgentIcon: View {
    let systemImage: String
    var tint: Color = Theme.primary

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(Circle().fill(tint.opacity(0.16)))
            .accessibilityHidden(true)
    }
}

/// A title above a card's contents, in the voice of the app's section labels.
private struct AgentCardTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.sans(11, weight: .black))
            .kerning(1.2)
            .foregroundStyle(Theme.primary)
            .padding(.leading, 4)
    }
}

/// Something RAUTA already changed, with the way back while there is one.
struct AgentChangeCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let undo: AgentItem.UndoState?
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AgentIcon(systemImage: undo == .undone ? "arrow.uturn.backward" : systemImage,
                      tint: undo == .undone ? Theme.mutedForeground : Theme.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(undo == .undone ? "\(title) — undone" : title)
                    .font(Theme.sans(15, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                Text(detail)
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(3)
                    .strikethrough(undo == .undone, color: Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if undo == .available {
                Button(action: onUndo) {
                    Text("Undo")
                        .font(Theme.sans(15, weight: .bold))
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 6)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo \(title.lowercased())")
            }
        }
        .padding(14)
        .background { GradientCard(radius: Theme.Radius.xl, accent: Theme.primary, strength: undo == .undone ? 0.2 : 0.6) }
        .accessibilityElement(children: .contain)
    }
}

/// A change waiting for a yes: what it is, the week it makes, and the two
/// ways out. Nothing is written until Apply.
struct AgentProposalCardView: View {
    let proposal: AgentProposalCard
    let fresh: Bool
    let agent: RautaAgent

    private var accent: Color { proposal.destructive ? Theme.destructive : Theme.primary }

    private var icon: String {
        if proposal.destructive { return "exclamationmark.triangle" }
        if proposal.title.localizedCaseInsensitiveContains("calendar") { return "calendar.badge.plus" }
        if proposal.title.localizedCaseInsensitiveContains("finish") { return "flag.checkered" }
        return proposal.rows.count > 1 ? "calendar.badge.clock" : "sparkles"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(14)

            if !proposal.rows.isEmpty, proposal.state != .dismissed {
                AgentCardDivider()
                WorkoutAgenda(rows: proposal.rows)
            }

            switch proposal.state {
            case .pending:
                HStack(spacing: 10) {
                    AppButton(
                        proposal.applyTitle,
                        variant: proposal.destructive ? .destructive : .primary,
                        expands: true
                    ) {
                        Haptics.trigger(.medium)
                        Task { await agent.apply(proposal.id) }
                    }
                    AppButton("Not now", variant: .ghost) { agent.dismiss(proposal.id) }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .padding(.top, proposal.rows.isEmpty ? 0 : 6)
            case .expired:
                Text("This preview is out of date. Ask me again for a fresh one.")
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            case .applied, .dismissed:
                EmptyView()
            }
        }
        .background { GradientCard(radius: Theme.Radius.xl, accent: accent, strength: 0.8) }
        .opacity(proposal.state == .dismissed || proposal.state == .expired ? 0.65 : 1)
        .animation(Theme.Motion.settleQuick, value: proposal.state)
    }

    private var header: some View {
        HStack(spacing: 12) {
            AgentIcon(systemImage: icon, tint: accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.title)
                    .font(Theme.sans(17, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                Text(proposal.detail)
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            stateBadge
        }
    }

    @ViewBuilder private var stateBadge: some View {
        switch proposal.state {
        case .applied:
            Label("Applied", systemImage: "checkmark.circle.fill")
                .font(Theme.sans(13, weight: .bold))
                .foregroundStyle(Theme.success)
        case .dismissed:
            Text("Not now")
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(Theme.mutedForeground)
        case .expired:
            Text("Expired")
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(Theme.mutedForeground)
        case .pending:
            EmptyView()
        }
    }
}

/// Workouts RAUTA looked up, laid out as an agenda; each opens its workout.
struct AgentSessionsCard: View {
    let title: String
    let rows: [AgentSessionRow]
    let fresh: Bool
    let onOpen: (String) -> Void
    /// A long list starts folded so the conversation around it stays in view.
    @State private var expanded = false
    private static let folded = 4

    private var shown: [AgentSessionRow] {
        expanded || rows.count <= Self.folded + 1 ? rows : Array(rows.prefix(Self.folded))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(Theme.sans(11, weight: .black))
                    .kerning(1.2)
                    .foregroundStyle(Theme.primary)
                Spacer()
                Text(Wording.countLabel(rows.count, "workout"))
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            AgentCardDivider()
            if rows.isEmpty {
                Text("Nothing planned yet.")
                    .font(Theme.sans(15, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(14)
            } else {
                WorkoutAgenda(rows: shown, onOpen: onOpen)
            }

            if shown.count < rows.count {
                AgentCardDivider()
                Button {
                    withAnimation(Theme.Motion.settleQuick) { expanded = true }
                } label: {
                    HStack(spacing: 6) {
                        Text("Show all \(rows.count)")
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                    }
                    .font(Theme.sans(14, weight: .bold))
                    .foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background { GradientCard(radius: Theme.Radius.xl, accent: Theme.primary, strength: 0.6) }
    }
}

/// A hairline between the parts of a card.
struct AgentCardDivider: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Theme.border.opacity(0.6))
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// Exercises from the library, each opening its own page.
struct AgentExercisesCard: View {
    let title: String
    let ids: [String]
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AgentCardTitle(text: title)
            VStack(spacing: 0) {
                ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                    if let exercise = ExerciseCatalogue.byId[id] {
                        Button { onOpen(id) } label: { row(exercise) }
                            .buttonStyle(.plain)
                        if index < ids.count - 1 {
                            Divider().overlay(Theme.border.opacity(0.4)).padding(.leading, 80)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .background { GradientCard(radius: Theme.Radius.xl, accent: Theme.primary, strength: 0.5) }
        }
    }

    private func row(_ exercise: ExerciseSummary) -> some View {
        HStack(spacing: 12) {
            ExerciseMediaView(exerciseId: exercise.id)
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(WorkoutAgenda.name(exercise))
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(2)
                Text([Wording.titleCase(exercise.equipment), exercise.primaryMuscle?.label].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.mutedForeground)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this exercise")
    }
}

/// Figures RAUTA read off the history or Health: each "label: value" line is
/// set as a row, anything else as a sentence.
struct AgentFactsCard: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.sans(17, weight: .bold))
                .foregroundStyle(Theme.foreground)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    if let split = line.range(of: ": ") {
                        HStack(alignment: .firstTextBaseline) {
                            Text(line[..<split.lowerBound])
                                .font(Theme.sans(14, weight: .medium))
                                .foregroundStyle(Theme.mutedForeground)
                            Spacer(minLength: 12)
                            Text(line[split.upperBound...])
                                .font(Theme.sans(15, weight: .bold))
                                .foregroundStyle(Theme.foreground)
                                .multilineTextAlignment(.trailing)
                        }
                    } else {
                        Text(line)
                            .font(Theme.sans(14, weight: .medium))
                            .foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background { GradientCard(radius: Theme.Radius.xl, accent: Theme.primary, strength: 0.7) }
    }
}

/// What RAUTA would read, why, and the one button that asks iOS.
struct AgentPermissionCard: View {
    let permission: AgentPermission
    let onAllow: () -> Void

    private var copy: (icon: String, tint: Color, title: String, detail: String, button: String) {
        switch permission {
        case .health:
            ("heart.fill", Theme.destructive, "Sleep and heart trends",
             "With Health access I can see last night's sleep and your resting heart rate and HRV, and plan around them.",
             "Allow Health access")
        case .calendar:
            ("calendar", Theme.primary, "Your calendar",
             "With Calendar access I can find free times and put workouts in your calendar when you say so.",
             "Allow Calendar access")
        case .notifications:
            ("bell.badge.fill", Theme.gold, "Workout reminders",
             "With notifications on I can remind you before a workout, with Start and Move buttons.",
             "Allow notifications")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AgentIcon(systemImage: copy.icon, tint: copy.tint)
                Text(copy.title)
                    .font(Theme.sans(17, weight: .bold))
                    .foregroundStyle(Theme.foreground)
            }
            Text(copy.detail)
                .font(Theme.sans(14, weight: .medium))
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            AppButton(copy.button, expands: true, action: onAllow)
        }
        .padding(16)
        .background { GradientCard(radius: Theme.Radius.xl, accent: copy.tint, strength: 0.7) }
    }
}

/// RAUTA without its model: what it needs, how big it is, and the download.
struct AgentDownloadCard: View {
    private let model = AgentModelStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AgentIcon(systemImage: "brain.head.profile")
                VStack(alignment: .leading, spacing: 2) {
                    Text("RAUTA's brain")
                        .font(Theme.sans(17, weight: .bold))
                        .foregroundStyle(Theme.foreground)
                    Text("Runs on your iPhone. Your training never leaves it.")
                        .font(Theme.sans(13, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }

            if model.downloading {
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.muted.opacity(0.5))
                            Capsule()
                                .fill(Theme.primaryGradient)
                                .frame(width: max(10, proxy.size.width * model.progress))
                        }
                    }
                    .frame(height: 8)
                    .animation(.easeOut(duration: 0.3), value: model.progress)
                    HStack {
                        Text(model.status)
                        Spacer()
                        Button("Cancel") { model.cancelDownload() }
                            .foregroundStyle(Theme.primary)
                    }
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
                }
            } else {
                #if targetEnvironment(simulator)
                Text("The simulator thinks with Apple's on-device model when it is available.")
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                #else
                if let error = model.error {
                    Text(error)
                        .font(Theme.sans(13, weight: .medium))
                        .foregroundStyle(Theme.destructive)
                }
                AppButton("Download · 1.75 GB", expands: true) { model.download() }
                Text("Wi-Fi recommended. Needs about 2.3 GB free.")
                    .font(Theme.sans(12, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                #endif
            }
        }
        .padding(16)
        .background { GradientCard(radius: Theme.Radius.xl, accent: Theme.primary, strength: 0.9) }
    }
}
