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
/// Everything in this file is pure: the clock and the randomness are arguments,
/// so the character's personality can be reasoned about without a frame loop.
enum RautaMood: String, CaseIterable, Sendable {
    case calm, curious, thinking, working, bored, blocked, sleepy, focused
    case excited, happy, proud, confused, skeptical, nervous, playful, listening

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
        case .spinLeft, .spinRight, .celebrate: return .acknowledge
        case .turnaround, .peek, .surprise: return .blinkDouble
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

        let holding = activity.isHeld(at: now)
            && activity.holder!.priority >= source.priority
            // A source never blocks itself out of continuing; only its cooldown
            // does.
            && activity.holder != source

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

// MARK: - Idle

/// One idle thought.
enum RautaIdleBeat: Equatable, Sendable {
    /// The eyes go somewhere and come back. The cheapest way to look alive, and
    /// most of what a living thing does while waiting.
    case glance(RautaGlance)
    case play(RautaReaction)
}

/// Where the eyes go when they go somewhere.
///
/// A uniformly random direction reads as noise. People look at things, and the
/// same handful of places over and over: off to one side, up and away while
/// thinking, down at their hands, back over a shoulder. Naming those places
/// means a mood can prefer some of them — a bored character looks away and
/// down, a thinking one looks up, a nervous one checks both sides — so the eyes
/// alone carry the mood, with no change of expression at all.
enum RautaGazeDirection: String, CaseIterable, Sendable {
    case left, right
    case farLeft, farRight
    case upLeft, upRight
    case up, down
    case downLeft, downRight
    /// Barely off centre: the eyes settling rather than looking.
    case nudgeLeft, nudgeRight

    /// Eyes travel less up and down than side to side, so the vertical reach of
    /// every direction is already the smaller one.
    var offset: (x: Double, y: Double) {
        switch self {
        case .left: return (-0.62, -0.04)
        case .right: return (0.62, -0.04)
        case .farLeft: return (-1, 0.02)
        case .farRight: return (1, 0.02)
        case .upLeft: return (-0.52, -0.46)
        case .upRight: return (0.52, -0.46)
        case .up: return (0.06, -0.54)
        case .down: return (-0.04, 0.5)
        case .downLeft: return (-0.5, 0.4)
        case .downRight: return (0.5, 0.4)
        case .nudgeLeft: return (-0.22, 0.06)
        case .nudgeRight: return (0.22, 0.06)
        }
    }
}

/// A look, as the eyes actually perform it: one place, then sometimes another,
/// before they come back.
struct RautaGlance: Equatable, Sendable {
    struct Stop: Equatable, Sendable {
        var x: Double
        var y: Double
        /// How long the eyes stay here before the next stop, in seconds.
        var hold: Double
        /// How quickly they close the distance to it, per second.
        var speed: Double
    }

    var stops: [Stop]
    /// Which of the named places this look went to, so the next one can go
    /// somewhere else.
    var direction: RautaGazeDirection?

    /// A look toward `direction`, scaled by how far this mood lets the eyes
    /// travel, sometimes followed by a second, smaller move — the flick that
    /// makes a look read as attention rather than as a pose.
    static func toward(
        _ direction: RautaGazeDirection,
        reach: Double,
        darting: Bool,
        random: () -> Double
    ) -> RautaGlance {
        let offset = direction.offset
        let scale = reach * (0.62 + 0.38 * random())
        let first = Stop(
            x: offset.x * scale,
            y: offset.y * scale,
            hold: 0.55 + random() * 1.1,
            speed: darting ? 26 : 15
        )
        guard darting || random() < 0.42 else {
            return RautaGlance(stops: [first], direction: direction)
        }

        // The second stop is a small correction off the first, not a new look:
        // eyes land near a thing and then on it.
        let drift = (darting ? 0.5 : 0.22) * (random() < 0.5 ? -1 : 1)
        let second = Stop(
            x: Swift.max(-1, Swift.min(1, first.x + drift)),
            y: Swift.max(-0.7, Swift.min(0.7, first.y + drift * 0.35 * (random() < 0.5 ? -1 : 1))),
            hold: 0.4 + random() * 0.8,
            speed: darting ? 30 : 18
        )
        return RautaGlance(stops: [first, second], direction: direction)
    }
}

/// What the character does with itself while nothing is happening, by mood.
///
/// A focused character barely moves; a bored one looks around and sighs; a happy
/// one winks and occasionally spins. The menus are weighted, not scripted, and
/// a repeat of the previous thought is avoided, so the same screen left open
/// never settles into a visible loop.
enum RautaIdle {
    private enum Option {
        case glance(reach: Double)
        case play(RautaReaction)
    }

