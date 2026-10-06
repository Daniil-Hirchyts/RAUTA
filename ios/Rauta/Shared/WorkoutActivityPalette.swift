import Foundation

nonisolated struct WorkoutActivityColor: Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

nonisolated extension WorkoutActivityColor {
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The app's dark palette as the Lock Screen card and the Dynamic Island draw
/// it, so they read as the same app.
nonisolated enum WorkoutActivityPalette {
    /// `#0e0e0f` — the shell behind every screen.
    static let background = WorkoutActivityColor(red: 0.055, green: 0.055, blue: 0.059)
    /// The brand orange, for a card from a build that did not carry its accent.
    static let accent = WorkoutActivityColor(hex: Int(RautaBrand.primary))
    /// Text.
    static let text = WorkoutActivityColor(red: 0.949, green: 0.949, blue: 0.949)
    /// Secondary text.
    static let mutedText = WorkoutActivityColor(red: 0.561, green: 0.561, blue: 0.561)

    /// The accent chosen in the app's Settings, carried in the activity's
    /// state; a card started before accents existed keeps the brand orange.
    static func accent(_ hex: Int?) -> WorkoutActivityColor {
        hex.map(WorkoutActivityColor.init(hex:)) ?? accent
    }
}
