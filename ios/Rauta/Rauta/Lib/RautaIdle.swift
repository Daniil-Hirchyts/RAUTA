import Foundation

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
        case .focused, .working, .determined:
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
        case .sleepy, .exhausted, .recovering:
            return [(.down, 4), (.downLeft, 1.5), (.downRight, 1.5), (.nudgeLeft, 1)]
        case .nervous:
            // Checking both sides, and behind.
            return [(.farLeft, 3), (.farRight, 3), (.left, 2), (.right, 2), (.downLeft, 1.5), (.downRight, 1.5)]
        case .blocked:
            return [(.down, 3), (.left, 2), (.right, 2), (.up, 1)]
        case .excited, .playful, .happy, .proud, .cheeky:
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
        case .nervous, .excited, .playful, .curious, .skeptical, .cheeky: return true
        default: return false
        }
    }

    /// Seconds until the next thought. Short enough that a few seconds never
    /// pass without the character doing something of its own; the mood still
    /// sets the pace, from a restless nervous to an unhurried sleepy.
    static func delay(for mood: RautaMood, random: () -> Double) -> Double {
        let range: (Double, Double)
        switch mood {
        case .focused, .working, .determined: range = (3, 5.5)
        case .calm, .listening: range = (2.6, 4.8)
        case .happy, .proud: range = (2.4, 4.2)
        case .excited, .playful, .cheeky: range = (2, 3.6)
        case .curious, .thinking, .confused, .skeptical: range = (2.4, 4.2)
        case .bored: range = (2.8, 5)
        case .sleepy, .exhausted, .recovering: range = (3.5, 6)
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
        case .focused, .working, .determined:
            return [(.glance(reach: 0.45), 5), (.play(.blink), 4), (.play(.blinkDouble), 1)]
        case .calm, .listening:
            return [
                (.glance(reach: 0.75), 7), (.play(.blink), 3), (.play(.blinkDouble), 1.5),
                (.play(.peek), 0.8), (.play(.acknowledge), 0.5), (.play(.turnaround), 0.2),
            ]
        case .happy, .proud, .excited, .playful, .cheeky:
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
        case .sleepy, .exhausted, .recovering:
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
