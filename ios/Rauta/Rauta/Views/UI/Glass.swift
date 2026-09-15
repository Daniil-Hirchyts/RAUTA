import SwiftUI

/// Liquid Glass, with a floor under it.
///
/// On iOS 26 a control is made of real glass: it refracts the page behind it,
/// picks up that page's colour as it scrolls past, and flexes under a finger.
/// Before iOS 26 none of that exists, so the same control is drawn as the
/// closest thing the platform has — a blurred material carrying the same tint.
///
/// Both are described once, here, so no view has to ask which one it got.
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
        border: Color? = nil,
        legacyFill: Color? = nil
    ) -> some View {
        modifier(
            GlassSurface(
                tone: tone,
                shape: shape,
                interactive: interactive,
                border: border,
                legacyFill: legacyFill
            )
        )
    }
}

struct GlassSurface<S: InsettableShape>: ViewModifier {
    var tone: GlassTone
    var shape: S
    var interactive: Bool
    var border: Color?
    var legacyFill: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(modernGlass, in: shape)
                .overlay(borderOverlay)
        } else {
            content
                .background(legacyPane)
                .overlay(borderOverlay)
        }
    }

    @available(iOS 26.0, *)
    private var modernGlass: Glass {
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

    private var legacyPane: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(legacyTint))
    }

    private var legacyTint: Color {
        switch tone {
        case .regular: return legacyFill ?? Theme.popover.opacity(0.72)
        case .clear: return legacyFill ?? Theme.card.opacity(0.34)
        case .tinted(let color): return color.opacity(0.86)
        case .inert: return Theme.muted.opacity(0.92)
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

/// Groups glass that changes shape together: on iOS 26 panes that come close
/// melt into one another as they move, so a strip of controls reads as one
/// material rearranging itself. Before iOS 26 it is a plain container.
struct GlassMorphContainer<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
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
    /// A button made of the system's own Liquid Glass.
    ///
    /// On iOS 26 this is the platform's glass button: it flexes under a finger,
    /// shimmers where it is touched, and carries its own rim and shadow — so
    /// nothing is laid over it, and nothing clips it to its shape. Before iOS 26
    /// the same button is drawn on the blurred pane `glassSurface` falls back to.
    static func glassControl(
        _ tone: GlassTone,
        _ shape: GlassButtonShape,
        legacyFill: Color? = nil
    ) -> GlassControlStyle {
        GlassControlStyle(tone: tone, shape: shape, legacyFill: legacyFill)
    }
}

struct GlassControlStyle: PrimitiveButtonStyle {
    var tone: GlassTone
    var shape: GlassButtonShape
    var legacyFill: Color?

    /// What the system glass style pads its label with at the regular control
    /// size. The label is laid out at the pane's full size and hands this back,
    /// so a pane is the same size on either side of iOS 26.
    private static let systemVerticalInset: CGFloat = 7
    private static let systemCircleInset: CGFloat = 7
    private static let systemCapsuleInset: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *) {
            Button(role: configuration.role, action: configuration.trigger) {
                sized(configuration.label)
                    .padding(.vertical, -Self.systemVerticalInset)
                    .padding(.horizontal, -horizontalInset)
            }
            .modifier(SystemGlassButton(tone: tone))
            .buttonBorderShape(borderShape)
            .controlSize(.regular)
        } else {
            Button(role: configuration.role, action: configuration.trigger) {
                sized(configuration.label)
            }
            .buttonStyle(LegacyGlassButton(tone: tone, shape: shape, legacyFill: legacyFill))
        }
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

    @available(iOS 26.0, *)
    private var borderShape: ButtonBorderShape {
        switch shape {
        case .circle: return .circle
        case .capsule: return .capsule
        }
    }
}

@available(iOS 26.0, *)
private struct SystemGlassButton: ViewModifier {
    var tone: GlassTone

    func body(content: Content) -> some View {
        switch tone {
        case .regular, .inert:
            content.buttonStyle(.glass)
        case .clear:
            if #available(iOS 26.1, *) {
                content.buttonStyle(.glass(.clear))
            } else {
                content.buttonStyle(.glass)
            }
        case .tinted(let color):
            content
                .buttonStyle(.glassProminent)
                .tint(color)
        }
    }
}

/// The pre-glass floor: the blurred pane, the warm outline, and the brand
/// gradient under a primary label.
private struct LegacyGlassButton: ButtonStyle {
    var tone: GlassTone
    var shape: GlassButtonShape
    var legacyFill: Color?

    func makeBody(configuration: Configuration) -> some View {
        Group {
            switch shape {
            case .circle: pane(configuration.label, in: Circle())
            case .capsule: pane(configuration.label, in: Capsule())
            }
        }
        .scaleEffect(configuration.isPressed ? 0.985 : 1)
        .opacity(configuration.isPressed ? 0.90 : 1)
        .animation(Theme.Motion.spring, value: configuration.isPressed)
    }

    private func pane<S: InsettableShape>(_ label: Configuration.Label, in shape: S) -> some View {
        label
            .background {
                if case .tinted = tone {
                    shape.fill(Theme.primaryGradient)
                }
            }
            .glassSurface(
                tone,
                in: shape,
                border: isTinted ? Theme.Glassware.brightEdge : Theme.Glassware.edge,
                legacyFill: legacyFill
            )
            .clipShape(shape)
            .contentShape(shape)
    }

    private var isTinted: Bool {
        if case .tinted = tone { return true }
        return false
    }
}

extension Theme {
    /// The glass palette: how much of the warm outline survives on top of a
    /// pane, and how strongly the brand colour is allowed to soak through one.
    enum Glassware {
        /// Real glass draws its own bright edge, so ours only has to hint.
        static var edge: Color { Theme.border.opacity(supportsLiquidGlass ? 0.55 : 1) }
        static var brightEdge: Color { Theme.primary.opacity(supportsLiquidGlass ? 0.45 : 0.8) }
        /// The outline for a glass control that is not a button. System glass
        /// draws its own rim, so a stroke on top of it only reads as a frame the
        /// glass has been pushed into.
        static var controlEdge: Color? { supportsLiquidGlass ? nil : Theme.border }
        /// The vertical warm gradient the primary control is known by, kept as
        /// a wash over the tint so glass never flattens the brand into one flat
        /// orange.
        static var primaryWash: Double { supportsLiquidGlass ? 0.34 : 1 }

        static var supportsLiquidGlass: Bool {
            if #available(iOS 26.0, *) { return true }
            return false
        }
    }
}
