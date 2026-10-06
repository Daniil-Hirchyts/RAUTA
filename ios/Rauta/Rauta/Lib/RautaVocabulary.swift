import CoreGraphics
import Foundation

/// What RAUTA can express, as a vocabulary rather than a pile of animation
/// names.
///
/// A screen should be able to say "the week was generated" or "this set was
/// hard" without knowing how the character draws it. So the names live here
/// once, the rig binding lives in the character once, and every screen speaks in
/// states.
///
/// All of it is pure — here and in RautaIdle, RautaTouch, RautaGaze and
/// RautaCues: the clock and the randomness are arguments, so the character's
/// personality can be reasoned about without a frame loop.
enum RautaMood: String, CaseIterable, Sendable {
    case calm, curious, thinking, working, bored, blocked, sleepy, focused
    case excited, happy, proud, confused, skeptical, nervous, playful, listening
    /// Bracing for a set: wedge eyes and a held forward lean.
    case determined
    /// Spent after an all-out effort: heavy breaths, a slumped handle.
    case exhausted
    /// Getting its breath back between sets: eyes closed, slow in and out.
    case recovering
    case cheeky

    /// The artwork's own order.
    var status: Int { RautaMood.allCases.firstIndex(of: self) ?? 0 }

    /// How animated the resting expression is.
    var intensity: Double {
        switch self {
        case .calm: return 0.42
        case .curious: return 0.52
        case .thinking: return 0.46
        case .working: return 0.62
        case .bored: return 0.30
        case .blocked: return 0.66
        case .sleepy: return 0.24
        case .focused: return 0.56
        case .excited: return 0.86
        case .happy: return 0.68
        case .proud: return 0.70
        case .confused: return 0.54
        case .skeptical: return 0.48
        case .nervous: return 0.72
        case .playful: return 0.76
        case .listening: return 0.50
        case .determined: return 0.60
        case .exhausted: return 0.28
        case .recovering: return 0.32
        case .cheeky: return 0.74
        }
    }

    /// Six moods own a scripted head turn. While one of them plays, the rig
    /// ignores `facing`, so a hand turning the character has to borrow a mood
    /// that lets it.
    var hasScriptedYaw: Bool {
        switch self {
        case .curious, .thinking, .working, .bored, .confused, .playful: return true
        default: return false
        }
    }

    /// The resting expressions a screen picks when it has nothing particular to
    /// say. Only these give way to what is going on around the character; a mood
    /// a screen chose on purpose — excited on the welcome, proud at the end — is
    /// kept.
    var isNeutral: Bool {
        self == .calm || self == .focused || self == .listening
    }

    /// Moods whose motion is the expression itself — a hop, a hammer, a
    /// tremor — and so need a smoother loop between moments than a breath.
    var keepsMoving: Bool {
        switch self {
        case .excited, .working, .playful, .nervous: return true
        default: return false
        }
    }
}

/// A one-shot: something happens, RAUTA reacts, the mood underneath returns.
enum RautaReaction: String, CaseIterable, Sendable {
    case acknowledge, surprise, celebrate, frustrated, relieved, wobble
    case gearUp, laugh, tapped, recoil, peek, blink, blinkDouble, wink
    case spinLeft, spinRight, turnaround
    /// Compresses, then rises into a strong stance.
    case powerUp
    /// A victory hop with star eyes.
    case personalBest
    /// Two encouraging bounces.
    case cheer
    /// Happy arc eyes and a gentle nod.
    case appreciate
    /// A squint, then eyes popping round.
    case idea
    /// Wobbling it off after one spin too many.
    case dizzy

    /// The clip's length in the artwork, in seconds.
    var duration: Double {
        switch self {
        case .acknowledge: return 0.55
        case .surprise: return 0.80
        case .celebrate: return 1.50
        case .frustrated: return 1.00
        case .relieved: return 1.10
        case .wobble: return 1.00
        case .gearUp: return 0.90
        case .laugh: return 1.10
        case .tapped: return 0.50
        case .recoil: return 0.90
        case .peek: return 1.60
        case .blink: return 0.23
        case .blinkDouble: return 0.50
        case .wink: return 0.45
        case .spinLeft, .spinRight: return 1.50
        case .turnaround: return 7.00
        case .powerUp: return 1.50
        case .personalBest: return 1.75
        case .cheer: return 1.25
        case .appreciate: return 1.50
        case .idea: return 1.00
        case .dizzy: return 2.00
        }
    }

    /// Blinks live on their own layer and never interrupt the body, so they
    /// never need to hold the floor.
    var isEyesOnly: Bool {
        self == .blink || self == .blinkDouble || self == .wink
    }

    /// What plays instead when large motion is not welcome: Reduce Motion is on.
    /// Turns become a look, jumps and knocks become a nod or a squash.
    var gentle: RautaReaction {
        switch self {
        case .spinLeft, .spinRight, .celebrate, .powerUp, .personalBest, .cheer: return .acknowledge
        case .turnaround, .peek, .surprise, .dizzy: return .blinkDouble
        case .wobble, .recoil: return .tapped
        default: return self
        }
    }

