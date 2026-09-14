import SwiftUI

// MARK: - Switch

/// The system switch, in the brand's colour.
///
/// On iOS 26 its thumb is Liquid Glass: it lifts into a lens under a finger and
/// can be dragged across. A drawn imitation can only fake the resting state.
struct AppSwitch: View {
    @Binding var isOn: Bool
    var isDisabled: Bool = false
    var label: String = ""

    var body: some View {
        Toggle(label, isOn: Binding(
            get: { isOn },
            set: { value in
                guard !isDisabled, value != isOn else { return }
                Haptics.trigger(.selection)
                withAnimation(Theme.Motion.smoothOut(0.2)) { isOn = value }
            }
        ))
        .toggleStyle(.switch)
        .labelsHidden()
        .tint(Theme.primary)
        .disabled(isDisabled)
    }
}

// MARK: - Text field

struct AppTextField: View {
    var placeholder: String
    @Binding var text: String
    var isDisabled: Bool = false
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)?

    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .focused($focused)
            .disabled(isDisabled)
            .font(Theme.sans(16))
            .foregroundStyle(Theme.foreground)
            .tint(Theme.primary)
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Theme.input.opacity(0.5), in: Capsule())
            .overlay(Capsule().strokeBorder(focused ? Theme.ring : .clear, lineWidth: 1))
            .animation(Theme.Motion.smoothOut(0.2), value: focused)
            .opacity(isDisabled ? 0.5 : 1)
    }
}

// MARK: - Stepper

/// How long a held button waits before it starts repeating, and how quickly the
/// repeats close up. Getting from an empty bar to 80 kg is a hold, not thirty-two
/// taps — but a single deliberate tap must still be a single step.
private let firstRepeatSeconds: Double = 0.42
private let repeatDecay: Double = 0.72
private let fastestRepeatSeconds: Double = 0.06

private struct StepButton: View {
    var systemImage: String
    var label: String
    var isDisabled: Bool
    var onStep: () -> Void

    @State private var repeatTask: Task<Void, Never>?
    @State private var isPressed = false

    var body: some View {
        let shape = Circle()

        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Theme.primary)
            .frame(width: 48, height: 48)
            .glassSurface(
                isDisabled ? .inert : .regular,
                in: shape,
                interactive: !isDisabled,
                border: Theme.Glassware.controlEdge,
                legacyFill: Theme.card
            )
            .opacity(isDisabled ? 0.35 : 1)
            .scaleEffect(isPressed && !Theme.Glassware.supportsLiquidGlass ? 0.94 : 1)
            .animation(Theme.Motion.spring, value: isPressed)
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isDisabled, repeatTask == nil else { return }
                        isPressed = true
                        start()
                    }
                    .onEnded { _ in
                        isPressed = false
                        stop()
                    }
            )
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    private func start() {
        step()
        repeatTask = Task {
            var delay = firstRepeatSeconds
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled { break }
                await MainActor.run { step() }
                delay = Swift.max(fastestRepeatSeconds, delay * repeatDecay)
            }
        }
    }

    private func stop() {
        repeatTask?.cancel()
        repeatTask = nil
    }

    private func step() {
        Haptics.trigger(.selection)
        onStep()
    }
}

/// A number nudged rather than typed.
///
/// Mid-set, a keyboard is the wrong instrument: it covers the screen to collect
/// two digits that only ever move by one plate or one rep. The buttons are the
/// whole control, and they repeat while held so a long way up is one gesture.
struct AppStepper: View {
    var label: String
    var display: String
    var unit: String?
    var canDecrement: Bool = true
    var onStep: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            StepButton(
                systemImage: "minus",
                label: "Decrease \(label.lowercased())",
                isDisabled: !canDecrement
            ) { onStep(-1) }

