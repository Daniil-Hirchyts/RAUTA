import SwiftUI

/// RAUTA's light behind the chat: RAUTA is the source, and a dot-matrix halo
/// — the dots the app sets its big numbers in — falls from it over a warm
/// wash. A lower light rises from the field and brightens while you talk.
///
/// At rest the halo breathes; while RAUTA thinks, light is drawn in toward it
/// and the dots twinkle; when the answer lands, one pulse travels out. Each is
/// eased in and out by ``RautaLightClock``, so one state flows into the next.
/// Drawn by `rautaLight` in RautaLight.metal.
struct RautaChatBackdrop: View {
    var thinking = false
    var listening = false
    /// A count of answers; each new one sends a pulse.
    var answers = 0
    /// Where RAUTA sits, in screen points.
    var source: CGPoint
    /// How far the progressive blur reaches from the top and the bottom.
    var blurTop: CGFloat
    var blurBottom: CGFloat

    @State private var clock = RautaLightClock()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // At rest the light only breathes, and 20 frames a second is plenty;
        // thinking and the answer's pulse move faster and get 30.
        TimelineView(.animation(minimumInterval: thinking ? 1 / 30 : 1 / 20, paused: reduceMotion)) { timeline in
            let light = clock.step(to: timeline.date, thinking: thinking && !reduceMotion,
                                   listening: listening, answers: answers)
            let lightMode = colorScheme == .light
            let glow = Theme.primary
            let ink = lightMode ? Theme.primary : Theme.primarySoft
            let strength: Float = lightMode ? 0.4 : 0.62
            let source = source, blurTop = blurTop, blurBottom = blurBottom
            Rectangle()
                .fill(Theme.background)
                .visualEffect { view, proxy in
                    view.colorEffect(ShaderLibrary.rautaLight(
                        .float2(proxy.size),
                        .float2(source),
                        .float(light.time),
                        .float(light.think),
                        .float(light.flow),
                        .float(light.pulse),
                        .float(light.bottom),
                        .float(blurTop),
                        .float(blurBottom),
                        .color(glow),
                        .color(ink),
                        .float(strength)
                    ))
                }
        }
    }
}

/// The backdrop's clocks and weights, stepped once a frame.
///
/// Frames arrive late whenever the main thread is busy — while RAUTA's tools
/// run, say. Each step moves the light on by at most one short frame, so a
/// hitch slows it for a moment instead of freezing it and then jumping ahead.
/// Weights ease toward their targets, so thinking, answering and resting blend.
@MainActor
final class RautaLightClock {
    struct Light: Sendable {
        var time = 0.0
        var think = 0.0
        var flow = 0.0
        var pulse = 1.0
        var bottom = 0.3
    }

    private var light = Light()
    private var last: Date?
    private var answers: Int?

    func step(to now: Date, thinking: Bool, listening: Bool, answers: Int) -> Light {
        let dt = min(max(now.timeIntervalSince(last ?? now), 0), 1.0 / 15)
        last = now
        if let seen = self.answers, answers != seen { light.pulse = 0 }
        self.answers = answers

        // Both clocks wrap where every wave they drive comes back to its start.
        light.time = (light.time + dt).truncatingRemainder(dividingBy: 2 * .pi * 200)
        light.think += ((thinking ? 1 : 0) - light.think) * (1 - exp(-dt / 0.6))
        light.flow = (light.flow + dt * light.think).truncatingRemainder(dividingBy: 2 * .pi * 100 / 3.4)
        light.bottom += ((listening ? 0.7 : 0.3) - light.bottom) * (1 - exp(-dt / 0.3))
        if light.pulse < 1 { light.pulse = min(1, light.pulse + dt / 1.8) }
        return light
    }
}
