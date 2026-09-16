import SwiftUI

/// Liquid Glass.
///
/// A control is made of real glass: it refracts the page behind it, picks up
/// that page's colour as it scrolls past, and flexes under a finger.
///
/// It is described once, here, so no view has to build a pane of its own.
enum GlassTone: Equatable {
    /// Chrome that should read as a pane laid over the page.
    case regular
    /// Barely there until it passes over something — for a control that must
    /// not compete with the content it floats above.
    case clear
    /// Glass carrying a colour through it. The brand's orange, mostly.
    case tinted(Color)
    /// A control that cannot be pressed: no colour, no reaction, dimmed.
    case inert
}

extension View {
    /// Puts `self` on a pane of glass cut to `shape`.
    ///
    /// - Parameters:
    ///   - interactive: the glass flexes and springs back under a press. Only
    ///     for something that is actually pressable; on anything else the
    ///     reaction is a lie about what the control does.
    ///   - border: a hairline the app's warm outline is drawn in. Real glass
    ///     already carries its own specular edge, so this stays subtle.
    func glassSurface<S: InsettableShape>(
        _ tone: GlassTone = .regular,
        in shape: S,
        interactive: Bool = false,
        border: Color? = nil
    ) -> some View {
        modifier(
            GlassSurface(
                tone: tone,
                shape: shape,
                interactive: interactive,
                border: border
            )
        )
    }
}

struct GlassSurface<S: InsettableShape>: ViewModifier {
    var tone: GlassTone
    var shape: S
    var interactive: Bool
    var border: Color?

    func body(content: Content) -> some View {
        content
            .glassEffect(glass, in: shape)
            .overlay(borderOverlay)
    }

    private var glass: Glass {
        switch tone {
        case .regular:
            return .regular.interactive(interactive)
        case .clear:
            return .clear.interactive(interactive)
        case .tinted(let color):
            return .regular.tint(color).interactive(interactive)
        case .inert:
            // A dead control still needs a shape; what it must not have is the
            // colour and the give that say "press me".
            return .regular.tint(Theme.muted.opacity(0.55))
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if let border {
            shape.strokeBorder(border, lineWidth: 1)
        }
    }
}

// MARK: - Morphing glass

/// Groups glass that changes shape together: panes that come close melt into
/// one another as they move, so a strip of controls reads as one material
/// rearranging itself.
struct GlassMorphContainer<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: spacing, content: content)
    }
}

// MARK: - Glass buttons

/// The cut of a glass button, and how big its pane is.
enum GlassButtonShape: Equatable {
    /// A round tool, `diameter` points across.
    case circle(diameter: CGFloat)
    /// A pill `height` points tall, as wide as its label and the label's own
    /// horizontal padding.
    case capsule(height: CGFloat)
}

extension PrimitiveButtonStyle where Self == GlassControlStyle {
    /// A button made of the system's own Liquid Glass: it flexes under a
    /// finger, shimmers where it is touched, and carries its own rim and
    /// shadow — so nothing is laid over it, and nothing clips it to its shape.
    static func glassControl(
        _ tone: GlassTone,
        _ shape: GlassButtonShape
    ) -> GlassControlStyle {
        GlassControlStyle(tone: tone, shape: shape)
    }
}

struct GlassControlStyle: PrimitiveButtonStyle {
    var tone: GlassTone
    var shape: GlassButtonShape

    /// What the system glass style pads its label with at the regular control
    /// size. The label is laid out at the pane's full size and hands this back,
    /// so the pane ends up the size the caller asked for.
    private static let systemVerticalInset: CGFloat = 7
    private static let systemCircleInset: CGFloat = 7
    private static let systemCapsuleInset: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            sized(configuration.label)
                .padding(.vertical, -Self.systemVerticalInset)
                .padding(.horizontal, -horizontalInset)
        }
        .modifier(SystemGlassButton(tone: tone))
        .buttonBorderShape(borderShape)
        .controlSize(.regular)
    }

    private func sized(_ label: Configuration.Label) -> some View {
        switch shape {
        case .circle(let diameter):
            return label.frame(width: diameter, height: diameter)
        case .capsule(let height):
            return label.frame(width: nil, height: height)
        }
    }

    private var horizontalInset: CGFloat {
        switch shape {
        case .circle: return Self.systemCircleInset
        case .capsule: return Self.systemCapsuleInset
        }
    }

    private var borderShape: ButtonBorderShape {
        switch shape {
        case .circle: return .circle
        case .capsule: return .capsule
        }
    }
}

private struct SystemGlassButton: ViewModifier {
    var tone: GlassTone

    func body(content: Content) -> some View {
        switch tone {
        case .regular, .inert:
            content.buttonStyle(.glass)
        case .clear:
            content.buttonStyle(.glass(.clear))
        case .tinted(let color):
            content
                .buttonStyle(.glassProminent)
                .tint(color)
        }
    }
}

extension Theme {
    /// The glass palette: how much of the warm outline survives on top of a
    /// pane, and how strongly the brand colour is allowed to soak through one.
    enum Glassware {
        /// Real glass draws its own bright edge, so ours only has to hint.
        static var edge: Color { Theme.border.opacity(0.55) }
        static var brightEdge: Color { Theme.primary.opacity(0.45) }
        /// The vertical warm gradient the primary control is known by, kept as
        /// a wash over the tint so glass never flattens the brand into one flat
        /// orange.
        static var primaryWash: Double { 0.34 }
    }
}