    /// Where a mood tends to look, and how far. Weighted rather than scripted,
    /// so the same screen left open never settles into a visible pattern, and
    /// never twice the same direction in a row.
    static func directions(for mood: RautaMood) -> [(RautaGazeDirection, Double)] {
        switch mood {
        case .focused, .working:
            // Barely off the work in front of it.
            return [(.nudgeLeft, 3), (.nudgeRight, 3), (.down, 2), (.left, 1), (.right, 1)]
        case .calm, .listening:
            return [
                (.left, 3), (.right, 3), (.upLeft, 1.5), (.upRight, 1.5),
                (.down, 1.2), (.nudgeLeft, 1), (.nudgeRight, 1),
            ]
        case .curious:
            return [
                (.farLeft, 2.5), (.farRight, 2.5), (.up, 2), (.upLeft, 2), (.upRight, 2),
                (.left, 1.5), (.right, 1.5),
            ]
        case .thinking, .confused:
            // Up and away is what thinking looks like.
            return [(.upLeft, 3), (.upRight, 3), (.up, 2.5), (.left, 1), (.right, 1), (.down, 0.8)]
        case .skeptical:
            return [(.left, 2.5), (.right, 2.5), (.downLeft, 2), (.downRight, 2), (.up, 0.6)]
        case .bored:
            // Away, and down at nothing in particular.
            return [
                (.farLeft, 3), (.farRight, 3), (.down, 2.5), (.downLeft, 2), (.downRight, 2),
                (.up, 1),
            ]
        case .sleepy:
            return [(.down, 4), (.downLeft, 1.5), (.downRight, 1.5), (.nudgeLeft, 1)]
        case .nervous:
            // Checking both sides, and behind.
            return [(.farLeft, 3), (.farRight, 3), (.left, 2), (.right, 2), (.downLeft, 1.5), (.downRight, 1.5)]
        case .blocked:
            return [(.down, 3), (.left, 2), (.right, 2), (.up, 1)]
        case .excited, .playful, .happy, .proud:
            return [
                (.upLeft, 2.5), (.upRight, 2.5), (.left, 2), (.right, 2),
                (.farLeft, 1.5), (.farRight, 1.5), (.up, 1.5),
            ]
        }
    }

    /// Moods whose eyes flick rather than travel: the look arrives fast and is
    /// corrected, instead of drifting across and settling.
    static func darts(_ mood: RautaMood) -> Bool {
        switch mood {
        case .nervous, .excited, .playful, .curious, .skeptical: return true
        default: return false
        }
    }

    /// Seconds until the next thought. Short enough that a few seconds never
    /// pass without the character doing something of its own; the mood still
    /// sets the pace, from a restless nervous to an unhurried sleepy.
    static func delay(for mood: RautaMood, random: () -> Double) -> Double {
        let range: (Double, Double)
        switch mood {
        case .focused, .working: range = (3, 5.5)
        case .calm, .listening: range = (2.6, 4.8)
        case .happy, .proud: range = (2.4, 4.2)
        case .excited, .playful: range = (2, 3.6)
        case .curious, .thinking, .confused, .skeptical: range = (2.4, 4.2)
        case .bored: range = (2.8, 5)
        case .sleepy: range = (3.5, 6)
        case .nervous: range = (1.8, 3.2)
        case .blocked: range = (2.6, 4.6)
        }
        return range.0 + random() * (range.1 - range.0)
    }

    /// How soon a thought that could not happen is tried again.
    static let retryDelay = 0.7

