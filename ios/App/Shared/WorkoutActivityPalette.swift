import Foundation

struct WorkoutActivityColor {
    let red: Double
    let green: Double
    let blue: Double
}

/// The app's dark palette, resolved out of the OKLCH tokens in `index.css` so
/// the Lock Screen card and the Dynamic Island are recognisably the same app.
enum WorkoutActivityPalette {
    /// `#0e0e0f` — the shell behind every screen.
    static let background = WorkoutActivityColor(red: 0.055, green: 0.055, blue: 0.059)
    /// `--card`, `oklch(0.205 0 0)`. Exercise frames are composited onto this
    /// exact color, so anything drawing one must use it as the tile behind.
    static let surface = WorkoutActivityColor(red: 0.090, green: 0.090, blue: 0.090)
    /// `--primary`, `oklch(0.72 0.2 42)`.
    static let accent = WorkoutActivityColor(red: 1.000, green: 0.435, blue: 0.153)
    /// `--foreground`, `oklch(0.96 0 0)`.
    static let text = WorkoutActivityColor(red: 0.949, green: 0.949, blue: 0.949)
    /// `--muted-foreground`, `oklch(0.65 0 0)`.
    static let mutedText = WorkoutActivityColor(red: 0.561, green: 0.561, blue: 0.561)
}
