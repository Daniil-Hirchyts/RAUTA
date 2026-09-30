import SwiftUI
import UIKit

/// The app opening, in the dot matrix RAUTA's chat is drawn in.
///
/// Stray dots flicker on across the screen like a display waking. A ring
/// closes in from the edges, sweeping them up, and collapses to a point — and
/// RAUTA appears there, turning to face you, as the halo comes up and a
/// shockwave pushes the grid outward. Its name rises underneath with a line
/// saying what the app is for. Last, RAUTA flies down into its seat in the tab
/// bar while the app appears behind it.
///
/// Every frame is worked out from the time since the start, so the whole
/// thing is one continuous motion rather than separate animations that happen
/// to overlap. The light is drawn by `rautaLaunch` in RautaLight.metal.
struct RautaLaunchIntro: View {
    /// Where RAUTA sits in the tab bar, in global coordinates.
    let seat: CGRect
    /// The mood the tab bar's RAUTA is in, so the one that lands there wears
    /// the same face and the handover is seamless.
    var mood: RautaMood = .calm
    let onLanded: () -> Void

    @State private var start: Date?
    /// What RAUTA is feeling right now; starts as the tab bar's mood.
    @State private var feeling: RautaMood?
    @State private var reaction: RautaReaction?
    @State private var reactionKey = ""
    @Environment(\.colorScheme) private var colorScheme

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
        let landing = CGPoint(x: size.width / 2, y: size.height * 0.40)
        let flying = Timing.fly(t)
        let seatPoint = seat == .zero ? landing : CGPoint(x: seat.midX, y: seat.midY)
        let point = CGPoint(
            x: landing.x + (seatPoint.x - landing.x) * flying,
            y: landing.y + (seatPoint.y - landing.y) * flying
        )
        let heroScale = Timing.arrive(t)
        let seatScale = seat == .zero ? 1 : seat.width / Self.heroSize
        let scale = heroScale + (seatScale - heroScale) * flying
        let fadeOut = 1 - Timing.fadeOut(t)

        ZStack {
            // Everything but RAUTA fades as it flies to its seat; RAUTA itself
            // is handed over to the tab bar's own at the very end.
            ZStack {
                light(at: t, source: landing)
                name(at: t, in: size, below: landing)
            }
            .opacity(fadeOut)

            // Feelings are kept off the turn: a clip cutting into it reads as a
            // jump. See `perform()` for when they come.
            RautaCharacter(
                mood: feeling ?? mood,
                reactionKey: reactionKey,
                reaction: reaction,
                yaw: flying > 0 ? nil : Timing.turn(t)
            )
            .frame(width: Self.heroSize, height: Self.heroSize)
            .scaleEffect(max(0.01, scale))
            .opacity(Timing.appear(t))
            .position(point)
        }
    }

    /// The dot matrix, laid over the launch screen's own colour and starting
    /// from nothing, so the system's picture hands over without a seam.
    private func light(at t: TimeInterval, source: CGPoint) -> some View {
        let lightMode = colorScheme == .light
        let glow = Theme.primary
        let ink = lightMode ? Theme.primary : Theme.primarySoft
        let strength: Float = lightMode ? 0.4 : 0.62
        let wake = Timing.wake(t), gather = Timing.gather(t)
        let light = Timing.light(t), pulse = Timing.pulse(t)
        return Rectangle()
            .fill(Theme.shell)
            .visualEffect { view, proxy in
                view.colorEffect(ShaderLibrary.rautaLaunch(
                    .float2(proxy.size),
                    .float2(source),
                    .float(t),
                    .float(wake),
                    .float(gather),
                    .float(light),
                    .float(pulse),
                    .color(glow),
                    .color(ink),
                    .float(strength)
                ))
            }
    }

    /// RAUTA's name, its letters rising in one after another, and a line
    /// underneath saying what the app is for.
    private func name(at t: TimeInterval, in size: CGSize, below landing: CGPoint) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ForEach(Array("RAUTA".enumerated()), id: \.offset) { index, letter in
                    let shown = Timing.letter(t, index: index)
                    Text(String(letter))
                        .font(Theme.sans(46, weight: .black))
                        .foregroundStyle(Theme.foreground)
                        .opacity(shown)
                        .offset(y: (1 - shown) * 16)
                        .blur(radius: (1 - shown) * 6)
                }
            }
            // Set like the app's own section labels; the letters open out as
            // the line fades in.
            let subtitle = Timing.subtitle(t)
            Text("TRAINING THAT FITS YOUR WEEK")
                .font(Theme.sans(11, weight: .black))
                .kerning(1 + 1.6 * subtitle)
                .foregroundStyle(Theme.primary)
                .opacity(subtitle)
        }
        .fixedSize()
        .position(x: size.width / 2, y: landing.y + Self.heroSize * 0.62 + 18)
    }

    // MARK: Clock

    private func react(_ next: RautaReaction) {
        reaction = next
        reactionKey = next.rawValue
    }

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
        let start = Date()
        self.start = start
        // The whole entrance as one phrase, so every note lands on its frame.
        var rng = SystemRandomNumberGenerator()
        WorkoutAudio.play(
            RautaPhrase.launch(arrival: Timing.arrival, landing: Timing.end, using: &rng),
            level: 0.22, felt: 0.8
        )
        func at(_ time: TimeInterval) async {
            try? await Task.sleep(for: .seconds(max(0, time - Date().timeIntervalSince(start))))
        }

        // It arrives in the tab bar's mood and turns to face you. Only once it
        // is facing you does it warm up — the shift comes with a blink — and
        // nod hello as its name rises.
        await at(Timing.arrival + 0.5)
        feeling = .happy
        await at(Timing.arrival + 0.7)
        react(.acknowledge)
        // It settles back into the tab bar's mood on the way down, so the one
        // waiting there wears the same face when it takes over.
        await at(Timing.flyStart + 0.1)
        feeling = nil
        await at(Timing.end)
        onLanded()
    }
}