    /// A look is the cheapest thing the character can do and the one that never
    /// wears out, so every mood does far more of it than anything else: the body
    /// stays where it is, and only the eyes carry the waiting.
    private static func menu(for mood: RautaMood) -> [(Option, Double)] {
        switch mood {
        case .focused, .working:
            return [(.glance(reach: 0.45), 5), (.play(.blink), 4), (.play(.blinkDouble), 1)]
        case .calm, .listening:
            return [
                (.glance(reach: 0.75), 7), (.play(.blink), 3), (.play(.blinkDouble), 1.5),
                (.play(.peek), 0.8), (.play(.acknowledge), 0.5), (.play(.turnaround), 0.2),
            ]
        case .happy, .proud, .excited, .playful:
            return [
                (.glance(reach: 0.85), 5), (.play(.wink), 1.8), (.play(.blink), 1.6),
                (.play(.laugh), 1), (.play(.spinRight), 0.4), (.play(.spinLeft), 0.4),
            ]
        case .curious, .thinking, .confused, .skeptical:
            return [
                (.glance(reach: 0.95), 7), (.play(.blinkDouble), 1.6), (.play(.blink), 1.6),
                (.play(.peek), 0.8),
            ]
        case .bored:
            return [
                (.glance(reach: 1), 6), (.play(.blinkDouble), 1.6), (.play(.relieved), 0.6),
                (.play(.peek), 0.8), (.play(.turnaround), 0.5),
            ]
        case .sleepy:
            return [(.glance(reach: 0.35), 3), (.play(.blinkDouble), 2)]
        case .nervous:
            return [(.glance(reach: 1), 6), (.play(.blink), 2.5), (.play(.blinkDouble), 1)]
        case .blocked:
            return [(.glance(reach: 0.55), 3), (.play(.blink), 1.5), (.play(.frustrated), 0.8)]
        }
    }

    static func beat(
        for mood: RautaMood,
        placement: RautaPlacement,
        reducedMotion: Bool,
        previous: RautaIdleBeat?,
        previousDirection: RautaGazeDirection? = nil,
        random: () -> Double
    ) -> RautaIdleBeat {
        let options = menu(for: mood).filter { option, _ in
            guard case .play(let reaction) = option else { return true }
            // A small character keeps its thoughts small, and Reduce Motion
            // keeps them to the eyes.
            if placement == .badge, [.turnaround, .spinLeft, .spinRight, .peek].contains(reaction) {
                return false
            }
            if reducedMotion, !reaction.isEyesOnly { return false }
            if case .play(let last) = previous, last == reaction { return false }
            return true
        }
        let total = options.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return .play(.blink) }

        var pick = random() * total
        var chosen = options[0].0
        for (option, weight) in options {
            if pick < weight { chosen = option; break }
            pick -= weight
        }

        switch chosen {
        case .play(let reaction):
            return .play(reaction)
        case .glance(let reach):
            return .glance(
                RautaGlance.toward(
                    direction(for: mood, avoiding: previousDirection, random: random),
                    reach: reach,
                    darting: darts(mood),
                    random: random
                )
            )
        }
    }

    /// One weighted direction, never the one the eyes just came back from.
    static func direction(
        for mood: RautaMood,
        avoiding previous: RautaGazeDirection?,
        random: () -> Double
    ) -> RautaGazeDirection {
        let options = directions(for: mood).filter { $0.0 != previous }
        let total = options.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return .left }
        var pick = random() * total
        for (option, weight) in options {
            if pick < weight { return option }
            pick -= weight
        }
        return options[options.count - 1].0
    }
}

// MARK: - Touch

/// What a finger on the character means.
enum RautaTouch {
    /// Taps closer together than this count as one run of poking.
    static let streakWindow: TimeInterval = 1.6

    /// Each tap in a run answers a little bigger than the last, until the
    /// character has had enough.
    static func reaction(forTap streak: Int) -> RautaReaction {
        switch streak {
        case ...1: return .tapped
        case 2: return .laugh
        case 3: return .surprise
        case 4: return .wobble
        default: return .frustrated
        }
    }

    /// Past this many taps in a run the character sulks for a moment.
    static func sulks(afterTap streak: Int) -> Bool { streak >= 5 }
    static let sulkDuration: TimeInterval = 5

