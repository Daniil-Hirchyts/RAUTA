import SwiftUI

/// RAUTA moving on the Lock Screen, with no updates from the app.
///
/// A Live Activity is drawn once and left alone; what still moves on its own
/// is a timer's text. So the frames of RAUTA's loop are baked into fonts whose
/// digits are pictures (`scripts/rauta-frames/build.py`), and a stack of
/// `Text(date, style: .timer)` views in those fonts is revealed one at a time
/// by timers in a mask font. Each layer shows for 1/F of every two seconds,
/// and its own seconds digit picks which of its frames — so the loop plays at
/// F frames a second for as long as the card is on screen.
///
/// The layout follows how the system draws a timer in a widget: it reserves
/// room for the longest reading and aligns the text inside it, so each timer
/// gets a wide frame, aligned trailing, and is shifted so that its last
/// character — the seconds — lands in the square.
struct RautaTimerSprite: View {
    /// Which loop: one of ``RautaSpriteFonts/loops``.
    var loop: String
    /// The instant every timer counts from. Must stay the same across
    /// renders, or the animation would jump each time the card is redrawn.
    var epoch: Date
    var size: CGFloat
    /// A still frame instead: paused, the wrist down on Always On, Reduce
    /// Motion. On Always On a timer reads in whole minutes, so it could not
    /// animate anyway.
    var still = false

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var family: String { "Rauta" + loop.prefix(1).uppercased() + loop.dropFirst() }

    var body: some View {
        let fps = Double(RautaSpriteFonts.framesPerSecond)
        ZStack {
            if still || isLuminanceReduced || reduceMotion {
                // The first frame, held: a digit, not a timer. A digit is
                // one square wide, so it simply fills the square — unlike a
                // timer, which lays itself out across the room reserved for
                // its longest reading.
                Text("0")
                    .font(.custom("\(family)0", fixedSize: size))
                    .frame(width: size, height: size)
            } else {
                ForEach(0..<RautaSpriteFonts.layers, id: \.self) { layer in
                    Text(epoch.addingTimeInterval(Double(layer) / fps), style: .timer)
                        .font(.custom("\(family)\(layer)", fixedSize: size))
                        .lastCharacterInSquare(size)
                        .mask {
                            SpriteMask(start: epoch.addingTimeInterval(Double(layer + 1) / fps + 1))
                                .frame(width: size, height: size)
                        }
                }
            }
        }
        .frame(width: size, height: size)
        .clipped()
        // Digits must be the font's own: a locale with its own numerals would
        // draw those instead of frames.
        .environment(\.locale, Locale(identifier: "en_US_POSIX"))
        .accessibilityHidden(true)
    }
}

/// A timer in the mask font: a solid square in even seconds, nothing in odd.
private struct SpriteMask: View {
    var start: Date

    var body: some View {
        GeometryReader { proxy in
            let side = max(proxy.size.width, proxy.size.height)
            Text(start, style: .timer)
                .font(.custom(RautaSpriteFonts.mask, fixedSize: side))
                .lastCharacterInSquare(side, fromLeadingEdge: true)
        }
        .clipped()
    }
}

private extension View {
    /// A timer's last character placed in a `side`-wide square: room for nine
    /// characters, the text aligned to the end of it, shifted back so the
    /// last one lands in the square. Centred in its parent unless laid out
    /// from a leading edge, as inside a geometry reader.
    func lastCharacterInSquare(_ side: CGFloat, fromLeadingEdge: Bool = false) -> some View {
        frame(width: side * 9, height: side)
            .multilineTextAlignment(.trailing)
            .offset(x: -side * (fromLeadingEdge ? 8 : 4))
    }
}
