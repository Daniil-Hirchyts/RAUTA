import SwiftUI
import UIKit

/// The design tokens the web app kept in `src/index.css`, resolved once here so
/// every screen reads the same palette, radii and timings.
enum Theme {}

// MARK: - Colour

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension UIColor {
    /// A colour that follows the interface style.
    convenience init(light: UIColor, dark: UIColor) {
        self.init { traits in traits.userInterfaceStyle == .dark ? dark : light }
    }
}

extension Color {
    /// A colour that follows the interface style: `light` in Light Mode, `dark`
    /// in Dark Mode. Resolved wherever it is drawn, so a view never has to ask
    /// which theme it is in.
    init(light: UInt32, dark: UInt32, lightOpacity: Double = 1, darkOpacity: Double = 1) {
        self.init(uiColor: UIColor(
            light: UIColor(hex: light, alpha: lightOpacity),
            dark: UIColor(hex: dark, alpha: darkOpacity)
        ))
    }
}

/// Every token carries both themes, and follows the accent chosen in Settings.
/// Dark is the original warm-charcoal design; light is the same warmth on paper
/// — a pure white shell, a warm off-white surface, white cards — with accents
/// deepened wherever they are read as text on a light ground.
///
/// The tokens are read through ``ThemeStore``, which SwiftUI observes: a view
/// that draws with one is redrawn when the accent changes.
extension Theme {
    static var palette: ThemePalette { ThemeStore.shared.palette }

    /// The shell behind every screen — the surround the device paints.
    static var shell: Color { palette.shell }
    static var background: Color { palette.background }
    static var foreground: Color { palette.foreground }
    static var card: Color { palette.card }
    static var popover: Color { palette.popover }

    static var primary: Color { palette.primary }
    static var primarySoft: Color { palette.primarySoft }
    static var primarySofter: Color { palette.primarySofter }
    static var primaryForeground: Color { palette.primaryForeground }
    static var primaryGradientStart: Color { palette.primaryGradientStart }
    static var primaryGradientEnd: Color { palette.primaryGradientEnd }

    static var secondary: Color { palette.secondary }
    static var secondaryForeground: Color { palette.secondaryForeground }
    static var muted: Color { palette.muted }
    static var mutedForeground: Color { palette.mutedForeground }
    static var accent: Color { palette.primary }
    static var destructive: Color { ThemePalette.destructive }

    static var border: Color { palette.border }
    static var input: Color { palette.input }
    static var ring: Color { palette.primary }
    /// What dims the page under a modal panel.
    static var scrim: Color { palette.scrim }

    // Supporting hues.
    /// The deepest shade; in Light Mode a soft one, since it is only ever used
    /// for shadows.
    static var obsidian: Color { palette.obsidian }
    /// The dark red the dark design glows with. On a light ground a dark glow
    /// is a stain, so Light Mode glows a pale tint instead.
    static var oxblood: Color { palette.oxblood }
    static var rust: Color { palette.rust }
    static var ember: Color { palette.ember }
    // Meaning, not brand: these never follow the accent.
    static var gold: Color { ThemePalette.gold }
    static var lime: Color { ThemePalette.lime }
    static var success: Color { ThemePalette.success }

    static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [primaryGradientStart, primaryGradientEnd],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Mixes `other` into `base` the way `color-mix(in oklch, …)` does closely
    /// enough for the handful of blends the design asks for. The blend is taken
    /// per theme, so a mix of two adaptive tokens adapts too.
    static func mix(_ base: Color, _ other: Color, _ amount: Double) -> Color {
        let a = UIColor(base)
        let b = UIColor(other)
        let t = CGFloat(max(0, min(1, amount)))
        return Color(uiColor: UIColor { traits in
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            a.resolvedColor(with: traits).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            b.resolvedColor(with: traits).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            return UIColor(
                red: r1 + (r2 - r1) * t,
                green: g1 + (g2 - g1) * t,
                blue: b1 + (b2 - b1) * t,
                alpha: a1 + (a2 - a1) * t
            )
        })
    }
}

// MARK: - Metrics

extension Theme {
    enum Radius {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 25
        static let xl2: CGFloat = 30
        static let xl3: CGFloat = 36
        static let xl4: CGFloat = 42
        /// `--radius`, the base control curve.
        static let base: CGFloat = 14
    }

    enum Metrics {
        /// The display's own corner radius. Concentric insets are derived from
        /// it exactly as the stylesheet did.
        static var deviceRadius: CGFloat { DeviceScreen.cornerRadius }
        static let surfaceGutter: CGFloat = 4
        static var surfaceRadius: CGFloat { max(0, deviceRadius - surfaceGutter) }
        static let contentInset: CGFloat = 12
        static var cardRadius: CGFloat { max(0, surfaceRadius - contentInset) }
        static let controlsHeight: CGFloat = 52
        static var controlsInset: CGFloat { max(0, deviceRadius - controlsHeight / 2) }
        /// A title bar under the safe area with nothing below its title row:
        /// the 44pt row and 12pt above and below it.
        static let headerHeight: CGFloat = 68
        /// From the bottom of a page's title bar to the page's first row.
        static let headerContentGap: CGFloat = 20
    }

