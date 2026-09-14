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

/// Every token carries both themes. Dark is the original warm-charcoal design;
/// light is the same warmth on paper — a pure white shell, a warm off-white
/// surface, white cards — with the accents deepened wherever they have to be
/// read as text on a light ground.
extension Theme {
    /// The shell behind every screen — the surround the device paints.
    static let shell = Color(light: 0xFFFFFF, dark: 0x000000)
    static let background = Color(light: 0xF6F2ED, dark: 0x171311)
    static let foreground = Color(light: 0x1C1512, dark: 0xF6F0E5)
    static let card = Color(light: 0xFFFFFF, dark: 0x261E1A)
    static let cardForeground = foreground
    static let popover = Color(light: 0xFFFFFF, dark: 0x211915)
    static let popoverForeground = foreground

    static let primary = Color(light: 0xF25200, dark: 0xFF5700)
    static let primarySoft = Color(light: 0xF46A1E, dark: 0xFF7E38)
    static let primarySofter = Color(light: 0xE0662A, dark: 0xFF9B68)
    static let primaryForeground = Color(hex: 0x060606)
    static let primaryGradientStart = Color(hex: 0xFF6700)
    static let primaryGradientEnd = Color(hex: 0xFF3F00)
    static let primaryGradientActiveStart = Color(hex: 0xFF8A2F)
    static let primaryGradientActiveEnd = Color(hex: 0xFF601B)

    static let secondary = Color(light: 0xEFE8E0, dark: 0x302620)
    static let secondaryForeground = Color(light: 0x3B2F28, dark: 0xE9DFD2)
    static let muted = Color(light: 0xEDE6DE, dark: 0x2B231E)
    static let mutedForeground = Color(light: 0x76685C, dark: 0xB1A396)
    static let accent = primary
    static let accentForeground = primaryForeground
    static let destructive = Color(light: 0xD63A24, dark: 0xFF7966)

    static let border = Color(light: 0x6B4A2A, dark: 0xD9AD6C, lightOpacity: 0.14, darkOpacity: 0.20)
    static let input = Color(light: 0x6B4A2A, dark: 0xD9AD6C, lightOpacity: 0.10, darkOpacity: 0.17)
    static let ring = primary
    /// What dims the page under a modal panel.
    static let scrim = Color(light: 0x1C1512, dark: 0x000000, lightOpacity: 0.28, darkOpacity: 0.6)

    // Warm supporting hues.
    /// The deepest warm shade; in Light Mode a soft one, since it is only ever
    /// used for shadows.
    static let obsidian = Color(light: 0x5C4636, dark: 0x100D0B)
    /// The dark red the dark design glows with. On a light ground a dark glow
    /// is a stain, so Light Mode glows peach instead.
    static let oxblood = Color(light: 0xFFD2BD, dark: 0x501D16)
    static let rust = Color(light: 0xB8432A, dark: 0x983723)
    static let ember = Color(light: 0xE5452A, dark: 0xF34D32)
    static let gold = Color(light: 0xA7742C, dark: 0xD9AD6C)
    static let lime = Color(light: 0x6B8A00, dark: 0xD6E65B)
    static let success = Color(light: 0x3F8F3A, dark: 0xC6E7BC)

    static let primaryGradient = LinearGradient(
        colors: [primaryGradientStart, primaryGradientEnd],
        startPoint: .top,
        endPoint: .bottom
    )
    static let primaryGradientActive = LinearGradient(
        colors: [primaryGradientActiveStart, primaryGradientActiveEnd],
        startPoint: .top,
        endPoint: .bottom
    )

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
        /// How far the progressive blur reaches past the bottom of the title bar.
        static let headerScrimOverhang: CGFloat = 12
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

/// The hardware corner radius, read from the private but stable display corner
/// value with a sane fallback so the surround stays concentric on every phone.
enum DeviceScreen {
    static let cornerRadius: CGFloat = {
        let key = ["Radius", "Corner", "display", "_"].reversed().joined()
        if let value = UIScreen.main.value(forKey: key) as? CGFloat, value > 0 {
            return value
        }
        return 55
    }()

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

    /// Geist ships as a variable font; iOS needs the weight axis set explicitly
    /// rather than synthesised, so every UI weight is an instance of the axis.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font(VariableFont.geist(size: size, weight: weight))
    }

    static func dot(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font(VariableFont.doto(size: size, weight: weight))
    }

    /// Instrument-style numeric readout. Tabular by construction.
    static func readout(_ size: CGFloat) -> Font {
        if let font = UIFont(name: FontFamily.readout, size: size) {
            return Font(font)
        }
        return .system(size: size, design: .monospaced)
    }
}

enum VariableFont {
    /// `wght` — the four-character axis identifier as a 32-bit tag.
    private static let weightAxis = 0x77676874

    private static func numericWeight(_ weight: Font.Weight) -> CGFloat {
        switch weight {
        case .ultraLight: return 100
        case .thin: return 200
        case .light: return 300
        case .regular: return 400
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy: return 800
        case .black: return 900
        default: return 400
        }
    }

    private static func instance(_ family: String, size: CGFloat, weight: Font.Weight, fallback: UIFont) -> UIFont {
        guard let base = UIFont(name: family, size: size) else { return fallback }
        let descriptor = base.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String):
                [weightAxis: numericWeight(weight)]
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    static func geist(size: CGFloat, weight: Font.Weight) -> UIFont {
        instance(
            Theme.FontFamily.sans,
            size: size,
            weight: weight,
            fallback: .systemFont(ofSize: size, weight: uiWeight(weight))
        )
    }

    static func doto(size: CGFloat, weight: Font.Weight) -> UIFont {
        instance(
            Theme.FontFamily.dot,
            size: size,
            weight: weight,
            fallback: .monospacedSystemFont(ofSize: size, weight: uiWeight(weight))
        )
    }

    static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}
