import RiveRuntime
import SwiftUI

/// Uses the exact artboard and state machine shipped by the React app.
///
/// The view is a thin shell. What this character does with its body lives in
/// ``RautaPerformer``; what RAUTA knows about the app lives in
/// ``RautaDirector``; what it can express lives in `RautaVocabulary`.
struct RautaCharacter: View {
    var mood: RautaMood = .calm
    var reactionKey = ""
    var reaction: RautaReaction?
    var onActivate: (() -> Void)?
    /// A horizontal turn to hold, in degrees, for a character being steered —
    /// flying in on the launch, say. Nil lets it face you as usual.
    var yaw: Double?
    /// A frame rate to hold, for a character in a piece of choreography that
    /// must not change pace mid-move. Nil lets it pace itself.
    var framesPerSecond: Int?
    /// Whether a change of `mood` comes with the blink a change of feeling
    /// usually brings. Choreography blending one into the next turns it off.
    var moodBlinks = true
    /// A point on screen, in global coordinates, for the eyes to go to.
    var lookAt: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.rautaOnStage) private var onStage
    @Environment(\.rautaQuiet) private var quiet
    @StateObject private var performer = RautaPerformer()
    private let speech = RautaSpeech.shared
    @State private var leash = CGSize.zero
    /// Resets when the touch ends *or is cancelled*; only a cancel reaches
    /// `touchCancelled`, since `onEnded` has already settled a normal lift.
    @GestureState private var touching = false

    var body: some View {
        performer.rig.view()
            .offset(leash)
            // The laid-out size picks the placement, the frame on screen is
            // where it is: a character scaled down in flight is still a hero.
            .onGeometryChange(for: PlacedFrame.self) { proxy in
                PlacedFrame(global: proxy.frame(in: .global), width: proxy.size.width)
            } action: { placed in
                performer.place(placed.global, layoutWidth: placed.width)
            }
            .onAppear {
                performer.appear(mood: mood, reducedMotion: reducedMotion, onStage: onStage, quiet: quiet)
                if let framesPerSecond { performer.pin(framesPerSecond: framesPerSecond) }
                if let reaction { performer.explicit(reaction) }
                if let yaw { performer.hold(yaw: yaw) }
            }
            .onDisappear { performer.disappear() }
            .onChange(of: mood) { _, next in performer.setMood(next, blinks: moodBlinks) }
            .onChange(of: lookAt) { _, point in if let point { performer.look(at: point) } }
            .onChange(of: quiet) { _, next in performer.setQuiet(next) }
            .onChange(of: framesPerSecond) { _, next in performer.pin(framesPerSecond: next) }
            // What RAUTA says, the character that answers for it also shows:
            // the look a line asks for, and a beat as it starts.
            .onChange(of: speech.line) { _, line in performer.hear(line) }
            .onChange(of: reactionKey) { _, _ in performer.explicit(reaction) }
            .onChange(of: yaw) { _, next in performer.hold(yaw: next) }
            .onChange(of: reducedMotion) { _, next in performer.setReducedMotion(next) }
            .onChange(of: scenePhase) { _, next in performer.setSceneActive(next == .active) }
            .onChange(of: onStage) { _, next in performer.setOnStage(next) }
            .contentShape(Rectangle())
            .gesture(
                // One gesture for every kind of touch, so a tap, a held press and
                // a drag are told apart by what the finger did rather than by
                // which recognizer won.
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, active, _ in active = true }
                    .onChanged { value in leash = performer.touchChanged(value) }
                    .onEnded { value in
                        if performer.touchEnded(value) {
                            onActivate?()
                            Haptics.trigger(.light)
                        }
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.5)) { leash = .zero }
                    }
            )
            .onChange(of: touching) { _, active in
                guard !active, performer.touchCancelled() else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.5)) { leash = .zero }
            }
            .accessibilityLabel(onActivate == nil ? "Interact with RAUTA" : "Open RAUTA actions")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                performer.tap()
                onActivate?()
            }
    }
}

nonisolated private struct PlacedFrame: Equatable, Sendable {
    var global: CGRect
    var width: CGFloat
}

private struct RautaOnStageKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False for a character on a page that another page currently covers. It
    /// keeps its place in the layout but stops performing, and never answers a
    /// cue nobody can see.
    var rautaOnStage: Bool {
        get { self[RautaOnStageKey.self] }
        set { self[RautaOnStageKey.self] = newValue }
    }

    /// True for a character running unseen, about to take over from another —
    /// the tab bar's, as the launch's lands in its seat. It answers nothing
    /// and claims nothing until it is in the scene.
    @Entry var rautaQuiet = false
}

/// The artwork, parsed once for every character in the app rather than once per
/// placement.
@MainActor
enum RautaArtwork {
    static let file: RiveFile? = try? RiveFile(name: "Media/rauta", extension: ".riv", in: .main, loadCdn: false)

    static func makeRig() -> RautaRig {
        guard let file else {
            return RautaRig(
                fileName: "Media/rauta",
                stateMachineName: "KettlebellBotMachine",
                autoPlay: true,
                artboardName: "KettlebellBot",
                loadCdn: false
            )
        }
        return RautaRig(
            RiveModel(riveFile: file),
            stateMachineName: "KettlebellBotMachine",
            autoPlay: true,
            artboardName: "KettlebellBot"
        )
    }
}

/// The rig, with a heartbeat. The runtime reports every frame it advances, and
/// the performer moves the eyes and the turn on that beat — in step with what is
/// drawn, and only while anything is drawn at all.
///
/// Nonisolated like the runtime class it extends. The runtime reports frames
/// from its main-thread display link, which the assertion below checks.
nonisolated final class RautaRig: RiveViewModel {
    var onAdvance: (@MainActor @Sendable (Double) -> Void)?

    override func player(didAdvanceby seconds: Double, riveModel: RiveModel?) {
        let onAdvance = onAdvance
        MainActor.assumeIsolated { onAdvance?(seconds) }
    }
}

struct CompanionAction: Identifiable {
    var title: String
    var systemImage: String = "sparkles"
    var primary = false
    var action: () -> Void
    var id: String { title }
}

/// A compact header-sized RAUTA on a static glass circle. The character owns
/// any interaction; the glass behind it never flexes like a button.
struct RautaHeaderBadge: View {
    var mood: RautaMood = .focused
    var reactionKey = ""
    var reaction: RautaReaction?
    var onActivate: (() -> Void)?
    /// Whether RAUTA's lines rise from this one. The workout player's keeps
    /// quiet, so nothing but the work competes for attention there.
    var speaks = true

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 44, height: 44)
                .glassSurface(
                    .regular,
                    in: Circle()
                )
                .allowsHitTesting(false)

            RautaCharacter(
                mood: mood,
                reactionKey: reactionKey,
                reaction: reaction,
                onActivate: onActivate
            )
            .frame(width: 54, height: 54)
            .frame(width: 44, height: 44)
        }
        .frame(width: 44, height: 44)
        .modifier(SpeakerRole(speaks: speaks))
    }
}

private struct SpeakerRole: ViewModifier {
    let speaks: Bool

    func body(content: Content) -> some View {
        if speaks {
            content.rautaSpeaker()
        } else {
            content
        }
    }
}
