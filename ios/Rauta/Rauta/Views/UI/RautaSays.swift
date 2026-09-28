import SwiftUI

/// RAUTA on the page, saying something: the character and its line together,
/// for the screens where RAUTA is the one doing the work — building a week,
/// closing a workout.
///
/// The line sits in the same glass as RAUTA's bubbles, joined to the character
/// by the same trail. A `transient` line is spoken rather than printed: it
/// pours out of RAUTA when there is something new to say, folds back once there
/// has been time to read it, and comes out again when RAUTA is tapped. Its room
/// stays reserved, so the page under it never jumps.
struct RautaSays: View {
    enum Layout {
        /// The line under RAUTA, centred: RAUTA is the subject of the screen.
        case stacked
        /// The line beside RAUTA: RAUTA introduces what is below.
        case beside
    }

    var text: String
    var mood: RautaMood = .calm
    /// Played whenever `reactionKey` changes.
    var reaction: RautaReaction?
    var reactionKey = ""
    var size: CGFloat = 104
    var layout: Layout = .stacked
    var transient = false
    /// Lets the empty margin above the artwork overlap what is above, so a
    /// larger RAUTA fits in the same room. For a page tight on height.
    var trims = false

    @State private var showing = true
    /// Bumped by a tap on RAUTA, to say the line again.
    @State private var replay = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let glass = GlassTone.tinted(Theme.card.opacity(0.5))

    var body: some View {
        content
            .task(id: "\(text)|\(replay)") { await speak() }
    }

    @ViewBuilder private var content: some View {
        // The artwork sits inside its frame with room around it; the trail
        // tucks into that room so it starts at RAUTA, not beside it.
        switch layout {
        case .stacked:
            VStack(spacing: 3) {
                character
                    .padding(.top, trims ? -size * 0.12 : 0)
                trail(axis: .vertical)
                    .padding(.top, -size * 0.12)
                    .modifier(Spoken(showing: showing, anchor: .top, reduceMotion: reduceMotion, delay: 0))
                panel
                    .multilineTextAlignment(.center)
                    .modifier(Spoken(showing: showing, anchor: .top, reduceMotion: reduceMotion, delay: 0.06))
            }
        case .beside:
            HStack(spacing: 3) {
                character
                trail(axis: .horizontal)
                    .padding(.leading, -size * 0.14)
                    .modifier(Spoken(showing: showing, anchor: .leading, reduceMotion: reduceMotion, delay: 0))
                panel
                    .modifier(Spoken(showing: showing, anchor: .leading, reduceMotion: reduceMotion, delay: 0.06))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var character: some View {
        RautaCharacter(
            mood: mood,
            reactionKey: reactionKey,
            reaction: reaction,
            onActivate: transient ? { replay += 1 } : nil
        )
        .frame(width: size, height: size)
        .accessibilityHidden(!transient)
    }

    private var panel: some View {
        Text(text)
            .font(Theme.sans(17, weight: .semibold))
            .tracking(-0.2)
            .lineSpacing(2)
            .foregroundStyle(Theme.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: text)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .glassSurface(Self.glass, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .animation(.spring(response: 0.36, dampingFraction: 0.82), value: text)
    }

    private func trail(axis: Axis) -> some View {
        let small = Color.clear.frame(width: 7, height: 7).glassSurface(Self.glass, in: Circle())
        let large = Color.clear.frame(width: 13, height: 13).glassSurface(Self.glass, in: Circle())
        return Group {
            if axis == .vertical {
                VStack(spacing: 3) { small; large }
            } else {
                HStack(spacing: 3) { small; large }
            }
        }
        .accessibilityHidden(true)
    }

    /// Out, then — for a transient line — back in once it has been read.
    private func speak() async {
        guard transient else {
            showing = true
            return
        }
        showing = true
        AccessibilityNotification.Announcement(text).post()
        let seconds = min(8, 3 + Double(text.count) * 0.05)
        try? await Task.sleep(for: .seconds(seconds))
        guard !Task.isCancelled else { return }
        showing = false
    }
}

/// A part of the line pouring out of RAUTA, or folding back into it.
private struct Spoken: ViewModifier {
    let showing: Bool
    let anchor: UnitPoint
    let reduceMotion: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(showing || reduceMotion ? 1 : 0.4, anchor: anchor)
            .opacity(showing ? 1 : 0)
            .animation(
                showing
                    ? .spring(response: 0.38, dampingFraction: 0.76).delay(delay)
                    : .easeIn(duration: 0.2).delay(0.06 - delay),
                value: showing
            )
    }
}