    /// A press held and let go is a spring released: longer holds jump.
    static func release(afterHolding seconds: TimeInterval, placement: RautaPlacement) -> RautaReaction {
        guard seconds >= 1.1, placement == .hero else { return .gearUp }
        return .celebrate
    }

    /// Degrees of turn per point of horizontal drag. A badge is small, so the
    /// same thumb travel has to turn it further.
    static func degreesPerPoint(_ placement: RautaPlacement) -> Double {
        placement == .hero ? 1.5 : 2.6
    }

    /// What a touch somewhere else on the screen is worth, beyond the look it
    /// always gets.
    ///
    /// Mostly nothing — the eyes going there is the answer, and a character that
    /// startles at every tap is exhausting. A tap that lands close by sometimes
    /// earns a proper look over; a blink is the rest of it. Ambient cooldown
    /// throttles whatever this returns, so a run of tapping cannot stutter.
    static func noticeReaction(distance: Double, random: () -> Double) -> RautaReaction? {
        let roll = random()
        if distance < 180 {
            if roll < 0.10 { return .surprise }
            if roll < 0.20 { return .peek }
            return roll < 0.45 ? .blink : nil
        }
        if roll < 0.05 { return .peek }
        return roll < 0.25 ? .blink : nil
    }

    /// How long the eyes stay on a touch: a tap right beside the character holds
    /// the look longer than one across the screen.
    static func noticeHold(distance: Double) -> TimeInterval {
        distance < 180 ? 2.0 : 1.3
    }

    /// Points per second of flick that throw the character into a full spin.
    static let spinVelocity: Double = 650
    /// Points per second of upward flick that make it hop.
    static let hopVelocity: Double = 800

    /// How far the character gives when pulled, in points. It stretches toward
    /// the finger and never leaves its place.
    static func leash(_ translation: CGSize, placement: RautaPlacement) -> CGSize {
        let limit: CGFloat = placement == .hero ? 18 : 7
        func give(_ value: CGFloat) -> CGFloat {
            value * 0.6 / (1 + abs(value) * 0.6 / limit)
        }
        return CGSize(width: give(translation.width), height: give(translation.height))
    }
}

// MARK: - Gaze

enum RautaGaze {
    /// Where the eyes sit when they are not looking at anything.
    ///
    /// Not dead centre: eyes parked on exactly the same pixel every time are the
    /// one thing that reads as a still image. Each rest is a slightly different
    /// place, close enough to centre to still be facing you.
    static func rest(random: () -> Double) -> (x: Double, y: Double) {
        (x: (random() - 0.5) * 0.24, y: (random() - 0.5) * 0.14)
    }

    /// The eye direction that looks from `frame` toward `point`, both in the
    /// same coordinate space.
    ///
    /// Soft saturation rather than a clamp: a tap just beside the character
    /// moves its eyes a little, anything across the screen pins them to the edge,
    /// and nothing in between jumps.
    static func toward(_ point: CGPoint, from frame: CGRect) -> (x: Double, y: Double) {
        let dx = Double(point.x - frame.midX)
        let dy = Double(point.y - frame.midY)
        let reachX = Swift.max(60, Double(frame.width) * 0.9)
        let reachY = Swift.max(80, Double(frame.height) * 1.2)
        return (dx / (abs(dx) + reachX), dy / (abs(dy) + reachY))
    }
}

// MARK: - Context

/// Where the person is in a workout, as far as the character's mood cares.
enum RautaWorkoutPhase: Equatable, Sendable {
    case none
    case working
    case resting(until: Date)
    case paused
}

/// Everything outside a placement that colours how RAUTA looks there.
struct RautaContext: Equatable, Sendable {
    var workout: RautaWorkoutPhase = .none
    /// What a long stretch without the person touching anything has done to the
    /// character: bored, then sleepy.
    var drift: RautaMood?
    /// A feeling that outlasts the reaction that started it: proud for a while
    /// after a finished session.
    var afterglow: RautaMood?
    var afterglowUntil: Date = .distantPast

    /// The mood a placement shows, given the one its screen asked for.
    func mood(for base: RautaMood, now: Date) -> RautaMood {
        guard base.isNeutral else { return base }
        if let afterglow, now < afterglowUntil { return afterglow }
        switch workout {
        case .resting(let until) where until > now: return .calm
        case .paused: return .listening
        case .working, .resting: return .focused
        case .none: return drift ?? base
        }
    }

