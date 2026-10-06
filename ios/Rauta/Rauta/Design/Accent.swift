import Observation
import SwiftUI
import UIKit

// MARK: - Choice

/// The colour the app is drawn in: one of the presets, or any colour picked.
enum AppAccent: Hashable, Sendable {
    case preset(AccentPreset)
    case custom(UInt32)

    static let `default` = AppAccent.preset(.ember)

    /// Read back from settings: a preset's name, or `#RRGGBB`. Anything else is
    /// the brand orange.
    init(storage: String?) {
        guard let storage else { self = .default; return }
        if storage.hasPrefix("#"), storage.count == 7, let hex = UInt32(storage.dropFirst(), radix: 16) {
            self = .custom(hex)
        } else if let preset = AccentPreset(rawValue: storage) {
            self = .preset(preset)
        } else {
            self = .default
        }
    }

    var storage: String {
        switch self {
        case .preset(let preset): return preset.rawValue
        case .custom(let hex): return String(format: "#%06X", hex)
        }
    }

    var name: String {
        switch self {
        case .preset(let preset): return preset.name
        case .custom: return "Custom"
        }
    }
}

/// Hand-tuned accents across the wheel. Each is a vivid shade for the dark
/// theme and a deeper one that still reads as text on white, and each says
/// whether a label on top of it is dark or white.
enum AccentPreset: String, CaseIterable, Identifiable, Sendable {
    case ember, amber, volt, emerald, aqua, cobalt, violet, fuchsia, crimson

    var id: String { rawValue }

    var name: String { rawValue.capitalized }

    fileprivate var dark: UInt32 {
        switch self {
        case .ember: return RautaBrand.primary
        case .amber: return 0xFFB020
        case .volt: return 0xC6F432
        case .emerald: return 0x22D39A
        case .aqua: return 0x38D5F2
        case .cobalt: return 0x4F7DFF
        case .violet: return 0x9D6BFF
        case .fuchsia: return 0xFF4DAE
        case .crimson: return 0xFF4057
        }
    }

    fileprivate var light: UInt32 {
        switch self {
        case .ember: return 0xF25200
        case .amber: return 0xB97800
        case .volt: return 0x5E8F00
        case .emerald: return 0x0C9A6C
        case .aqua: return 0x0A8FB3
        case .cobalt: return 0x2F5CE8
        case .violet: return 0x6E43E5
        case .fuchsia: return 0xD42A8C
        case .crimson: return 0xDB2139
        }
    }

    fileprivate var whiteLabel: Bool {
        switch self {
        case .cobalt, .violet, .crimson: return true
        default: return false
        }
    }

