import SwiftUI

/// The moment after a workout is saved: RAUTA celebrating what the records
/// actually hold, and one way on.
///
/// It is shown only with a receipt, and a receipt only exists once the save has
/// landed, so nothing here can celebrate work that was not kept.
struct WorkoutCelebration: View {
    let receipt: WorkoutReceipt
    let onContinue: () -> Void

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tileColors: [Color] { [Theme.primary, Theme.gold, Theme.lime] }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            RautaSays(
                text: receipt.rautaLine,
                mood: .proud,
                reaction: .celebrate,
                reactionKey: receipt.id,
                size: 176
            )
            .padding(.horizontal, 28)
            .scaleEffect(shown ? 1 : 0.86)
            .opacity(shown ? 1 : 0)

            VStack(spacing: 6) {
                Text(receipt.workoutName.uppercased())
                    .font(Theme.sans(11, weight: .black))
                    .kerning(1.8)
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                Text(receipt.title)
                    .font(Theme.sans(32, weight: .black))
                    .tracking(-0.8)
                    .foregroundStyle(Theme.foreground)
            }
            .padding(.top, 26)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)

            HStack(spacing: 10) {
                ForEach(Array(receipt.facts.enumerated()), id: \.offset) { index, fact in
                    tile(fact.value, fact.label, color: tileColors[index % tileColors.count])
                        .scaleEffect(shown ? 1 : 0.7)
                        .opacity(shown ? 1 : 0)
                        .animation(
                            reduceMotion
                                ? .easeOut(duration: 0.2)
                                : .spring(response: 0.42, dampingFraction: 0.62)
                                    .delay(0.35 + Double(index) * 0.09),
                            value: shown
                        )
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 20)

            Spacer(minLength: 24)

            AppButton("Continue", size: .cta, expands: true, action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .opacity(shown ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Behind and in front of the page, never part of its layout: the
        // grain is a filled picture larger than the screen.
        .background { background }
        .overlay {
            if !reduceMotion {
                ConfettiBurst(colors: tileColors + [Theme.foreground.opacity(0.85)])
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.74)) {
                shown = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var background: some View {
        Theme.background
            .overlay {
                RadialGradient(
                    colors: [Theme.primary.opacity(0.28), .clear],
                    center: UnitPoint(x: 0.5, y: 0.26),
                    startRadius: 0,
                    endRadius: 360
                )
            }
            .overlay(AppGrain())
            .clipped()
            .ignoresSafeArea()
    }

    /// A result, Duolingo style: the label in a band of colour, the number
    /// under it.
    private func tile(_ value: String, _ label: String, color: Color) -> some View {
        VStack(spacing: 0) {
            Text(label.uppercased())
                .font(Theme.sans(9, weight: .black))
                .kerning(1.2)
                .foregroundStyle(Theme.background)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(color)
            Text(value)
                .font(Theme.sans(22, weight: .black))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.card)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(color, lineWidth: 2)
        )
        .accessibilityElement(children: .combine)
    }
}

/// A single burst of confetti from behind RAUTA, drawn in one canvas and gone
/// in three seconds. Nothing in it can be touched or read.
private struct ConfettiBurst: View {
    let colors: [Color]

    private struct Piece {
        var velocity: CGVector
        var spin: Double
        var angle: Double
        var size: CGSize
        var color: Int
    }

    private static let lifetime: TimeInterval = 3
    private static let gravity: CGFloat = 1_100

    @State private var start = Date()
    @State private var finished = false
    @State private var pieces: [Piece] = (0..<72).map { index in
        Piece(
            velocity: CGVector(dx: .random(in: -430...430), dy: .random(in: -980...(-360))),
            spin: .random(in: -9...9),
            angle: .random(in: 0...(2 * .pi)),
            size: CGSize(width: .random(in: 6...9), height: .random(in: 10...15)),
            color: index
        )
    }

    var body: some View {
        TimelineView(.animation(paused: finished)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                guard elapsed < Self.lifetime else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.24)
                let fade = max(0, min(1, 1 - (elapsed - 1.9) / 1.1))
                let t = CGFloat(elapsed)
                for piece in pieces {
                    var ctx = context
                    ctx.opacity = fade
                    ctx.translateBy(
                        x: origin.x + piece.velocity.dx * t,
                        y: origin.y + piece.velocity.dy * t + 0.5 * Self.gravity * t * t
                    )
                    ctx.rotate(by: .radians(piece.angle + piece.spin * elapsed))
                    let rect = CGRect(
                        x: -piece.size.width / 2, y: -piece.size.height / 2,
                        width: piece.size.width, height: piece.size.height
                    )
                    ctx.fill(
                        Path(roundedRect: rect, cornerRadius: 1.5),
                        with: .color(colors[piece.color % colors.count])
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { start = Date() }
        .task {
            try? await Task.sleep(for: .seconds(Self.lifetime))
            finished = true
        }
    }
}
