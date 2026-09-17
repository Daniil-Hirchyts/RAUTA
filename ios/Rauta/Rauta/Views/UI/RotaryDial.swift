import SwiftUI

struct ProfileDial: View {
    private let store = AppStore.shared
    var duration: Bool
    var body: some View {
        RotaryDial(
            value: duration ? store.trainingProfile.profile.preferredSessionDurationMinutes : store.trainingProfile.profile.age,
            range: duration ? ProfileVocabulary.sessionDuration : ProfileVocabulary.profileAge,
            scale: duration ? ProfileVocabulary.sessionDurationScale : ProfileVocabulary.profileAgeScale,
            label: duration ? "Preferred session duration" : "Age", unit: duration ? "minutes" : "years"
        ) { value in
            if duration { store.trainingProfile.updateProfile(.init(preferredSessionDurationMinutes: value)) }
            else { store.trainingProfile.updateProfile(.init(age: value)) }
        }
    }
}

/// Geometry and gesture direction from rotary-knob.tsx's 240 × 84 artboard.
struct RotaryDial: View {
    var value: Double
    var range: NumericRange
    var scale: (min: Double, max: Double)
    var label: String
    var unit: String
    var compact = false
    let onChange: (Double) -> Void
    @State private var dragStart: Double?
    @GestureState private var dragging = false
    private var tickDegrees: Double { min(9, max(3, 96 / ((scale.max - scale.min) / range.step))) }
    private var notch: Double { ((value - scale.min) / range.step).rounded() }
    var body: some View {
        VStack(spacing: compact ? 4 : 8) {
            VStack(spacing: compact ? 4 : 6) {
                Text(Num.trimmed(value)).font(Theme.readout(compact ? 30 : 52)).tracking(-1.56).contentTransition(.numericText())
                Text(unit.uppercased()).font(Theme.sans(compact ? 10 : 12, weight: .bold))
                    .tracking(compact ? 1.4 : 2.16).foregroundStyle(Theme.mutedForeground)
            }.foregroundStyle(Theme.foreground)
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    Canvas { context, size in
                        var ctx = context
                        ctx.scaleBy(x: size.width / 240, y: size.width / 240)
                        draw(in: ctx)
                    }.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 3).updating($dragging) { _, active, _ in
                            active = true
                        }.onChanged { gesture in
                            if dragStart == nil { dragStart = value }
                            let pixels = max(10, 162 * proxy.size.width / 240 * tickDegrees * .pi / 180)
                            commit((dragStart ?? value) - gesture.translation.width / pixels * range.step)
                        }.onEnded { _ in dragStart = nil })
                        // A drag taken over by a scroll is cancelled without
                        // `onEnded`; the next turn must not start from its origin.
                        .onChange(of: dragging) { _, active in if !active { dragStart = nil } }
                    HStack(spacing: 0) { nudge(-1); nudge(1) }.frame(height: proxy.size.height * 0.48)
                }
            }.aspectRatio(240.0 / 84, contentMode: .fit).frame(maxWidth: compact ? 240 : 480)
        }
        .accessibilityElement(children: .contain).accessibilityLabel(label)
        .accessibilityValue("\(Num.trimmed(value)) \(unit)")
        .accessibilityAdjustableAction { commit(value + ($0 == .increment ? range.step : -range.step)) }
    }
    private func draw(in ctx: GraphicsContext) {
        // SVG's radialGradient uses the ellipse's object bounds, so its 100%
        // stop is transparent at every point on the ellipse. A circular Swift
        // radial gradient clipped to an ellipse still has visible colour at
        // the top/bottom edge and exposes the oval as a hard cut. Draw a
        // circular gradient in a vertically scaled context instead: the
        // gradient itself becomes the same 48 × 24 ellipse as React.
        var glowContext = ctx
        glowContext.scaleBy(x: 1, y: 0.5)
        let glow = Path(ellipseIn: CGRect(x: 72, y: 0, width: 96, height: 96))
        let glowGradient = Gradient(stops: [
            .init(color: Theme.primary.opacity(0.34), location: 0),
            .init(color: Theme.primary.opacity(0.12), location: 0.55),
            .init(color: Theme.primary.opacity(0), location: 1),
        ])
        glowContext.fill(
            glow,
            with: .radialGradient(
                glowGradient,
                center: CGPoint(x: 120, y: 48),
                startRadius: 0,
                endRadius: 48
            )
        )
        let count = Int(((scale.max - scale.min) / range.step).rounded())
        for i in 0...max(0, count) {
            let angle = (Double(i) - notch) * tickDegrees
            guard abs(angle) <= 48 else { continue }
            let major = i % 5 == 0
            let tickValue = scale.min + Double(i) * range.step
            let blocked = tickValue < range.min || tickValue > range.max
            let reach = abs(angle) / 48
            let alpha = (major ? 0.85 : 0.45) * (blocked ? 0.3 : 1) * min(1, max(0, (1 - reach) / 0.3))
            func polar(_ radius: Double) -> CGPoint {
                let r = (angle - 90) * .pi / 180
                return CGPoint(x: 120 + radius * cos(r), y: 190 + radius * sin(r))
            }
            var p = Path(); p.move(to: polar(162)); p.addLine(to: polar(major ? 178 : 171))
            let style = StrokeStyle(lineWidth: major ? 1.6 : 1, lineCap: .round)
            ctx.stroke(p, with: .color(Theme.mutedForeground.opacity(alpha)), style: style)
            if !blocked { ctx.stroke(p, with: .color(Theme.primary.opacity(max(0, 1 - reach * 1.8))), style: style) }
        }
        var marker = Path(); marker.move(to: CGPoint(x: 120, y: 5)); marker.addLine(to: CGPoint(x: 120, y: 32))
        ctx.stroke(marker, with: .color(Theme.primary.opacity(0.3)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
        ctx.stroke(marker, with: .linearGradient(Gradient(colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd]), startPoint: CGPoint(x: 120, y: 5), endPoint: CGPoint(x: 120, y: 32)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
    }
    private func nudge(_ direction: Double) -> some View {
        Button { commit(value + direction * range.step) } label: {
            Text(direction < 0 ? "−" : "+").font(Theme.sans(compact ? 18 : 24, weight: .light))
                .foregroundStyle(Theme.foreground.opacity(0.7)).frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(direction < 0 ? value <= range.min : value >= range.max)
            .accessibilityLabel("\(direction < 0 ? "Decrease" : "Increase") \(label.lowercased())")
    }
    private func commit(_ next: Double) {
        let next = range.snap(next); guard next != value else { return }
        onChange(next); Haptics.trigger(.selection)
    }
}
