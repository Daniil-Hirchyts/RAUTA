import Foundation

/// A workout's elapsed time as "MM:SS", widening to "H:MM:SS" only once it
/// passes an hour — one shape for the app, its Live Activity and the watch, so
/// the Lock Screen, the wrist and the screen agree.
nonisolated enum ElapsedClock {
    static func format(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total / 60) % 60
        let rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%02d:%02d", minutes, rest)
    }
}