            VStack(spacing: 2) {
                Text(label.uppercased())
                    .font(Theme.sans(10, weight: .black))
                    .kerning(1.8)
                    .foregroundStyle(Theme.mutedForeground)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(display)
                        .font(Theme.sans(21, weight: .black))
                        .kerning(-0.4)
                        .monospacedDigit()
                        .foregroundStyle(Theme.foreground)
                    if let unit {
                        Text(unit)
                            .font(Theme.sans(13, weight: .bold))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            StepButton(
                systemImage: "plus",
                label: "Increase \(label.lowercased())",
                isDisabled: false
            ) { onStep(1) }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous)
                .fill(Theme.muted.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xl2, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

// MARK: - Sliding tabs

struct TabDefinition: Identifiable, Hashable {
    var label: String
    /// A number worth putting on the tab — how many are in there. Left off, the
    /// tab is just its name.
    var count: Int?

    var id: String { label }
}

/// Sliding-pill tab bar. The pill follows the active tab's measured frame.
struct SlidingTabs: View {
    var tabs: [TabDefinition]
    @Binding var activeIndex: Int
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                let selected = index == activeIndex
                Button {
                    guard index != activeIndex else { return }
                    Haptics.trigger(.selection)
                    withAnimation(Theme.Motion.spring) { activeIndex = index }
                } label: {
                    ZStack {
                        if selected {
                            Capsule()
                                .fill(Theme.primaryGradient)
                                .matchedGeometryEffect(
                                    id: "active-tab",
                                    in: selectionNamespace
                                )
                                .shadow(color: Theme.primary.opacity(0.18), radius: 8, y: 3)
                        }

                        HStack(spacing: 6) {
                            Text(tab.label)
                                .font(Theme.sans(13, weight: .bold))
                            if let count = tab.count {
                                Text("\(count)")
                                    .font(Theme.sans(10, weight: .bold))
                                    .monospacedDigit()
                                    .opacity(0.8)
                            }
                        }
                        .foregroundStyle(
                            selected ? Theme.primaryForeground : Theme.secondaryForeground
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassSurface(
            .regular,
            in: Capsule(),
            border: Theme.Glassware.edge,
            legacyFill: Theme.card.opacity(0.74)
        )
        .frame(minHeight: 42)
    }
}

// MARK: - Glass segments

/// A compact segmented choice with a Liquid Glass selection in the brand's
/// colour.
///
/// The system segmented control is glass too, but it cannot be tinted or made
/// this small. Here the track is a quiet fill and only the selection is glass —
/// tinted, and flexing under a finger on iOS 26 — so it reads as the one thing
/// that moves. Drag across to scrub; the choice is made where the finger lifts.
/// Before iOS 26 the selection is the brand gradient.
struct GlassSegmentedPicker<Option: Hashable>: View {
    var title: String
    var options: [Option]
    @Binding var selection: Option
    var label: (Option) -> String
    var tint: Color = Theme.primary

    @Namespace private var selectionNamespace
    @State private var scrubbing: Option?
    @State private var width: CGFloat = 0

    private static var height: CGFloat { 30 }
    private var shown: Option { scrubbing ?? selection }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let active = option == shown
                Text(label(option))
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(active ? Theme.primaryForeground : Theme.mutedForeground)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.height)
                    .background {
                        if active {
                            thumb.matchedGeometryEffect(id: "selection", in: selectionNamespace)
                        }
                    }
            }
        }
        .padding(2)
        .background(Theme.foreground.opacity(0.07), in: Capsule())
        .contentShape(Capsule())
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let option = option(at: value.location.x)
                    guard option != shown else { return }
                    Haptics.trigger(.selection)
                    withAnimation(Theme.Motion.spring(0.32)) { scrubbing = option }
                }
                .onEnded { value in
                    let option = option(at: value.location.x)
                    withAnimation(Theme.Motion.spring(0.32)) {
                        scrubbing = nil
                        if option != selection { selection = option }
                    }
                }
        )
        // VoiceOver gets the system control's own semantics: a picker whose
        // value can be swiped through.
        .accessibilityRepresentation {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var thumb: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(tint).interactive(), in: Capsule())
        } else {
            Capsule()
                .fill(Theme.primaryGradient)
                .shadow(color: tint.opacity(0.18), radius: 6, y: 2)
        }
    }

    private func option(at x: CGFloat) -> Option {
        guard !options.isEmpty else { return selection }
        let inner = Swift.max(1, width - 4)
        let index = Int(((x - 2) / inner * CGFloat(options.count)).rounded(.down))
        return options[Swift.min(options.count - 1, Swift.max(0, index))]
    }
}

