import SwiftUI

/// One entry in the conversation with RAUTA.
///
/// Words are set the way Messages sets them — RAUTA's on the left in the warm
/// grey, the person's on the right in the accent, the last of a run carrying
/// its tail. What RAUTA changed or found arrives as a card lit the way every
/// other card in the app is lit. Only the newest entry arrives with motion.
struct AgentItemView: View {
    let item: AgentItem
    let fresh: Bool
    /// The last bubble of a run from one side carries the tail.
    var tail = true
    let agent: RautaAgent

    var body: some View {
        content.modifier(Arrival(active: fresh, anchor: anchor))
    }

    @ViewBuilder private var content: some View {
        switch item.content {
        case .user(let text):
            AgentUserBubble(text: text, tail: tail)
        case .rauta(let text):
            AgentRautaBubble(text: text, tail: tail)
        case .failure(let text):
            AgentFailureRow(text: text)
        case .card(let card):
            AgentCardView(card: card, itemId: item.id, undo: item.undo, fresh: fresh, agent: agent)
        case .activity:
            EmptyView()
        }
    }

    private var anchor: UnitPoint {
        if case .user = item.content { return .bottomTrailing }
        return .bottomLeading
    }
}

/// A new entry poured in from where it belongs: RAUTA's from its side, the
/// person's from theirs.
private struct Arrival: ViewModifier {
    let active: Bool
    let anchor: UnitPoint
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = shown || !active
        content
            .scaleEffect(visible || reduceMotion ? 1 : 0.92, anchor: anchor)
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 8)
            .onAppear {
                guard active, !shown else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { shown = true }
            }
    }
}

// MARK: - Words

/// A message bubble as Messages cuts one: fully round at a single line, and on
/// the last of a run a tail curling out of the bottom corner on the sender's
/// side. Without the tail the body keeps the same inset, so a run lines up.
nonisolated struct AgentBubbleShape: Shape {
    var tail: Bool
    /// The tail sits bottom right — the person's side.
    var trailing: Bool

    static let tailWidth: CGFloat = 6
    static let radius: CGFloat = 19

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let l = Self.tailWidth
        let r = min(Self.radius, h / 2)
        var p = Path()
        p.move(to: CGPoint(x: l + r, y: 0))
        p.addLine(to: CGPoint(x: w - r, y: 0))
        p.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w, y: r), radius: r)
        p.addLine(to: CGPoint(x: w, y: h - r))
        p.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: w - r, y: h), radius: r)
        if tail {
            // Along the bottom into the tail, out to its tip, and back up the
            // side: the curl Messages draws.
            p.addLine(to: CGPoint(x: l + 15, y: h))
            p.addCurve(to: CGPoint(x: l + 7, y: h - 4),
                       control1: CGPoint(x: l + 15, y: h), control2: CGPoint(x: l + 10, y: h - 0.5))
            p.addCurve(to: CGPoint(x: -1, y: h),
                       control1: CGPoint(x: l + 3, y: h - 1), control2: CGPoint(x: 3, y: h + 0.8))
            p.addLine(to: CGPoint(x: 0, y: h))
            p.addCurve(to: CGPoint(x: l, y: h - min(10, r)),
                       control1: CGPoint(x: 0, y: h), control2: CGPoint(x: l, y: h - 1))
        } else {
            p.addLine(to: CGPoint(x: l + r, y: h))
            p.addArc(tangent1End: CGPoint(x: l, y: h), tangent2End: CGPoint(x: l, y: h - r), radius: r)
        }
        p.addLine(to: CGPoint(x: l, y: r))
        p.addArc(tangent1End: CGPoint(x: l, y: 0), tangent2End: CGPoint(x: l + r, y: 0), radius: r)
        p.closeSubpath()
        guard trailing else { return p.offsetBy(dx: rect.minX, dy: rect.minY) }
        return p
            .applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -w, y: 0))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// How a message's words are set, on either side.
private extension Text {
    func bubbleText() -> some View {
        self
            .font(Theme.sans(16, weight: .medium))
            .tracking(-0.1)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 9)
            .textSelection(.enabled)
    }
}

struct AgentUserBubble: View {
    let text: String
    var tail = true

    var body: some View {
        HStack {
            Spacer(minLength: 64)
            Text(text)
                .bubbleText()
                .foregroundStyle(Theme.primaryForeground)
                .padding(.leading, 14)
                .padding(.trailing, 14 + AgentBubbleShape.tailWidth)
                .background(AgentBubbleShape(tail: tail, trailing: true).fill(Theme.primaryGradient))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You: \(text)")
    }
}

/// RAUTA speaking, in the warm grey Messages keeps for the other side.
struct AgentRautaBubble: View {
    let text: String
    var tail = true

    var body: some View {
        HStack {
            Text(text)
                .bubbleText()
                .foregroundStyle(Theme.foreground)
                .padding(.leading, 14 + AgentBubbleShape.tailWidth)
                .padding(.trailing, 14)
                .background(AgentBubbleShape(tail: tail, trailing: false).fill(Theme.secondary))
            Spacer(minLength: 48)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("RAUTA: \(text)")
    }
}

struct AgentFailureRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.destructive)
                .padding(.top, 1)
            Text(text)
                .font(Theme.sans(14, weight: .medium))
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 4 + AgentBubbleShape.tailWidth)
        .padding(.trailing, 32)
    }
}

/// When a stretch of the conversation happened, centred between turns the way
/// Messages marks them.
struct AgentTimestamp: View {
    let date: Date

