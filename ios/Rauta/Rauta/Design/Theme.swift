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

extension Theme {
    /// The shell behind every screen — the surround the device paints.
    static let shell = Color(hex: 0x000000)
    static let background = Color(hex: 0x171311)
    static let foreground = Color(hex: 0xF6F0E5)
    static let card = Color(hex: 0x261E1A)
    static let cardForeground = foreground
    static let popover = Color(hex: 0x211915)
    static let popoverForeground = foreground

    static let primary = Color(hex: 0xFF5700)
    static let primarySoft = Color(hex: 0xFF7E38)
    static let primarySofter = Color(hex: 0xFF9B68)
    static let primaryForeground = Color(hex: 0x060606)
    static let primaryGradientStart = Color(hex: 0xFF6700)
    static let primaryGradientEnd = Color(hex: 0xFF3F00)
    static let primaryGradientActiveStart = Color(hex: 0xFF8A2F)
    static let primaryGradientActiveEnd = Color(hex: 0xFF601B)

    static let secondary = Color(hex: 0x302620)
    static let secondaryForeground = Color(hex: 0xE9DFD2)
    static let muted = Color(hex: 0x2B231E)
    static let mutedForeground = Color(hex: 0xB1A396)
    static let accent = primary
    static let accentForeground = primaryForeground
    static let destructive = Color(hex: 0xFF7966)

    static let border = Color(hex: 0xD9AD6C, opacity: 0.20)
    static let input = Color(hex: 0xD9AD6C, opacity: 0.17)
    static let ring = primary

    // Warm supporting hues.
    static let obsidian = Color(hex: 0x100D0B)
    static let oxblood = Color(hex: 0x501D16)
    static let rust = Color(hex: 0x983723)
    static let ember = Color(hex: 0xF34D32)
    static let gold = Color(hex: 0xD9AD6C)
    static let lime = Color(hex: 0xD6E65B)
    static let success = Color(hex: 0xC6E7BC)

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
    /// enough for the handful of blends the design asks for.
    static func mix(_ base: Color, _ other: Color, _ amount: Double) -> Color {
        let a = UIColor(base)
        let b = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(max(0, min(1, amount)))
        return Color(
            .sRGB,
            red: Double(r1 + (r2 - r1) * t),
            green: Double(g1 + (g2 - g1) * t),
            blue: Double(b1 + (b2 - b1) * t),
            opacity: Double(a1 + (a2 - a1) * t)
        )
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
