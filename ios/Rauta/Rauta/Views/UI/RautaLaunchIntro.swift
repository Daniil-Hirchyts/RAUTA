import SwiftUI
import UIKit

/// The app opening. RAUTA rises from the foot of the screen on a corkscrew —
/// swinging wider, then spiralling into the middle — turning its body as it
/// goes, growing as it comes forward and dimming on the far side of each loop.
/// A comet ribbon of light streams behind it, shedding specks as it goes, and
/// a shadow floats beneath it so the loops read in depth. It lands in a burst
/// of sparks that slow into embers and drift up, with one quiet ring and a
/// bloom of warm light; its name rises underneath with a gleam passing across
/// it, and then it flies down into its seat in the tab bar while the app
/// appears behind it.
///
/// Every frame is worked out from the time since the start, so the path, the
/// turn and the scale are one continuous motion rather than separate
/// animations that happen to overlap.
struct RautaLaunchIntro: View {
    /// Where RAUTA sits in the tab bar, in global coordinates.
    let seat: CGRect
    let onLanded: () -> Void

    @State private var start: Date?
    @State private var reactionKey = ""

    private static let heroSize: CGFloat = 176

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: start == nil)) { timeline in
                let t = start.map { timeline.date.timeIntervalSince($0) } ?? 0
                frame(at: t, in: proxy.size)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting((start.map { Date().timeIntervalSince($0) } ?? 0) < Timing.flyStart)
        .accessibilityHidden(true)
        .task { await perform() }
    }

    // MARK: One frame

    @ViewBuilder
    private func frame(at t: TimeInterval, in size: CGSize) -> some View {
        let path = SpiralPath(size: size)
        let flight = Timing.flight(t)
        let pose = path.pose(at: flight)
        let flying = Timing.fly(t)
        let seatPoint = seat == .zero ? pose.point : CGPoint(x: seat.midX, y: seat.midY)
        let point = CGPoint(
            x: pose.point.x + (seatPoint.x - pose.point.x) * flying,
            y: pose.point.y + (seatPoint.y - pose.point.y) * flying
        )
        let seatScale = seat == .zero ? pose.scale : seat.width / Self.heroSize
        let scale = pose.scale + (seatScale - pose.scale) * flying
        let fadeOut = 1 - Timing.fadeOut(t)

        ZStack {
            // Everything but RAUTA fades as it flies to its seat; RAUTA itself
            // is handed over to the tab bar's own at the very end.
            ZStack {
                // The launch screen's own colour first, so the system's
                // picture hands over without a seam; the glow gathers as RAUTA
                // arrives and swells when it lands.
                Theme.shell
                RadialGradient(
                    colors: [Theme.primary.opacity(0.34), Theme.oxblood.opacity(0.18), .clear],
                    center: UnitPoint(x: 0.5, y: path.landing.y / max(1, size.height)),
                    startRadius: 0,
                    endRadius: 260 + 120 * Timing.pulse(t)
                )
                .opacity(flight * 0.9 + Timing.pulse(t) * 0.4)

                Canvas { context, _ in
                    if t < Timing.flyStart {
                        drawShadow(context, under: point, pose: pose, scale: scale)
                        drawRibbon(context, path: path, at: t)
                    }
                    drawRing(context, at: path.landing, time: t)
                    drawSparks(context, at: path.landing, time: t)
                }

                title(at: t)
                    .position(x: size.width / 2, y: path.landing.y + Self.heroSize * 0.62)
            }
            .opacity(fadeOut)

            RautaCharacter(
                mood: .happy,
                reactionKey: reactionKey,
                reaction: .celebrate,
                yaw: flying > 0 ? nil : pose.yaw
            )
            .frame(width: Self.heroSize, height: Self.heroSize)
            .scaleEffect(scale)
            .opacity(pose.opacity)
            .position(point)
        }
    }

    private func title(at t: TimeInterval) -> some View {
        let letters = Array("RAUTA")
        let gleam = Timing.gleam(t)
        return HStack(spacing: 10) {
            ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                let shown = Timing.letter(t, index: index)
                Text(String(letter))
                    .font(Theme.sans(46, weight: .black))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.foreground, Theme.primary],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(shown)
                    .offset(y: (1 - shown) * 22)
                    .scaleEffect(0.7 + 0.3 * shown)
                    .blur(radius: (1 - shown) * 8)
            }
        }
        // A band of light passing across the letters once they are up.
        .overlay {
            GeometryReader { proxy in
                LinearGradient(
                    colors: [.clear, .white.opacity(0.85), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: proxy.size.width * 0.35)
                .rotationEffect(.degrees(18))
                .offset(x: -proxy.size.width * 0.4 + proxy.size.width * 1.45 * gleam)
                .blendMode(.plusLighter)
                .opacity(gleam > 0 && gleam < 1 ? 1 : 0)
            }
            .mask {
                HStack(spacing: 10) {
                    ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in
                        Text(String(letter)).font(Theme.sans(46, weight: .black))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: Effects

    /// A soft shadow floating under RAUTA, sized with it: larger and darker on
    /// the near side of a loop, so the spiral reads in depth.
    private func drawShadow(
        _ context: GraphicsContext,
        under point: CGPoint,
        pose: SpiralPath.Pose,
        scale: CGFloat
    ) {
        let width = Self.heroSize * 0.58 * scale
        let y = point.y + Self.heroSize * 0.5 * scale + 10
        var shadow = context
        shadow.opacity = pose.opacity * 0.6
        shadow.addFilter(.blur(radius: 8 + 6 * (1 - scale)))
        shadow.fill(
            Path(ellipseIn: CGRect(x: point.x - width / 2, y: y - width * 0.08, width: width, height: width * 0.16)),
            with: .color(.black)
        )
    }

    private static var warm: [Color] { [.white, Theme.gold, Theme.primary, Theme.ember] }

    /// A cheap, fixed "random" in 0..<1, so every launch draws the same shapes.
    private static func hash(_ n: Double) -> Double {
        let x = sin(n * 12.9898) * 43_758.5453
        return x - x.rounded(.down)
    }

    /// The comet ribbon: the last moment of RAUTA's path as one tapering
    /// stroke — a blurred glow under a bright core, hottest at RAUTA and
    /// cooling to gold as it thins — dimmer where the loop passes behind. It
    /// shrinks by itself as RAUTA slows, and is gone once it lands.
    private func drawRibbon(_ context: GraphicsContext, path: SpiralPath, at t: TimeInterval) {
        guard t > 0.05, t < Timing.landing + 0.3 else { return }
        let window = 0.8
        let steps = 44
        var samples: [(point: CGPoint, pose: SpiralPath.Pose)] = []
        for step in 0...steps {
            let pose = path.pose(at: Timing.flight(t - window * Double(step) / Double(steps)))
            samples.append((pose.point, pose))
        }

        var glow = context
        glow.blendMode = .plusLighter
        glow.addFilter(.blur(radius: 9))
        var core = context
        core.blendMode = .plusLighter

        for index in 0..<steps {
            let head = samples[index]
            let tail = samples[index + 1]
            guard hypot(head.point.x - tail.point.x, head.point.y - tail.point.y) > 0.3 else { continue }
            let along = Double(index) / Double(steps)
            let taper = pow(1 - along, 1.5)
            let segment = Path { path in
                path.move(to: head.point)
                path.addLine(to: tail.point)
            }
            let depth = head.pose.opacity
            glow.stroke(
                segment,
                with: .color(Theme.primary.opacity(0.75 * taper * depth)),
                style: StrokeStyle(lineWidth: 30 * head.pose.scale * taper + 2, lineCap: .round)
            )
            let coreColor = along < 0.25 ? Color.white : (along < 0.6 ? Theme.gold : Theme.primary)
            core.stroke(
                segment,
                with: .color(coreColor.opacity(0.9 * taper * depth)),
                style: StrokeStyle(lineWidth: 7 * head.pose.scale * taper + 0.6, lineCap: .round)
            )
        }

        // Specks shed from the ribbon: they fall a little behind it, drift
        // outward and twinkle out.
        for speck in 0..<18 {
            let seed = Double(speck)
            let born = t - window * (0.15 + 0.85 * Self.hash(seed + 1))
            let age = t - born
            guard born > 0 else { continue }
            let pose = path.pose(at: Timing.flight(born))
            let drift = CGFloat(age) * 38
            let angle = Self.hash(seed + 7) * 2 * .pi
            let point = CGPoint(
                x: pose.point.x + cos(angle) * (drift + 10),
                y: pose.point.y + sin(angle) * (drift + 10) + CGFloat(age) * 14
            )
            let twinkle = 0.5 + 0.5 * sin(t * 22 + seed * 3)
            let life = max(0, 1 - age / window)
            let radius = CGFloat(1.2 + 1.8 * Self.hash(seed + 3)) * pose.scale
            var dot = context
            dot.blendMode = .plusLighter
            dot.opacity = life * twinkle * pose.opacity
            dot.fill(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(Self.warm[speck % 2 == 0 ? 0 : 1])
            )
        }
    }

    /// The landing burst: sparks shooting out as short streaks, slowing
    /// under drag into round embers that rise and twinkle before they go.
    private func drawSparks(_ context: GraphicsContext, at origin: CGPoint, time t: TimeInterval) {
        let age = t - Timing.landing
        let lifetime = 2.1
        guard age > 0, age < lifetime else { return }
        let drag = 3.2
        let slowing = exp(-drag * age)
        let travelled = (1 - slowing) / drag

        var glow = context
        glow.blendMode = .plusLighter
        glow.addFilter(.blur(radius: 5))
        var core = context
        core.blendMode = .plusLighter

        for index in 0..<64 {
            let seed = Double(index)
            let angle = seed / 64 * 2 * .pi + (Self.hash(seed) - 0.5) * 0.35
            let speed = 260 + 420 * Self.hash(seed + 11)
            let rise = CGFloat(pow(age, 1.6) * (26 + 30 * Self.hash(seed + 5)))
            let position = CGPoint(
                x: origin.x + CGFloat(cos(angle) * speed * travelled),
                y: origin.y + CGFloat(sin(angle) * speed * travelled) * 0.82 - rise
            )
            let velocity = CGVector(dx: cos(angle) * speed * slowing, dy: sin(angle) * speed * slowing * 0.82)
            // A streak while it flies, a dot once it has slowed.
            let streak = 0.045
            let tail = CGPoint(x: position.x - velocity.dx * streak, y: position.y - velocity.dy * streak)
            let fade = max(0, min(1, (lifetime - age) / 0.9))
            let twinkle = age < 0.5 ? 1 : 0.55 + 0.45 * sin(age * 18 + seed * 2.3)
            let color = Self.warm[index % Self.warm.count]
            let width = CGFloat(1.6 + 2.2 * Self.hash(seed + 19))

            let line = Path { path in
                path.move(to: tail)
                path.addLine(to: position)
            }
            glow.opacity = fade * twinkle * 0.8
            glow.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: width * 3.2, lineCap: .round))
            core.opacity = fade * twinkle
            core.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
    }

    /// One thin ring easing out from where RAUTA settles.
    private func drawRing(_ context: GraphicsContext, at point: CGPoint, time t: TimeInterval) {
        let age = t - Timing.landing
        guard age > 0, age < 1.1 else { return }
        let progress = age / 1.1
        let eased = 1 - pow(1 - progress, 3)
        let radius = 90 + 150 * eased
        var ring = context
        ring.opacity = (1 - progress) * 0.5
        ring.stroke(
            Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(Theme.primary),
            lineWidth: 1.5
        )
    }

    // MARK: Clock

    private func perform() async {
        // The view is built while the launch screen is still up. The clock
        // starts once the app is really on screen, or the entrance plays to
        // nobody.
        var waited = 0
        while UIApplication.shared.applicationState != .active, waited < 60 {
            try? await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        try? await Task.sleep(for: .milliseconds(120))
        start = Date()
        try? await Task.sleep(for: .seconds(Timing.landing))
        reactionKey = "landed"
        try? await Task.sleep(for: .seconds(Timing.end - Timing.landing))
        onLanded()
    }
}

/// When each part of the intro happens, in seconds from its start.
private enum Timing {
    static let landing: TimeInterval = 2.5
    static let flyStart: TimeInterval = 3.75
    static let flyDuration: TimeInterval = 0.6
    static var end: TimeInterval { flyStart + flyDuration }

    /// How far along the spiral RAUTA is: quick off the mark, easing right
    /// down into the landing.
    static func flight(_ t: TimeInterval) -> Double {
        let x = max(0, min(1, t / landing))
        return 1 - pow(1 - x, 2.6)
    }

    static func fly(_ t: TimeInterval) -> Double {
        let x = max(0, min(1, (t - flyStart) / flyDuration))
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    static func fadeOut(_ t: TimeInterval) -> Double {
        max(0, min(1, (t - flyStart) / (flyDuration * 0.8)))
    }

    /// A swell of light at the landing.
    static func pulse(_ t: TimeInterval) -> Double {
        let age = t - landing
        guard age > 0 else { return 0 }
        return exp(-age * 3) * min(1, age * 12)
    }

    /// The gleam across the name, once its letters have risen.
    static func gleam(_ t: TimeInterval) -> Double {
        let age = t - landing - 0.75
        let x = max(0, min(1, age / 0.55))
        return x == 0 ? 0 : x * x * (3 - 2 * x)
    }

    static func letter(_ t: TimeInterval, index: Int) -> Double {
        let age = t - landing - 0.15 - Double(index) * 0.07
        let x = max(0, min(1, age / 0.38))
        return 1 - pow(1 - x, 3)
    }
}

/// The corkscrew RAUTA rides in on.
private struct SpiralPath {
    let size: CGSize

    /// Where it comes to rest.
    var landing: CGPoint { CGPoint(x: size.width / 2, y: size.height * 0.40) }
    private var launch: CGPoint { CGPoint(x: size.width * 0.46, y: size.height * 1.02) }

    private static let turns = 2.25

    struct Pose {
        var point: CGPoint
        var scale: CGFloat
        var opacity: Double
        /// Degrees of horizontal turn; zero faces the screen.
        var yaw: Double
    }

    /// Where RAUTA is at `progress` along the path, 0 at the foot of the screen,
    /// 1 landed. The loops are a helix seen from a little above: the near side
    /// of each loop sits lower, bigger and brighter than the far side.
    func pose(at progress: Double) -> Pose {
        let p = max(0, min(1, progress))
        let angle = p * Self.turns * 2 * .pi
        // Narrow at the foot, widest halfway up, closing to nothing at the
        // landing so it spirals into place rather than stopping on a loop.
        let width = Double(size.width) * 0.36 * (0.38 + 0.62 * p) * (1 - pow(p, 3.2))
        let depth = cos(angle)
        let rise = 1 - pow(1 - p, 1.4)
        let center = CGPoint(
            x: launch.x + (landing.x - launch.x) * rise,
            y: launch.y + (landing.y - launch.y) * rise
        )
        let point = CGPoint(
            x: center.x + CGFloat(width * sin(angle)),
            y: center.y + CGFloat(width * 0.2 * depth)
        )
        let grow = 0.22 + 0.78 * (1 - pow(1 - p, 2))
        let nearness = 1 + 0.16 * depth * (1 - p)
        let fadeIn = min(1, p / 0.22)
        return Pose(
            point: point,
            scale: CGFloat(grow * nearness),
            opacity: fadeIn * (0.72 + 0.28 * (depth + 1) / 2 * (1 - p) + 0.28 * p),
            // It turns with the path: one full turn of the body per loop,
            // arriving square to the screen.
            yaw: -(1 - p) * Self.turns * 360
        )
    }
}
