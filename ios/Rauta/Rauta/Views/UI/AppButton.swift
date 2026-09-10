import SwiftUI

enum ButtonVariant {
    case primary, secondary, ghost, destructive
}

enum ButtonSize {
    case standard, icon, cta, iconCTA

    var height: CGFloat {
        switch self {
        case .standard: return 44
        case .icon: return 44
        case .cta, .iconCTA: return Theme.Metrics.controlsHeight
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .standard: return Theme.Radius.xl4
        case .icon, .iconCTA: return height / 2
        case .cta: return Theme.Radius.xl2
        }
    }
}

/// How long a button ignores a press that repeats the one before it.
///
/// A tap that starts a workout, saves a preset or deletes something is meant
/// once. Hammering it runs the action twice: two identical workouts, a page
/// pushed twice, a delete that outlives the row it removed.
private let repeatGuardMilliseconds: Double = 350

/// The app's one button.
///
/// A disabled button that cannot be pressed also cannot say why: the tap lands
/// on nothing and reads as a dead app. Pressing one still reaches us and is
/// answered with a shake and a warning haptic.
struct AppButton<Label: View>: View {
    var variant: ButtonVariant = .primary
    var size: ButtonSize = .standard
    var isDisabled: Bool = false
    var expands: Bool = false
    var accessibilityLabel: String?
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    @State private var isPressed = false
    @State private var shakePhase = 0
    @State private var lastAction: (label: String, at: Date)?

    private var background: some ShapeStyle {
        AnyShapeStyle(resolvedBackground)
    }

    private var resolvedBackground: AnyShapeStyle {
        if isDisabled { return AnyShapeStyle(Theme.muted) }
        switch variant {
        case .primary:
            return AnyShapeStyle(isPressed ? Theme.primaryGradientActive : Theme.primaryGradient)
        case .secondary:
            return AnyShapeStyle(isPressed ? Theme.secondary.opacity(0.9) : Theme.secondary)
        case .ghost:
            return AnyShapeStyle(isPressed ? Theme.card.opacity(0.9) : Theme.card)
        case .destructive:
            return AnyShapeStyle(
                isPressed ? Theme.mix(Theme.card, Theme.primary, 0.28) : Theme.card
            )
        }
    }

    private var foreground: Color {
        if isDisabled { return Theme.mutedForeground }
        switch variant {
        case .primary: return Theme.primaryForeground
        case .secondary: return isPressed ? .white : Theme.secondaryForeground
        case .ghost: return size == .icon || size == .iconCTA ? Theme.primary : Theme.foreground
        case .destructive: return Theme.primary
        }
    }

    private var borderColor: Color {
        if isDisabled { return Theme.border }
        switch variant {
        case .primary: return isPressed ? Theme.primarySofter : Theme.primary.opacity(0.8)
        case .secondary, .ghost: return Theme.border
        case .destructive: return Theme.primary
        }
    }

    private var font: Font {
        switch size {
        case .standard: return Theme.sans(16, weight: .semibold)
        case .icon, .iconCTA: return Theme.sans(16, weight: .semibold)
        case .cta: return Theme.sans(18, weight: .bold)
        }
    }

    var body: some View {
        Button {
            press()
        } label: {
            label()
                .font(font)
                .lineLimit(1)
                .frame(maxWidth: expands ? .infinity : nil)
                .frame(
                    width: (size == .icon || size == .iconCTA) ? size.height : nil,
                    height: size.height
                )
                .padding(.horizontal, horizontalPadding)
                .foregroundStyle(foreground)
                .background(background, in: shape)
                .overlay(shape.strokeBorder(borderColor, lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(PressReporting(isPressed: $isPressed))
        .scaleEffect(isPressed && !isDisabled ? 0.96 : 1)
        .animation(Theme.Motion.spring, value: isPressed)
        .modifier(ShakeEffect(phase: shakePhase))
        .accessibilityLabel(accessibilityLabel ?? "")
        .accessibilityAddTraits(isDisabled ? [] : [])
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .standard: return 16
        case .icon, .iconCTA: return 0
        case .cta: return 20
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
    }

    private func press() {
        guard !isDisabled else {
            // Restart the refusal shake even if one is already playing, so a
            // second impatient tap answers as clearly as the first.
            withAnimation(.linear(duration: 0.36)) { shakePhase += 1 }
            Haptics.trigger(.warning)
            return
        }
        // The guard has to tell a hammered repeat from a button that now does
        // something else: most of them are reused in place. The label is what
        // the user was answering, so that is what the press is keyed on.
        let key = accessibilityLabel ?? "\(Label.self)"
        if let lastAction, lastAction.label == key,
           Date().timeIntervalSince(lastAction.at) * 1000 < repeatGuardMilliseconds {
            return
        }
        lastAction = (key, Date())
        action()
    }
}

extension AppButton where Label == Text {
    init(
        _ title: String,
        variant: ButtonVariant = .primary,
        size: ButtonSize = .standard,
        isDisabled: Bool = false,
        expands: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            variant: variant,
            size: size,
            isDisabled: isDisabled,
            expands: expands,
            accessibilityLabel: title,
            action: action,
            label: { Text(title) }
        )
    }
}

private struct PressReporting: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}

/// A short horizontal refusal, three swings and out.
struct ShakeEffect: GeometryEffect {
    var phase: Int
    var amplitude: CGFloat = 6

    var animatableData: CGFloat {
        get { CGFloat(phase) }
        set { phase = Int(newValue.rounded()) }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let progress = animatableData.truncatingRemainder(dividingBy: 1)
        let offset = amplitude * sin(progress * .pi * 6) * (1 - progress)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

/// A round tool in the command band.
///
/// Which icon it carries and what pressing it does belong to the page; how big
/// the button is, what it is made of, and how big the icon inside it draws
/// belong to the band.
struct AppControlButton: View {
    var systemImage: String
    var label: String
    var variant: ButtonVariant = .ghost
    var isDisabled: Bool = false
    var isPressed: Bool = false
    var action: () -> Void

    var body: some View {
        AppButton(
            variant: variant,
            size: .iconCTA,
            isDisabled: isDisabled,
            accessibilityLabel: label,
            action: action
        ) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
        }
    }
}

/// The round header tool: back, settings, close.
struct AppHeaderButton: View {
    var systemImage: String
    var label: String
    var isDisabled: Bool = false
    var action: () -> Void

    var body: some View {
        AppButton(
            variant: .ghost,
            size: .icon,
            isDisabled: isDisabled,
            accessibilityLabel: label,
            action: action
        ) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
        }
    }
}