/// When each part of the intro happens, in seconds from its start.
private enum Timing {
    static let gatherStart: TimeInterval = 0.35
    /// The ring collapses and RAUTA appears.
    static let arrival: TimeInterval = 1.4
    static let flyStart: TimeInterval = 3.4
    static let flyDuration: TimeInterval = 0.6
    static var end: TimeInterval { flyStart + flyDuration }

    private static func clamp(_ x: Double) -> Double { max(0, min(1, x)) }
    private static func smooth(_ x: Double) -> Double { let x = clamp(x); return x * x * (3 - 2 * x) }

    /// The stray dots coming on.
    static func wake(_ t: TimeInterval) -> Double { smooth(t / 0.5) }

    /// The ring closing in: slow off the edges, quickening as it draws tight.
    static func gather(_ t: TimeInterval) -> Double {
        guard t > gatherStart else { return 0 }
        return pow(clamp((t - gatherStart) / (arrival - gatherStart)), 2.2)
    }

    /// The halo coming up out of the collapse.
    static func light(_ t: TimeInterval) -> Double { smooth((t - arrival + 0.12) / 0.5) }

    /// The shockwave leaving RAUTA; 1 when there is none.
    static func pulse(_ t: TimeInterval) -> Double {
        t < arrival ? 1 : clamp((t - arrival) / 1.5)
    }

    /// RAUTA's size as it appears: a spring from a point, past full size and
    /// back.
    /// RAUTA's size as it appears: grown out of the collapse, a touch past
    /// full size and settling back, critically damped so it never wobbles.
    static func arrive(_ t: TimeInterval) -> Double {
        let age = max(0, t - arrival + 0.1)
        let grow = 1 - (1 + age * 9) * exp(-age * 9)
        let settle = 0.05 * sin(clamp(age / 0.7) * .pi)
        return 0.55 + 0.45 * grow + settle
    }

    static func appear(_ t: TimeInterval) -> Double { smooth((t - arrival + 0.1) / 0.3) }

    /// RAUTA turning to face you as it appears, easing all the way in.
    static func turn(_ t: TimeInterval) -> Double {
        let x = clamp((t - arrival + 0.1) / 1.1)
        return -80 * pow(1 - x, 3)
    }

    static func letter(_ t: TimeInterval, index: Int) -> Double {
        let x = clamp((t - arrival - 0.3 - Double(index) * 0.06) / 0.42)
        return 1 - pow(1 - x, 3)
    }

    static func subtitle(_ t: TimeInterval) -> Double {
        smooth((t - arrival - 0.85) / 0.5)
    }

    static func fly(_ t: TimeInterval) -> Double {
        let x = clamp((t - flyStart) / flyDuration)
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    static func fadeOut(_ t: TimeInterval) -> Double {
        clamp((t - flyStart) / (flyDuration * 0.8))
    }
}
