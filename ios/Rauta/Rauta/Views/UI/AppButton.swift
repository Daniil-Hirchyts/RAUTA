import SwiftUI

enum ButtonVariant {
    case primary, secondary, ghost, destructive
}

enum ButtonSize {
    case standard, icon, cta, iconCTA

    /// The visible pane stays compact while the row keeps `hitHeight` of room
    /// around it. A glass button answers touches on its pane.
    var visualHeight: CGFloat {
        switch self {
        case .standard: return 40
        case .icon: return 40
        case .cta: return 46
        case .iconCTA: return 42
        }
    }

    var hitHeight: CGFloat {
        switch self {
        case .standard, .icon: return 44
        case .cta, .iconCTA: return 48
        }
    }
}

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

    @State private var shakePhase: CGFloat = 0

    private var tone: GlassTone {
        if isDisabled { return .inert }
        switch variant {
        case .primary:
            return .tinted(Theme.primary)
        case .secondary:
            return .regular
        case .ghost:
            return .clear
        case .destructive:
            return .clear
        }
    }

    private var foreground: Color {
        if isDisabled { return Theme.mutedForeground }
        switch variant {
        case .primary: return Theme.primaryForeground
        case .secondary: return Theme.secondaryForeground
        case .ghost: return size == .icon || size == .iconCTA ? Theme.primary : Theme.foreground
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
                .padding(.horizontal, horizontalPadding)
                .foregroundStyle(foreground)
        }
        .buttonStyle(.glassControl(tone, shape))
        .frame(
            minWidth: (size == .icon || size == .iconCTA) ? size.hitHeight : nil,
            minHeight: size.hitHeight
        )
        .modifier(ShakeEffect(phase: shakePhase))
        // Without an explicit label the button keeps the one its content
        // gives it, rather than being overridden with an empty string.
        .accessibilityLabel(accessibilityLabel ?? "", isEnabled: accessibilityLabel != nil)
        // Presses still reach a disabled button (to explain the refusal), so
        // the dimmed state has to be spoken rather than taken from `.disabled`.
        .accessibilityValue(isDisabled ? "Unavailable" : "", isEnabled: isDisabled)
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .standard: return 16
        case .icon, .iconCTA: return 0
        case .cta: return 20
        }
    }

    private var shape: GlassButtonShape {
        switch size {
        case .icon, .iconCTA: return .circle(diameter: size.visualHeight)
        case .standard, .cta: return .capsule(height: size.visualHeight)
        }
    }

    private func press() {
        guard !isDisabled else {
            // Restart the refusal shake even if one is already playing, so a
            // second impatient tap answers as clearly as the first.
            withAnimation(.linear(duration: 0.36)) { shakePhase += 1 }
            Haptics.trigger(.warning)
            return
        }
        // Every button is heard; what it does may say something more.
        WorkoutAudio.touch(.tap)
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

/// A short horizontal refusal, three swings and out.
///
/// The phase is fractional because the swing lives in its fractional part:
/// rounding it to a whole number left the button standing still.
nonisolated struct ShakeEffect: GeometryEffect {
    var phase: CGFloat
    var amplitude: CGFloat = 6

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
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
                .font(.system(size: 18, weight: .medium))
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
                .font(.system(size: 17, weight: .medium))
        }
    }
}

/// RAUTA as the entry point for a page's secondary actions, which open as a
/// thought bubble rising from the character.
struct AppMenuButton<MenuContent: View>: View {
    var label: String
    var compact = false
    var mood: RautaMood = .focused
    var speaks = true
    @ViewBuilder var menu: () -> MenuContent
    @State private var isPresented = false
    @State private var reactionKey = ""

    var body: some View {
        trigger
            .accessibilityLabel(label)
            .rautaThoughts(isPresented: $isPresented) { menu() }
    }

    @ViewBuilder private var trigger: some View {
        if compact {
            RautaHeaderBadge(mood: mood, reactionKey: reactionKey, onActivate: openMenu, speaks: speaks)
        } else {
            RautaCharacter(mood: mood, reactionKey: reactionKey, onActivate: openMenu)
                .frame(width: 72, height: 72)
                .frame(width: 60, height: 52)
                .contentShape(Circle())
        }
    }

    private func openMenu() {
        Haptics.trigger(.selection)
        RautaSpeech.shared.hush()
        // The character reacts as the thought leaves it.
        reactionKey = UUID().uuidString
        isPresented = true
    }
}

struct AppMenuSurface<Content: View>: View {
    var dismiss: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        VStack(alignment: .leading, spacing: 2) {
            content()
        }
        .buttonStyle(AppMenuRowButtonStyle())
        .labelStyle(.titleAndIcon)
        .padding(8)
        .frame(minWidth: 232, idealWidth: 248, maxWidth: 280, alignment: .leading)
        .glassSurface(.regular, in: shape)
        .padding(6)
        .simultaneousGesture(
            TapGesture().onEnded {
                DispatchQueue.main.async { dismiss() }
            }
        )
    }
}

struct AppMenuRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(16, weight: .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.trailing, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .background(
                configuration.isPressed ? Theme.foreground.opacity(0.08) : .clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .opacity(isEnabled ? 1 : 0.38)
    }
}
