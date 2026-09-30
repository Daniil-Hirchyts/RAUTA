import SwiftUI

/// What RAUTA is saying right now, if anything: one line at a time.
///
/// RAUTA always had a line for everything it reacts to, and nobody ever saw
/// them. The director hands its lines here, and screens add their own — what
/// RAUTA is working on, what came of it, what it suggests next.
///
/// A line is shown by the RAUTA the person can see, rising out of it the way
/// its menu does. Where no RAUTA is speaking — the workout player keeps a quiet
/// one — the line is not shown at all rather than saved for later.
@MainActor @Observable
final class RautaSpeech {
    static let shared = RautaSpeech()

    struct Line: Equatable {
        let id: Int
        let text: String
        /// How RAUTA looks while this is up — working, while it works. Nil
        /// keeps whatever mood the character already has.
        let mood: RautaMood?
        /// A beat to play as the line starts. The director's lines leave it
        /// nil: the character already answered the cue they came from.
        let reaction: RautaReaction?
    }

    private(set) var line: Line?
    @ObservationIgnored private var nextId = 0
    @ObservationIgnored private var hushTask: Task<Void, Never>?

    /// Characters that speak for RAUTA while they are on stage, newest last.
    private struct Speaker {
        let id: UUID
        var frame: CGRect
        var lift: CGFloat
    }
    @ObservationIgnored private var speakers: [Speaker] = []

    /// A held line is work in progress, which its result replaces. It still
    /// goes eventually, so a result that never comes cannot leave it up.
    private static let longestHold: TimeInterval = 30

    private init() {}

    /// Says `text` in place of whatever was being said. It folds away once
    /// there has been time to read it, or, when it `holds`, once something
    /// else is said.
    func say(
        _ text: String,
        holds: Bool = false,
        mood: RautaMood? = nil,
        reaction: RautaReaction? = .acknowledge
    ) {
        guard !text.isEmpty else { return }
        nextId += 1
        let id = nextId
        line = Line(id: id, text: text, mood: mood, reaction: reaction)
        AccessibilityNotification.Announcement(text).post()
        // Heard only where it is seen: a line nobody is shown is not said.
        if show(text) { WorkoutAudio.voice(text, tone: RautaPhrase.Tone(reaction: reaction, mood: mood)) }

        hushTask?.cancel()
        let seconds = holds ? Self.longestHold : min(7, 2.8 + Double(text.count) * 0.05)
        hushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.line?.id == id else { return }
            self.hush()
        }
    }

    /// RAUTA at work: a line that stays up, with the working look, until the
    /// result is said.
    func working(_ text: String) {
        say(text, holds: true, mood: .working, reaction: .gearUp)
    }

    func hush() {
        hushTask?.cancel()
        hushTask = nil
        line = nil
        RautaThoughts.shared.hush()
    }

    // MARK: Speakers

    fileprivate func enter(_ id: UUID, frame: CGRect, lift: CGFloat) {
        speakers.removeAll { $0.id == id }
        speakers.append(Speaker(id: id, frame: frame, lift: lift))
    }

    fileprivate func move(_ id: UUID, frame: CGRect, lift: CGFloat) {
        guard let index = speakers.firstIndex(where: { $0.id == id }) else { return }
        speakers[index].frame = frame
        speakers[index].lift = lift
        RautaThoughts.shared.move(id, to: frame, lift: lift)
    }

    /// A speaker covered or gone takes its line with it: nothing it says may
    /// float over the page that covered it.
    fileprivate func leave(_ id: UUID) {
        speakers.removeAll { $0.id == id }
        RautaThoughts.shared.hush(id)
    }

    private func show(_ text: String) -> Bool {
        guard let speaker = speakers.last, speaker.frame != .zero else { return false }
        return RautaThoughts.shared.say(
            id: speaker.id,
            anchor: speaker.frame,
            lift: speaker.lift,
            text: text,
            close: { [weak self] in self?.hush() }
        )
    }
}

extension View {
    /// Makes this RAUTA the one that says RAUTA's lines while the person can
    /// see it. `lift` keeps the words clear of something between RAUTA and
    /// them — the exercise bar over the tabs.
    func rautaSpeaker(lift: CGFloat = 0) -> some View {
        modifier(RautaSpeakerAnchor(lift: lift))
    }
}

private struct RautaSpeakerAnchor: ViewModifier {
    var lift: CGFloat
    @Environment(\.rautaOnStage) private var onStage
    @State private var id = UUID()
    @State private var frame: CGRect = .zero
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { next in
                frame = next
                RautaSpeech.shared.move(id, frame: next, lift: lift)
            }
            .onAppear {
                appeared = true
                if onStage { RautaSpeech.shared.enter(id, frame: frame, lift: lift) }
            }
            .onDisappear {
                appeared = false
                RautaSpeech.shared.leave(id)
            }
            .onChange(of: onStage) { _, visible in
                guard appeared else { return }
                if visible {
                    RautaSpeech.shared.enter(id, frame: frame, lift: lift)
                } else {
                    RautaSpeech.shared.leave(id)
                }
            }
            .onChange(of: lift) { _, next in RautaSpeech.shared.move(id, frame: frame, lift: next) }
    }
}
