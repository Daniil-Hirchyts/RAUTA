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

    /// Ties this pane to its neighbours inside a ``GlassGroup``, so panes that
    /// come near each other merge and pull apart the way liquid does.
    @ViewBuilder
    func glassMorph(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
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
            .environment(\.colorScheme, .dark)
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

/// The space inside which panes of glass know about each other.
///
/// Two glass buttons sitting side by side are two separate panes until they
/// share a container; inside one they behave as a single body of liquid —
/// blending where they overlap, and morphing into one another when one is
/// swapped for the next.
struct GlassGroup<Content: View>: View {
    /// Keep the merge threshold below the visual gap between neighbouring
    /// controls. Large values make separate buttons fuse into a blob at rest.
    var spacing: CGFloat = 4
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

extension Theme {
    /// The glass palette: how much of the warm outline survives on top of a
    /// pane, and how strongly the brand colour is allowed to soak through one.
    enum Glassware {
        /// Real glass draws its own bright edge, so ours only has to hint.
        static var edge: Color { Theme.border.opacity(supportsLiquidGlass ? 0.55 : 1) }
        static var brightEdge: Color { Theme.primary.opacity(supportsLiquidGlass ? 0.45 : 0.8) }
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
