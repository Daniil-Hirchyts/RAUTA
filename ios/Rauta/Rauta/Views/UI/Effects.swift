import SwiftUI

/// A count whose digits pop in when it changes.
///
/// Arriving is not changing. A number that is simply the first thing a page puts
/// on screen has not come from anywhere, and animating it into place makes the
/// page look like it is still settling. So the first value is drawn at rest, and
/// only the ones that replace it move.
struct AnimatedNumber: View {
    var value: Int
    var format: (Int) -> String = { String($0) }
    /// This change is not one to animate. A dial passing over a notch a frame
    /// restarts the pop before it has played, so while it is being turned the
    /// number stays put and legible.
    var still: Bool = false

    @State private var shown: Int?
    @State private var changed = false

    private var text: String { format(value) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .monospacedDigit()
                    .modifier(DigitPop(
                        active: changed,
                        // The last two characters trail the ones before them, so
                        // a rising count reads left to right.
                        delay: staggerDelay(index)
                    ))
                    .id("\(text)-\(index)")
            }
        }
        .accessibilityLabel(text)
        .onChange(of: value) { _, _ in
            changed = !still
            shown = value
        }
        .onAppear { shown = value }
    }

    private func staggerDelay(_ index: Int) -> Double {
        let count = text.count
        if index == count - 1 { return Theme.Duration.digitStagger * 2 }
        if index == count - 2 { return Theme.Duration.digitStagger }
        return 0
    }
}

private struct DigitPop: ViewModifier {
    var active: Bool
    var delay: Double

    @State private var progress: Double = 1

    func body(content: Content) -> some View {
        content
            .offset(y: (1 - progress) * 8)
            .opacity(progress)
            .blur(radius: (1 - progress) * 2)
            .onAppear {
                guard active else { return }
                progress = 0
                withAnimation(
                    .timingCurve(0.34, 1.45, 0.64, 1, duration: Theme.Duration.digit)
                        .delay(delay)
                ) { progress = 1 }
            }
    }
}

/// A circle that draws its tick when it becomes checked and erases it when it
/// does not.
struct AnimatedCheck: View {
    var checked: Bool
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .fill(checked ? AnyShapeStyle(Theme.primaryGradient) : AnyShapeStyle(Color.clear))
                .overlay(
                    Circle().strokeBorder(
                        checked ? Theme.primary.opacity(0.8) : Theme.border, lineWidth: 1
                    )
                )
            CheckMark()
                .trim(from: 0, to: checked ? 1 : 0)
                .stroke(
                    checked ? Theme.primaryForeground : Theme.mutedForeground,
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                )
                .frame(width: size * 0.5, height: size * 0.5)
        }
        .frame(width: size, height: size)
        .animation(Theme.Motion.smoothOut(Theme.Duration.checkDraw), value: checked)
    }
}

private struct CheckMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return path
    }
}

/// The heart, with the burst it earns the first time it is filled.
struct LikeButton: View {
    var liked: Bool
    /// Set false to skip the pop and burst — for a toggle that filters a view
    /// rather than "liking" something.
    var animated: Bool = true
    var label: String
    var size: CGFloat = 32
    var iconSize: CGFloat = 16
    var chromeless: Bool = false
    var action: () -> Void

    @State private var bursting = false
    @State private var pop: CGFloat = 1

    private static let particles: [(x: CGFloat, y: CGFloat, delay: Double, size: CGFloat)] = [
        (0, -21, 0, 0.85), (15, -15, 0.018, 1.1), (22, 0, 0.005, 0.75),
        (15, 15, 0.024, 1), (0, 21, 0.010, 0.8), (-15, 15, 0.028, 1.05),
        (-22, 0, 0.008, 0.8), (-15, -15, 0.020, 0.95),
    ]

    var body: some View {
        let button = Button {
            if !liked && animated { burst() }
            Haptics.trigger(.selection)
            action()
        } label: {
            heartContent
        }

        Group {
            if chromeless {
                button
                    .buttonStyle(.plain)
            } else {
                button
                    .buttonStyle(
                        .glassControl(
                            liked ? .tinted(Theme.primary.opacity(0.28)) : .clear,
                            .circle(diameter: size)
                        )
                    )
            }
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(liked ? [.isSelected] : [])
    }

    @ViewBuilder
    private var heartContent: some View {
        let content = ZStack {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .scaleEffect(pop)

                if bursting {
                    ForEach(Array(Self.particles.enumerated()), id: \.offset) { _, particle in
                        Circle()
                            .fill(Theme.primary)
                            .frame(width: 2.5 * particle.size, height: 2.5 * particle.size)
                            .offset(
                                x: bursting ? particle.x : 0,
                                y: bursting ? particle.y : 0
                            )
                            .opacity(bursting ? 0 : 1)
                            .animation(
                                .easeOut(duration: 0.6).delay(particle.delay), value: bursting
                            )
                    }
                }
            }

        if chromeless {
            content
                .frame(width: size, height: size)
                .contentShape(Circle())
        } else {
            // The glass style cuts the pane to `size` itself.
            content
        }
    }

    private func burst() {
        bursting = true
        withAnimation(.timingCurve(0.34, 1.96, 0.64, 1, duration: 0.35)) { pop = 1.35 }
        Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            withAnimation(Theme.Motion.spring) { pop = 1 }
            try? await Task.sleep(nanoseconds: 500_000_000)
            bursting = false
        }
    }
}

/// How far through a short sequence of pages you are. Shared by the exercise
/// picker and by first-run setup, so a multi-step flow always reports itself the
/// same way.
struct FlowProgress: View {
    var stage: Int
    var steps: Int = 3

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...Swift.max(1, steps), id: \.self) { step in
                Color.clear
                    .frame(width: step == stage ? 28 : 14, height: 4)
                    .glassSurface(
                        tone(step),
                        in: Capsule()
                    )
                    .overlay {
                        if step == stage {
                            Capsule()
                                .fill(Theme.primaryGradient)
                                .opacity(Theme.Glassware.primaryWash)
                        } else if step < stage {
                            Capsule()
                                .fill(Theme.primary)
                                .opacity(0.12)
                        }
                    }
                    .clipShape(Capsule())
            }
        }
        .animation(Theme.Motion.smoothOut, value: stage)
        .accessibilityLabel("Step \(stage) of \(steps)")
    }

    private func tone(_ step: Int) -> GlassTone {
        if step == stage { return .tinted(Theme.primary) }
        if step < stage { return .tinted(Theme.primary.opacity(0.28)) }
        return .clear
    }
}

/// A label that crossfades and lifts when its text changes.
struct TextSwap: View {
    var text: String
    var font: Font
    var color: Color = Theme.foreground

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .id(text)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 4)),
                    removal: .opacity.combined(with: .offset(y: -4))
                )
            )
            .animation(.easeInOut(duration: Theme.Duration.textSwap), value: text)
    }
}

/// The frosted panel every modal, dock and floating control is made of.
struct FrostedBackground: View {
    var cornerRadius: CGFloat = Theme.Radius.xl2
    var compact: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.popover.opacity(compact ? 0.5 : 0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}