    /// What plays instead on a character the size of a button, where a seven
    /// second tour reads as the icon breaking rather than as a thought.
    var compact: RautaReaction {
        self == .turnaround ? .peek : self
    }
}

/// How much room the character has where it stands.
enum RautaPlacement: Sendable {
    /// Header and tab-bar sizes.
    case badge
    /// A character that is the subject of the screen.
    case hero

    init(width: CGFloat) {
        self = width < 72 ? .badge : .hero
    }
}

/// Who asked for the behaviour, and therefore who wins.
///
/// The engine and the app have something to say and must never be talked over.
/// What the person is physically doing to the character comes next, because it
/// is still their action. Ambient idle is the character having a thought of its
/// own, and yields to both.
enum RautaSource: String, Sendable {
    case explicit, interaction, ambient

    var priority: Int {
        switch self {
        case .explicit: return 3
        case .interaction: return 2
        case .ambient: return 1
        }
    }

    /// The shortest time a source holds the floor after it plays, in
    /// milliseconds; a longer clip holds it for its own length. Only as long as
    /// the answer is actually playing: a finger on the character a moment after
    /// a saved set must still get a reaction.
    var holdMs: Double {
        switch self {
        case .explicit: return 600
        case .interaction: return 400
        case .ambient: return 0
        }
    }

    /// The shortest gap between two reactions from the same source. Without it a
    /// stream of events becomes a stutter of restarted animations. Touch is kept
    /// short on purpose: a finger tapping again expects an answer again.
    var cooldownMs: Double {
        switch self {
        case .explicit: return 260
        case .interaction: return 240
        case .ambient: return 2400
        }
    }
}

/// How long anything happening keeps the character from having an idle thought
/// of its own, in milliseconds.
let RAUTA_QUIET_AFTER_MS = 2600.0

struct RautaActivity {
    /// The source that currently holds the floor, and until when.
    var holder: RautaSource?
    var holdUntil: Double = 0
    var lastInteraction: RautaReaction?
    /// When each source last played, for its own cooldown.
    var lastPlayedAt: [String: Double] = [
        RautaSource.explicit.rawValue: -.greatestFiniteMagnitude,
        RautaSource.interaction.rawValue: -.greatestFiniteMagnitude,
        RautaSource.ambient.rawValue: -.greatestFiniteMagnitude,
    ]
    /// When ambient idle is next allowed to have a thought.
    var ambientDueAt: Double = 0

    init(now: Double = 0) {
        ambientDueAt = now + RAUTA_QUIET_AFTER_MS
    }

    func isHeld(at now: Double) -> Bool {
        holder != nil && now < holdUntil
    }
}

enum RautaScheduler {
    struct Outcome {
        var activity: RautaActivity
        var play: RautaReaction?
    }

    /// Whether a reaction gets to play, and the activity that follows.
    ///
    /// A request is refused when a higher-priority source still holds the floor,
    /// or when its own source is still cooling down. Refusing is the point — it
    /// is what stops an idle blink from cutting off the celebration of a finished
    /// week.
    static func request(
        _ activity: RautaActivity,
        source: RautaSource,
        reaction: RautaReaction,
        now: Double
    ) -> Outcome {
        let lastPlayed = activity.lastPlayedAt[source.rawValue] ?? -.greatestFiniteMagnitude

        // Eyes never compete with the body: a blink only answers to its own
        // source's cooldown.
        if reaction.isEyesOnly {
            if source == .ambient, (now - lastPlayed) < source.cooldownMs {
                return Outcome(activity: activity, play: nil)
            }
            var next = activity
            next.lastPlayedAt[source.rawValue] = now
            return Outcome(activity: next, play: reaction)
        }

        // A source never blocks itself out of continuing; only its cooldown
        // does.
        let holding = activity.isHeld(at: now)
            && activity.holder.map { $0.priority >= source.priority && $0 != source } == true

        let impactInterrupt = source == .interaction
            && (reaction == .recoil || reaction == .wobble)
            && [RautaReaction.surprise, .peek, .spinLeft, .spinRight]
                .contains(activity.lastInteraction ?? .blink)

        let cooling = !impactInterrupt && (now - lastPlayed) < source.cooldownMs

        if holding || cooling { return Outcome(activity: activity, play: nil) }

        var next = activity
        next.holder = source
        if source == .interaction { next.lastInteraction = reaction }
        next.holdUntil = now + Swift.max(source.holdMs, reaction.duration * 1000)
        next.lastPlayedAt[source.rawValue] = now
        // Anything happening pushes the character's own next thought back.
        if source != .ambient {
            next.ambientDueAt = Swift.max(next.ambientDueAt, next.holdUntil + RAUTA_QUIET_AFTER_MS * 0.5)
        }
        return Outcome(activity: next, play: reaction)
    }
}