    /// The swatch Settings shows: the preset's own button gradient.
    var swatch: LinearGradient {
        let base = HSB(hex: dark)
        return LinearGradient(
            colors: [Color(uiColor: base.shifted(3.8).color), Color(uiColor: base.shifted(-5.6).color)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// The accent as plain numbers, for what draws outside the app's own views and
/// cannot read ``ThemeStore``: the Live Activity and the watch.
struct AccentSignature: Equatable, Sendable {
    /// The accent as the dark theme draws it.
    var primary: UInt32
    var gradientStart: UInt32
    var gradientEnd: UInt32
    /// Whether a label on the accent is white rather than near-black.
    var whiteLabel: Bool
}

extension AppAccent {
    var signature: AccentSignature {
        switch self {
        case .preset(.ember):
            return AccentSignature(
                primary: RautaBrand.primary,
                gradientStart: RautaBrand.gradientStart,
                gradientEnd: RautaBrand.gradientEnd,
                whiteLabel: false
            )
        case .preset(let preset):
            let dark = HSB(hex: preset.dark)
            return AccentSignature(
                primary: preset.dark,
                gradientStart: dark.shifted(3.8).hex,
                gradientEnd: dark.shifted(-5.6).hex,
                whiteLabel: preset.whiteLabel
            )
        case .custom(let hex):
            let dark = HSB(hex: hex).normalizedAccent().dark
            return AccentSignature(
                primary: dark.hex,
                gradientStart: dark.shifted(3.8).hex,
                gradientEnd: dark.shifted(-5.6).hex,
                whiteLabel: dark.prefersWhiteLabel
            )
        }
    }
}

// MARK: - Palette

/// Every colour the app draws with, for one accent, in both themes.
///
/// Ember is the original hand-tuned palette, unchanged. Any other accent
/// regenerates the whole palette from the same recipe the original follows:
/// the accent family — soft tints, the button gradient, the glow reds — keep
/// their exact offsets from the accent, and the warm neutrals take the
/// accent's hue at half the weight, so a cobalt app has cool charcoal surfaces
/// rather than blue on brown.
struct ThemePalette {
    var shell: Color
    var background: Color
    var foreground: Color
    var card: Color
    var popover: Color

    var primary: Color
    var primarySoft: Color
    var primarySofter: Color
    var primaryForeground: Color
    var primaryGradientStart: Color
    var primaryGradientEnd: Color

    var secondary: Color
    var secondaryForeground: Color
    var muted: Color
    var mutedForeground: Color
    var border: Color
    var input: Color
    var scrim: Color

    var obsidian: Color
    var oxblood: Color
    var rust: Color
    var ember: Color

    var bodyResting: Color
    var bodySilhouette: Color
    var bodyRestingShadow: Color

    /// How far the accent's hue sits from the brand orange, in degrees. The
    /// exercise demonstrations and equipment art turn their orange by this.
    var hueShift: Double

    // Colours that mean something — success, streaks, errors — never follow
    // the accent.
    static let destructive = Color(light: 0xD63A24, dark: 0xFF7966)
    static let gold = Color(light: 0xA7742C, dark: 0xD9AD6C)
    static let lime = Color(light: 0x6B8A00, dark: 0xD6E65B)
    static let success = Color(light: 0x3F8F3A, dark: 0xC6E7BC)

    static func make(_ accent: AppAccent) -> ThemePalette {
        switch accent {
        case .preset(.ember):
            return .ember
        case .preset(let preset):
            return generated(
                dark: HSB(hex: preset.dark),
                light: HSB(hex: preset.light),
                whiteLabel: preset.whiteLabel
            )
        case .custom(let hex):
            let (dark, light) = HSB(hex: hex).normalizedAccent()
            return generated(dark: dark, light: light, whiteLabel: dark.prefersWhiteLabel)
        }
    }

    /// The original design, exactly.
    private static let ember = ThemePalette(
        shell: Color(light: 0xFFFFFF, dark: 0x000000),
        background: Color(light: 0xF6F2ED, dark: 0x171311),
        foreground: Color(light: 0x1C1512, dark: 0xF6F0E5),
        card: Color(light: 0xFFFFFF, dark: 0x261E1A),
        popover: Color(light: 0xFFFFFF, dark: 0x211915),
        primary: Color(light: 0xF25200, dark: RautaBrand.primary),
        primarySoft: Color(light: 0xF46A1E, dark: 0xFF7E38),
        primarySofter: Color(light: 0xE0662A, dark: 0xFF9B68),
        primaryForeground: Color(hex: RautaBrand.onPrimary),
        primaryGradientStart: Color(hex: RautaBrand.gradientStart),
        primaryGradientEnd: Color(hex: RautaBrand.gradientEnd),
        secondary: Color(light: 0xEFE8E0, dark: 0x302620),
        secondaryForeground: Color(light: 0x3B2F28, dark: 0xE9DFD2),
        muted: Color(light: 0xEDE6DE, dark: 0x2B231E),
        mutedForeground: Color(light: 0x76685C, dark: 0xB1A396),
        border: Color(light: 0x6B4A2A, dark: 0xD9AD6C, lightOpacity: 0.14, darkOpacity: 0.20),
        input: Color(light: 0x6B4A2A, dark: 0xD9AD6C, lightOpacity: 0.10, darkOpacity: 0.17),
        scrim: Color(light: 0x1C1512, dark: 0x000000, lightOpacity: 0.28, darkOpacity: 0.6),
        obsidian: Color(light: 0x5C4636, dark: 0x100D0B),
        oxblood: Color(light: 0xFFD2BD, dark: 0x501D16),
        rust: Color(light: 0xB8432A, dark: 0x983723),
        ember: Color(light: 0xE5452A, dark: 0xF34D32),
        bodyResting: Color(light: 0xD5C8BC, dark: 0x3D322B),
        bodySilhouette: Color(light: 0xE9E1D8, dark: 0x2D241F),
        bodyRestingShadow: Color(light: 0x5C4636, dark: 0x000000, lightOpacity: 0.16, darkOpacity: 0.45),
        hueShift: 0
    )

    /// The original palette's recipe, applied to another accent.
    private static func generated(dark: HSB, light: HSB, whiteLabel: Bool) -> ThemePalette {
        let h = dark.hue
        // Neutrals carry the accent's hue as the originals carry orange's, at
        // half the strength: warm brown is the brand's own ground, and the same
        // weight of green or pink reads as a colour rather than a tint.
        func neutral(_ offset: Double, _ saturation: Double, _ brightness: Double) -> UIColor {
            HSB(hue: h + offset, saturation: saturation * 0.5, brightness: brightness).color
        }
        func pair(_ light: UIColor, _ dark: UIColor) -> Color {
            Color(uiColor: UIColor(light: light, dark: dark))
        }
        func pair(_ light: UIColor, _ dark: UIColor, lightAlpha: CGFloat, darkAlpha: CGFloat) -> Color {
            Color(uiColor: UIColor(
                light: light.withAlphaComponent(lightAlpha),
                dark: dark.withAlphaComponent(darkAlpha)
            ))
        }
        func accent(_ offset: Double, _ saturation: Double, _ brightness: Double, from base: HSB) -> UIColor {
            HSB(
                hue: base.hue + offset,
                saturation: base.saturation * saturation,
                brightness: min(1, base.brightness * brightness)
            ).color
        }
        let white = UIColor.white

        return ThemePalette(
            shell: Color(light: 0xFFFFFF, dark: 0x000000),
            background: pair(neutral(12.9, 0.037, 0.965), neutral(-0.5, 0.261, 0.090)),
            foreground: pair(neutral(-2.5, 0.357, 0.110), neutral(18.4, 0.069, 0.965)),
            card: pair(white, neutral(-0.5, 0.316, 0.149)),
            popover: pair(white, neutral(-0.5, 0.364, 0.129)),
            primary: pair(light.color, dark.color),
            primarySoft: pair(accent(0.8, 0.877, 1.008, from: light), accent(0.6, 0.780, 1, from: dark)),
            primarySofter: pair(accent(-0.7, 0.812, 0.925, from: light), accent(-0.2, 0.592, 1, from: dark)),
            primaryForeground: whiteLabel ? .white : Color(hex: RautaBrand.onPrimary),
            primaryGradientStart: Color(uiColor: dark.shifted(3.8).color),
            primaryGradientEnd: Color(uiColor: dark.shifted(-5.6).color),
            secondary: pair(neutral(11.5, 0.063, 0.937), neutral(2.0, 0.333, 0.188)),
            secondaryForeground: pair(neutral(1.6, 0.322, 0.231), neutral(13.4, 0.099, 0.914)),
            muted: pair(neutral(11.5, 0.063, 0.929), neutral(2.6, 0.302, 0.169)),
            mutedForeground: pair(neutral(7.2, 0.220, 0.463), neutral(8.4, 0.153, 0.694)),
            border: pair(neutral(9.1, 0.607, 0.420), neutral(15.3, 0.502, 0.851), lightAlpha: 0.14, darkAlpha: 0.20),
            input: pair(neutral(9.1, 0.607, 0.420), neutral(15.3, 0.502, 0.851), lightAlpha: 0.10, darkAlpha: 0.17),
            scrim: pair(neutral(-2.5, 0.357, 0.110), .black, lightAlpha: 0.28, darkAlpha: 0.6),
            obsidian: pair(neutral(4.8, 0.413, 0.361), neutral(3.5, 0.312, 0.063)),
            oxblood: pair(
                HSB(hue: h - 1.4, saturation: 0.259, brightness: 1).color,
                accent(-13.2, 0.725, 0.314, from: dark)
            ),
            rust: pair(accent(-9.9, 0.772, 0.722, from: dark), accent(-10.2, 0.770, 0.596, from: dark)),
            ember: pair(accent(-11.8, 0.817, 0.898, from: dark), accent(-12.1, 0.794, 0.953, from: dark)),
            bodyResting: pair(neutral(8.3, 0.117, 0.835), neutral(2.9, 0.295, 0.239)),
            bodySilhouette: pair(neutral(11.3, 0.073, 0.914), neutral(1.0, 0.311, 0.176)),
            bodyRestingShadow: pair(neutral(4.8, 0.413, 0.361), .black, lightAlpha: 0.16, darkAlpha: 0.45),
            hueShift: HSB.signedDegrees(h - HSB.brandHue)
        )
    }
}

// MARK: - Store

/// The palette in use, as observable state.
///
/// `Theme`'s tokens read through here, so every view that draws with one is
/// redrawn the moment the accent changes — no relaunch, no rebuilt hierarchy,
/// no lost scroll position.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    private(set) var accent: AppAccent = .default
    private(set) var palette: ThemePalette = .make(.default)

    private init() {}

    func apply(_ next: AppAccent) {
        guard next != accent else { return }
        accent = next
        palette = .make(next)
    }
}

// MARK: - Colour maths

/// A colour as hue (degrees), saturation and brightness.
struct HSB: Hashable, Sendable {
    var hue: Double
    var saturation: Double
    var brightness: Double

    /// The brand orange's hue, which every hue shift is measured from.
    static let brandHue = HSB(hex: RautaBrand.primary).hue

    init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = hue
        self.saturation = max(0, min(1, saturation))
        self.brightness = max(0, min(1, brightness))
    }

    init(hex: UInt32) {
        let color = UIColor(hex: hex)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        self.init(hue: Double(h) * 360, saturation: Double(s), brightness: Double(b))
    }

    init(_ color: UIColor) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        self.init(hue: Double(h) * 360, saturation: Double(s), brightness: Double(b))
    }

    var color: UIColor {
        let wrapped = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return UIColor(
            hue: CGFloat(wrapped / 360),
            saturation: CGFloat(saturation),
            brightness: CGFloat(brightness),
            alpha: 1
        )
    }

    var hex: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt32((r * 255).rounded()) << 16) | (UInt32((g * 255).rounded()) << 8) | UInt32((b * 255).rounded())
    }

    func shifted(_ degrees: Double) -> HSB {
        HSB(hue: hue + degrees, saturation: saturation, brightness: brightness)
    }

    /// WCAG relative luminance.
    var luminance: Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    func contrast(with other: HSB) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// A white label only when it is clearly the more readable one; otherwise
    /// the brand's near-black, as on the orange.
    var prefersWhiteLabel: Bool {
        contrast(with: HSB(hue: 0, saturation: 0, brightness: 1)) >= 3.4
    }

    /// Any picked colour, made usable as an accent: vivid enough to be seen on
    /// the dark theme, and a light-theme shade deepened until it reads on
    /// white. A grey or a black cannot be an accent, so it is given colour.
    func normalizedAccent() -> (dark: HSB, light: HSB) {
        let dark = HSB(hue: hue, saturation: max(saturation, 0.5), brightness: max(brightness, 0.82))
        let white = HSB(hue: 0, saturation: 0, brightness: 1)
        var light = HSB(hue: hue, saturation: min(1, dark.saturation * 1.05), brightness: dark.brightness * 0.95)
        while light.contrast(with: white) < 3.4, light.brightness > 0.3 {
            light.brightness -= 0.02
        }
        return (dark, light)
    }

    /// An angle folded into -180…180.
    static func signedDegrees(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }
}
