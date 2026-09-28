import SwiftUI

struct Flame: View {
    var lit: Bool
    /// Flickers: a lit day's flame, and today's even before it is lit.
    var alive = false
    var phase: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if alive, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 24)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate + phase
                // Two slow waves out of step, so it never settles into a beat.
                let sway = sin(t * 2.3) * 0.5 + sin(t * 3.7) * 0.5
                flame
                    .scaleEffect(
                        x: 1 + 0.025 * sin(t * 3.1),
                        y: 1 + (lit ? 0.05 : 0.025) * sway,
                        anchor: .bottom
                    )
                    .brightness(lit ? 0.04 * sway : 0)
                    .opacity(lit ? 1 : 0.75 + 0.25 * (0.5 + 0.5 * sin(t * 1.6)))
            }
        } else {
            flame
        }
    }

    private var flame: some View {
        ZStack {
            FlameShape()
                .fill(lit ? Theme.rust : Theme.muted)
                .overlay(
                    FlameShape()
                        .strokeBorder(
                            lit ? Theme.ember.opacity(0.72) : Theme.border.opacity(0.55),
                            lineWidth: 1
                        )
                )

            Canvas { context, size in
                var ctx = context
                ctx.scaleBy(x: size.width / 32, y: size.height / 40)

                if lit, let outer = SVGPath.parse(FlameShape.definition) {
                    ctx.fill(
                        outer,
                        with: .linearGradient(
                            Gradient(colors: [
                                Theme.primaryGradientStart.opacity(0.64),
                                Theme.primaryGradientEnd.opacity(0.28)
                            ]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: 0, y: 40)
                        )
                    )
                }

                if lit, let inner = SVGPath.parse("M16.2 15.8c0 4 6.1 6.1 6.1 11a6.2 6.2 0 0 1-12.4 0c0-4.9 6.3-7 6.3-11Z") {
                    ctx.fill(
                        inner,
                        with: .linearGradient(
                            Gradient(colors: [
                                .white.opacity(0.42),
                                Theme.primaryGradientEnd.opacity(0.18)
                            ]),
                            startPoint: CGPoint(x: 16, y: 16),
                            endPoint: CGPoint(x: 16, y: 34)
                        )
                    )
                }

                if lit, let highlight = SVGPath.parse("M13.2 21.6c-1.2 1.6-1.8 3-1.9 4.6") {
                    ctx.stroke(
                        highlight,
                        with: .color(.white.opacity(0.72)),
                        style: StrokeStyle(lineWidth: 1.55, lineCap: .round)
                    )
                }

                if lit, let ember = SVGPath.parse("M17.2 24.3c1.9 1.7 2.7 3.2 2.7 4.8a3.7 3.7 0 0 1-7.4 0c0-1.5 1.2-3.2 4.7-4.8Z") {
                    ctx.fill(ember, with: .color(.white.opacity(0.15)))
                }
            }
            .allowsHitTesting(false)
        }
        .shadow(
            color: lit ? Theme.primary.opacity(0.25) : .clear,
            radius: lit ? 7 : 0,
            y: lit ? 3 : 0
        )
    }
}

/// Pure geometry: `Shape` asks for its path off the main actor.
private nonisolated struct FlameShape: InsettableShape {
    static let definition = "M16.6 1.6c.6 6.4 9.9 10.4 9.9 22.1a10.5 10.5 0 0 1-21 0c0-5.4 2.1-9 4.9-11.9.1 3.1 1.3 5.3 3.1 6.4 1.8-1.7 3-8.6 3.1-16.6Z"

    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        guard let source = SVGPath.parse(Self.definition) else { return Path() }
        let target = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let scaleX = target.width / 32
        let scaleY = target.height / 40
        let transform = CGAffineTransform(translationX: target.minX, y: target.minY)
            .scaledBy(x: scaleX, y: scaleY)
        return source.applying(transform)
    }

    func inset(by amount: CGFloat) -> FlameShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