    /// Bored after a while untouched, sleepy after longer, and sooner at night.
    /// Never during a workout: a phone left on the bench between sets is the
    /// workout going well.
    static func drift(idleFor seconds: TimeInterval, hour: Int, workout: RautaWorkoutPhase) -> RautaMood? {
        guard workout == .none else { return nil }
        let night = hour >= 23 || hour < 5
        if seconds >= (night ? 90 : 180) { return .sleepy }
        if seconds >= (night ? 30 : 60) { return .bored }
        return nil
    }
}

// MARK: - Cues

/// Meaningful product events RAUTA can answer without coupling screens to the
/// animation. The director notices them by watching the stores and the app's
/// haptics, so a screen never has to say anything at all.
enum RautaCue: String, Sendable {
    case setSaved = "set-saved"
    case hardSetSaved = "hard-set-saved"
    case exerciseCompleted = "exercise-completed"
    case allExercisesDone = "all-exercises-done"
    case restOver = "rest-over"
    case workoutPaused = "workout-paused"
    case workoutResumed = "workout-resumed"
    case workoutStarted = "workout-started"
    case workoutFinished = "workout-finished"
    case workoutCancelled = "workout-cancelled"
    case workoutCreated = "workout-created"
    case workoutDeleted = "workout-deleted"
    case planCreated = "plan-created"
    case planAdjusted = "plan-adjusted"
    case favoriteAdded = "favorite-added"
    /// Something the person did went through: a success haptic with no richer
    /// event behind it.
    case confirmed
    /// Something the person did pushed back: a warning haptic.
    case warned
    /// The first touch after the character drifted off.
    case wokeUp = "woke-up"
    case noticed
    /// The app came back after a long time away.
    case welcomeBack = "welcome-back"

    /// When several cues land together — a saved set is also a success haptic
    /// and the start of a rest — the most meaningful one is answered.
    var salience: Int {
        switch self {
        case .workoutFinished: return 100
        case .planCreated: return 95
        case .workoutStarted: return 90
        case .allExercisesDone: return 85
        case .exerciseCompleted: return 80
        case .planAdjusted: return 75
        case .workoutCancelled: return 65
        case .hardSetSaved: return 62
        case .setSaved: return 60
        case .restOver: return 55
        case .workoutPaused, .workoutResumed: return 50
        case .workoutCreated: return 45
        case .workoutDeleted: return 40
        case .favoriteAdded: return 35
        case .welcomeBack: return 30
        case .wokeUp: return 25
        case .warned: return 20
        case .noticed: return 12
        case .confirmed: return 10
        }
    }

    /// The feeling a cue leaves behind, and for how long.
    var afterglow: (mood: RautaMood, seconds: TimeInterval)? {
        switch self {
        case .workoutFinished: return (.proud, 30)
        case .planCreated, .planAdjusted: return (.happy, 16)
        case .allExercisesDone: return (.excited, 8)
        case .exerciseCompleted: return (.happy, 8)
        case .welcomeBack: return (.happy, 6)
        default: return nil
        }
    }
}

struct RautaResponse: Sendable {
    var reaction: RautaReaction
    var line: String
}

enum RautaCues {
    /// What an explicit request with no reaction of its own plays, in turn.
    static let acknowledgements: [RautaReaction] = [.acknowledge, .wink, .gearUp, .relieved]

