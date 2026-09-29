import SwiftUI

/// A person's mark, in the app's dot-matrix: a small round field of large dots,
/// some lit in a pattern of their own. Few and big, so the shape reads at a
/// glance. The pattern comes from their name, mirrored left to right the way a
/// face is, so it is theirs, the same on every launch and every device, and
/// changes only if the name does.
///
/// It lights up dot by dot when it appears and then breathes, each lit dot on
/// its own slow beat, like the numerals and RAUTA's light elsewhere.
struct DotMatrixEmblem: View {
    var seed: String
    var size: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared: Date?

    private static let grid = 5

    /// Which dots are lit, row by row, from the name. A pattern with too few
    /// or too many lit is turned inside out, so every mark has a shape.
    private var pattern: [[Bool]] {
        let text = seed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hash = (text.isEmpty ? "you" : text).stableHash
        let half = (Self.grid + 1) / 2
        var rows: [[Bool]] = []
        for _ in 0..<Self.grid {
            var left: [Bool] = []
            for _ in 0..<half {
                hash = hash &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                left.append((hash >> 33) % 100 < 50)
            }
            rows.append(left + left.dropLast().reversed())
        }
        let lit = rows.joined().filter { $0 }.count
        let total = Self.grid * Self.grid
        if lit < total / 4 || lit > total * 3 / 4 {
            rows = rows.map { $0.map { !$0 } }
        }
        return rows
    }

    var body: some View {
        let pattern = pattern
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let since = appeared.map { timeline.date.timeIntervalSince($0) } ?? 10
            Canvas { context, canvasSize in
                draw(pattern, in: context, size: canvasSize, time: t, since: since)
            }
        }
        .frame(width: size, height: size)
        .background(Circle().fill(Theme.primary.opacity(0.12)))
        .overlay(Circle().strokeBorder(Theme.primary.opacity(0.35), lineWidth: 1))
        .clipShape(Circle())
        .onAppear { appeared = reduceMotion ? nil : Date() }
        .accessibilityHidden(true)
    }

    private func draw(_ pattern: [[Bool]], in context: GraphicsContext, size: CGSize, time t: Double, since: Double) {
        let grid = Self.grid
        // Drawn inside the circle with a margin, so the dots at its edge are
        // whole rather than cut by it.
        let inset = size.width * 0.13
        let cell = (size.width - inset * 2) / CGFloat(grid)
        let dot = cell * 0.78
        let centre = CGFloat(grid - 1) / 2
        let radius = centre + 0.45
        for row in 0..<grid {
            for column in 0..<grid {
                let dx = CGFloat(column) - centre
                let dy = CGFloat(row) - centre
                guard dx * dx + dy * dy <= radius * radius else { continue }
                let rect = CGRect(
                    x: inset + CGFloat(column) * cell + (cell - dot) / 2,
                    y: inset + CGFloat(row) * cell + (cell - dot) / 2,
                    width: dot,
                    height: dot
                )
                let lit = pattern[row][column]
                guard lit else {
                    context.fill(Path(ellipseIn: rect), with: .color(Theme.foreground.opacity(0.07)))
                    continue
                }
                // Lighting up from the middle out, then each dot breathing on
                // a phase of its own.
                let distance = Double(sqrt(dx * dx + dy * dy))
                let lightUp = min(1, max(0, (since - distance * 0.12) / 0.35))
                let phase = Double(row * 7 + column * 3)
                let breath = reduceMotion ? 1 : 0.82 + 0.18 * (0.5 + 0.5 * sin(t * 1.3 + phase))
                let colour = Double(row) / Double(grid - 1)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(
                        (colour < 0.5 ? Theme.primaryGradientStart : Theme.primaryGradientEnd)
                            .opacity(0.25 + 0.75 * breath * lightUp)
                    )
                )
            }
        }
    }
}