// MARK: - Dot pattern

/// The faint dotted field behind the body map, which warms towards the accent as
/// more muscles are chosen.
struct DotPattern: View {
    var spacing: CGFloat = 18
    var radius: CGFloat = 1.1
    var color: Color = Theme.mutedForeground
    var opacity: Double = 0.36

    var body: some View {
        Canvas { context, size in
            let dot = Path(
                ellipseIn: CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            )
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radiusX = Swift.max(1, size.width / 2)
            let radiusY = Swift.max(1, size.height / 2)
            var y = spacing / 2 - radius
            while y < size.height {
                var x = spacing / 2 - radius
                while x < size.width {
                    let dotCenter = CGPoint(x: x + radius, y: y + radius)
                    let dx = (dotCenter.x - center.x) / radiusX
                    let dy = (dotCenter.y - center.y) / radiusY
                    let distance = sqrt(dx * dx + dy * dy)
                    let maskOpacity: Double
                    if distance <= 0.28 {
                        maskOpacity = 1
                    } else if distance >= 0.80 {
                        maskOpacity = 0
                    } else {
                        maskOpacity = Double((0.80 - distance) / (0.80 - 0.28))
                    }
                    if maskOpacity > 0 {
                        var dotContext = context
                        dotContext.opacity = maskOpacity
                        dotContext.fill(dot.offsetBy(dx: x, dy: y), with: .color(color))
                    }
                    x += spacing
                }
                y += spacing
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

// MARK: - Matrix loader

enum MatrixLoaderVariant { case scan, twinkle, orbit, pulse }

/// A 4×4 field of dots that lights in the order its variant asks for.
struct MatrixLoader: View {
    var variant: MatrixLoaderVariant = .scan
    var label: String = "Loading"
    var dot: CGFloat = 2
    var gap: CGFloat = 2

    @State private var phase: Double = 0

    private static let twinkleOrder = [7, 2, 11, 5, 14, 9, 0, 12, 3, 15, 6, 10, 13, 1, 8, 4]
    private static let orbitRing = [1, 2, 7, 11, 14, 13, 8, 4]
    private static let pulseInner = [5, 6, 9, 10]
    private static let corners = [0, 3, 12, 15]

    /// How far into the shared colour cycle a cell lights up. Nil means the cell
    /// never lights — orbit's centre and corners hold steady.
    private func delay(_ index: Int) -> Double? {
        switch variant {
        case .scan:
            // Left to right, a column at a time.
            return Double(index % 4) / 10
        case .twinkle:
            // Scattered order, so no two neighbours light together.
            return Double(Self.twinkleOrder.firstIndex(of: index) ?? 0) / 16
        case .orbit:
            guard let position = Self.orbitRing.firstIndex(of: index) else { return nil }
            return Double(position) / Double(Self.orbitRing.count)
        case .pulse:
            if Self.pulseInner.contains(index) { return 0 }
            if Self.corners.contains(index) { return 0.4 }
            return 0.2
        }
    }

    var body: some View {
        VStack(spacing: gap) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<4, id: \.self) { column in
                        let index = row * 4 + column
                        Circle()
                            .fill(cellColor(index))
                            .frame(width: dot, height: dot)
                    }
                }
            }
        }
        .accessibilityLabel(label)
        .onAppear {
            withAnimation(.linear(duration: Theme.Duration.matrixCycle).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private func cellColor(_ index: Int) -> Color {
        guard let delay = delay(index) else { return Theme.primary.opacity(0.25) }
        let position = (phase + 1 - delay).truncatingRemainder(dividingBy: 1)
        // A short bright window, softening back into the base tint.
        let brightness = Swift.max(0, 1 - abs(position - 0.5) * 4)
        return Theme.primary.opacity(0.25 + 0.75 * brightness)
    }
}