    enum Duration {
        static let fast: Double = 0.25
        static let pageEnter: Double = 0.30
        static let pageExit: Double = 0.20
        static let textSwap: Double = 0.15
        static let digit: Double = 0.5
        static let digitStagger: Double = 0.07
        static let checkBox: Double = 0.2
        static let checkDraw: Double = 0.35
        static let stagger: Double = 0.5
        static let staggerStep: Double = 0.04
        static let matrixCycle: Double = 1.2
    }

    enum Motion {
        /// `cubic-bezier(0.34, 1.56, 0.64, 1)` — the springy release the web app
        /// used for everything that pops into place.
        static let spring = Animation.timingCurve(0.34, 1.56, 0.64, 1, duration: Duration.fast)
        static let bounce = Animation.timingCurve(0.34, 1.85, 0.64, 1, duration: 0.35)
        /// `cubic-bezier(0.22, 1, 0.36, 1)`.
        static let smoothOut = Animation.timingCurve(0.22, 1, 0.36, 1, duration: Duration.fast)
        static func smoothOut(_ duration: Double) -> Animation {
            .timingCurve(0.22, 1, 0.36, 1, duration: duration)
        }
        static func spring(_ duration: Double) -> Animation {
            .timingCurve(0.34, 1.56, 0.64, 1, duration: duration)
        }
        static let pageEnter = Animation.timingCurve(0.22, 1, 0.36, 1, duration: Duration.pageEnter)
        static let pageExit = Animation.timingCurve(0.22, 1, 0.36, 1, duration: Duration.pageExit)
    }
}

// MARK: - Device

/// The hardware corner radius, so the surround stays concentric on every phone.
///
/// Read through public UIKit: a view that fills a window and asks for
/// container-concentric corners resolves to the display's own radius.
enum DeviceScreen {
    /// Until a window exists the fallback is used and nothing is cached, so the
    /// first read inside a window settles the real value.
    private static let fallback: CGFloat = 55
    private static var resolved: CGFloat?

    static var cornerRadius: CGFloat {
        if let resolved { return resolved }
        guard let radius = measure() else { return fallback }
        resolved = radius
        return radius
    }

    /// The width of the screen the app's window is on, found through the
    /// window scene.
    static var width: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen.bounds.width ?? 0
    }

    private static func measure() -> CGFloat? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { !$0.bounds.isEmpty }
        guard let window else { return nil }
        let probe = UIView(frame: window.bounds)
        probe.cornerConfiguration = .corners(radius: .containerConcentric())
        window.addSubview(probe)
        defer { probe.removeFromSuperview() }
        probe.layoutIfNeeded()
        let radius = probe.effectiveRadius(corner: .topLeft)
        return radius > 0 ? radius : nil
    }
}

private struct AppSafeAreaInsetsKey: EnvironmentKey {
    static let defaultValue = EdgeInsets()
}

extension EnvironmentValues {
    var appSafeAreaInsets: EdgeInsets {
        get { self[AppSafeAreaInsetsKey.self] }
        set { self[AppSafeAreaInsetsKey.self] = newValue }
    }
}

// MARK: - Typography

extension Theme {
    enum FontFamily {
        static let sans = "Geist-Regular"
        static let dot = "Doto-Black_Regular"
        static let readout = "MatrixSansPrint-Regular"
    }

    /// Every face grows with Dynamic Type, relative to the system text style
    /// nearest its design size. Geist and Doto ship as variable fonts; the
    /// weight is applied to their weight axis, not synthesised.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom(FontFamily.sans, size: size, relativeTo: textStyle(for: size)).weight(weight)
    }

    /// The system text style a design size grows with under Dynamic Type.
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: return .caption2
        case ..<12.5: return .caption
        case ..<13.5: return .footnote
        case ..<15.5: return .subheadline
        case ..<16.5: return .callout
        case ..<17.5: return .body
        case ..<20.5: return .title3
        case ..<24.5: return .title2
        case ..<30.5: return .title
        default: return .largeTitle
        }
    }

    static func dot(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom(FontFamily.dot, size: size, relativeTo: textStyle(for: size)).weight(weight)
    }

    /// Instrument-style numeric readout. Tabular by construction.
    static func readout(_ size: CGFloat) -> Font {
        Font.custom(FontFamily.readout, size: size, relativeTo: textStyle(for: size))
    }
}

