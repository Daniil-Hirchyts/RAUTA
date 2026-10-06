import SwiftUI

/// RAUTA's own orange: the accent the app starts in, and the one the Lock
/// Screen and the watch fall back to until the phone says otherwise. One set of
/// values for every target, so none of them drifts from the others.
nonisolated enum RautaBrand {
    static let primary: UInt32 = 0xFF5700
    static let gradientStart: UInt32 = 0xFF6700
    static let gradientEnd: UInt32 = 0xFF3F00
    /// The near-black a label on the orange is set in.
    static let onPrimary: UInt32 = 0x060606
}

extension Color {
    /// A colour from `0xRRGGBB`, in sRGB.
    nonisolated init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