    private static let responses: [RautaCue: [RautaResponse]] = [
        .setSaved: [
            RautaResponse(reaction: .acknowledge, line: "Set locked in."),
            RautaResponse(reaction: .wink, line: "Got it. Keep moving."),
            RautaResponse(reaction: .gearUp, line: "Recorded. Next one when you're ready."),
            RautaResponse(reaction: .relieved, line: "That's on the board."),
        ],
        .hardSetSaved: [
            RautaResponse(reaction: .relieved, line: "That one took everything. Breathe."),
            RautaResponse(reaction: .wobble, line: "Nothing left in the tank. Nice."),
        ],
        .exerciseCompleted: [
            RautaResponse(reaction: .celebrate, line: "Exercise done. Strong work."),
            RautaResponse(reaction: .gearUp, line: "One station cleared."),
            RautaResponse(reaction: .laugh, line: "That's finished. Onward."),
        ],
        .allExercisesDone: [
            RautaResponse(reaction: .celebrate, line: "Every exercise done. Finish when you're ready."),
        ],
        .restOver: [
            RautaResponse(reaction: .gearUp, line: "Rest's up. Next set."),
            RautaResponse(reaction: .surprise, line: "Time. Back to it."),
        ],
        .workoutPaused: [
            RautaResponse(reaction: .relieved, line: "Clock paused. Take the moment."),
            RautaResponse(reaction: .blinkDouble, line: "Paused. I'll hold our place."),
            RautaResponse(reaction: .peek, line: "Break time. I'm still here."),
        ],
        .workoutResumed: [
            RautaResponse(reaction: .gearUp, line: "We're back. Clock is running."),
            RautaResponse(reaction: .acknowledge, line: "Resumed. Pick up where you left off."),
        ],
        .workoutStarted: [
            RautaResponse(reaction: .gearUp, line: "Let's train. First set when you're ready."),
            RautaResponse(reaction: .spinRight, line: "Session started. I'll keep count."),
        ],
        .workoutFinished: [
            RautaResponse(reaction: .celebrate, line: "Session complete. You did the work."),
            RautaResponse(reaction: .laugh, line: "That's a wrap. Nice session."),
        ],
        .workoutCancelled: [
            RautaResponse(reaction: .relieved, line: "Session closed. Your sets are kept."),
            RautaResponse(reaction: .peek, line: "Stopped. Nothing you logged is lost."),
        ],
        .workoutCreated: [
            RautaResponse(reaction: .acknowledge, line: "Workout saved."),
            RautaResponse(reaction: .wink, line: "On the calendar."),
        ],
        .workoutDeleted: [
            RautaResponse(reaction: .peek, line: "Gone."),
            RautaResponse(reaction: .recoil, line: "Removed."),
        ],
        .planCreated: [
            RautaResponse(reaction: .celebrate, line: "Your plan is ready."),
            RautaResponse(reaction: .spinRight, line: "Weeks mapped out. Let's go."),
        ],
        .planAdjusted: [
            RautaResponse(reaction: .celebrate, line: "Week adjusted. The remaining work fits."),
            RautaResponse(reaction: .acknowledge, line: "Plan updated around what you logged."),
            RautaResponse(reaction: .wink, line: "Schedule reshaped. You're set."),
        ],
        .favoriteAdded: [
            RautaResponse(reaction: .wink, line: "Good pick."),
            RautaResponse(reaction: .laugh, line: "One of yours now."),
        ],
        .confirmed: [
            RautaResponse(reaction: .acknowledge, line: ""),
            RautaResponse(reaction: .wink, line: ""),
        ],
        .warned: [
            RautaResponse(reaction: .surprise, line: ""),
            RautaResponse(reaction: .recoil, line: ""),
        ],
        .wokeUp: [
            RautaResponse(reaction: .surprise, line: "Oh! I'm up."),
        ],
        .noticed: [
            RautaResponse(reaction: .blinkDouble, line: ""),
            RautaResponse(reaction: .acknowledge, line: ""),
        ],
        .welcomeBack: [
            RautaResponse(reaction: .surprise, line: "You're back."),
            RautaResponse(reaction: .laugh, line: "There you are."),
        ],
    ]

    /// Only the director picks, and it lives on the main actor.
    @MainActor private static var previousChoice: [RautaCue: Int] = [:]

    @MainActor
    static func pick(
        _ cue: RautaCue,
        previous: Int? = nil,
        random: () -> Double = { Double.random(in: 0..<1) }
    ) -> RautaResponse {
        guard let options = responses[cue], !options.isEmpty else {
            return RautaResponse(reaction: .acknowledge, line: "")
        }
        var index = Swift.min(options.count - 1, Int(random() * Double(options.count)))
        let last = previous ?? previousChoice[cue]
        if options.count > 1, index == last { index = (index + 1) % options.count }
        previousChoice[cue] = index
        return options[index]
    }
}