    var body: some View {
        Text("\(Text(day).fontWeight(.semibold)) \(date.formatted(date: .omitted, time: .shortened))")
            .font(Theme.sans(12, weight: .medium))
            .foregroundStyle(Theme.mutedForeground)
            .frame(maxWidth: .infinity)
    }

    private var day: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

/// RAUTA at work: what it is doing, with light running through the words.
/// Nothing else — no bubble, no icon, never a percentage.
struct AgentThinkingText: View {
    let text: String

    var body: some View {
        ShimmerText(text: text, font: Theme.sans(15, weight: .semibold))
            .padding(.leading, 6 + AgentBubbleShape.tailWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Words with a band of light sweeping across them, over and over.
struct ShimmerText: View {
    let text: String
    var font: Font
    var period: Double = 1.8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // The band's centre runs from well before the first letter to well
            // past the last, so it enters and leaves cleanly.
            let centre = reduceMotion ? 0.5 : (t.truncatingRemainder(dividingBy: period) / period) * 2.2 - 0.6
            Text(text)
                .font(font)
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: Theme.mutedForeground.opacity(0.55), location: 0),
                            .init(color: Theme.foreground, location: 0.5),
                            .init(color: Theme.mutedForeground.opacity(0.55), location: 1),
                        ],
                        startPoint: UnitPoint(x: centre - 0.35, y: 0.5),
                        endPoint: UnitPoint(x: centre + 0.35, y: 0.5)
                    )
                )
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: text)
        }
    }
}

// MARK: - Cards

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
                AgentAgenda(rows: proposal.rows)
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
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: proposal.state)
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
                AgentAgenda(rows: shown, onOpen: onOpen)
            }

            if shown.count < rows.count {
                AgentCardDivider()
                Button {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { expanded = true }
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

/// Workouts as a calendar's list view draws them: each day once, down the
/// side, with its workouts beside it — what each is, how long it takes, and
/// the exercises in it, pictured and named.
struct AgentAgenda: View {
    let rows: [AgentSessionRow]
    var onOpen: ((String) -> Void)?

    private static let dayColumn: CGFloat = 44

    private var days: [(date: String, rows: [AgentSessionRow])] {
        var order: [String] = []
        var byDay: [String: [AgentSessionRow]] = [:]
        for row in rows {
            if byDay[row.date] == nil { order.append(row.date) }
            byDay[row.date, default: []].append(row)
        }
        return order.map { ($0, byDay[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.date) { index, day in
                if index > 0 { AgentCardDivider(inset: 14) }
                HStack(alignment: .top, spacing: 12) {
                    dayLabel(day.date)
                        .frame(width: Self.dayColumn)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(day.rows.enumerated()), id: \.element.id) { position, row in
                            if position > 0 { AgentCardDivider().padding(.vertical, 12) }
                            workout(row)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
        }
    }

    private func dayLabel(_ date: String) -> some View {
        let today = date == CalendarDate.today
        return VStack(spacing: 0) {
            Text(today ? "TODAY" : CalendarDate.weekdayShort(date).uppercased())
                .font(Theme.sans(10, weight: .black))
                .kerning(today ? 0.4 : 1.2)
                .foregroundStyle(Theme.primary)
            Text(CalendarDate.dayOfMonth(date))
                .font(Theme.sans(24, weight: .black))
                .foregroundStyle(Theme.foreground)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CalendarDate.format(date, "EEEEdMMMM"))
    }

    @ViewBuilder private func workout(_ row: AgentSessionRow) -> some View {
        if let onOpen {
            Button { onOpen(row.id) } label: { workoutBody(row, opens: true) }
                .buttonStyle(.plain)
                .accessibilityHint("Opens this workout")
        } else {
            workoutBody(row, opens: false)
        }
    }

    private func workoutBody(_ row: AgentSessionRow, opens: Bool) -> some View {
        let exercises = row.exerciseIds.compactMap { ExerciseCatalogue.byId[$0] }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.title)
                    .font(Theme.sans(17, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(detail(row))
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
                if opens {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            if !exercises.isEmpty {
                HStack(spacing: 6) {
                    ForEach(exercises.prefix(4), id: \.id) { exercise in
                        ExerciseMediaView(exerciseId: exercise.id)
                            .padding(3)
                            .frame(width: 42, height: 42)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.muted.opacity(0.7)))
                    }
                    if exercises.count > 4 {
                        Text("+\(exercises.count - 4)")
                            .font(Theme.sans(13, weight: .bold))
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(width: 42, height: 42)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.muted.opacity(0.7)))
                    }
                }
                .accessibilityHidden(true)
                Text(exercises.prefix(3).map { Self.name($0) }.joined(separator: " · ")
                     + (exercises.count > 3 ? " …" : ""))
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func detail(_ row: AgentSessionRow) -> String {
        row.minutes > 0 ? "\(row.minutes) min" : Wording.countLabel(row.exerciseIds.count, "exercise")
    }

    static func name(_ exercise: ExerciseSummary) -> String {
        exercise.name.replacingOccurrences(of: "_", with: " ").capitalized
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
                Text(AgentAgenda.name(exercise))
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

extension AgentSessionRow {
    /// The row as the plan screen draws a session.
    var plannedView: PlannedSessionView {
        PlannedSessionView(
            programId: "", sessionId: id, date: date, title: title,
            exerciseIds: exerciseIds, focus: [], workingSets: 0, minutes: minutes, prescription: []
        )
    }
}
