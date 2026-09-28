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
