import Foundation

struct WorkoutActivityColor {
    let red: Double
    let green: Double
    let blue: Double
}

extension WorkoutActivityColor {
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The app's dark palette, resolved out of the OKLCH tokens in `index.css` so
/// the Lock Screen card and the Dynamic Island are recognisably the same app.
enum WorkoutActivityPalette {
    /// `#0e0e0f` — the shell behind every screen.
    static let background = WorkoutActivityColor(red: 0.055, green: 0.055, blue: 0.059)
    /// `--primary`, `oklch(0.715 0.245 42.5)`, `#FF6200`.
    static let accent = WorkoutActivityColor(red: 1.000, green: 0.384, blue: 0.000)
    /// `--foreground`, `oklch(0.96 0 0)`.
    static let text = WorkoutActivityColor(red: 0.949, green: 0.949, blue: 0.949)
    /// `--muted-foreground`, `oklch(0.65 0 0)`.
    static let mutedText = WorkoutActivityColor(red: 0.561, green: 0.561, blue: 0.561)

    /// The accent chosen in the app's Settings, carried in the activity's
    /// state; a card started before accents existed keeps the brand orange.
    static func accent(_ hex: Int?) -> WorkoutActivityColor {
        hex.map(WorkoutActivityColor.init(hex:)) ?? accent
    }
}
