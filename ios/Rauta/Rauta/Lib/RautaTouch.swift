import CoreGraphics
import Foundation

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

    /// Spins closer together than this count as one run of spinning.
    static let spinWindow: TimeInterval = 5

    /// A spin, until it has been spun once too often in a row: then it is
    /// dizzy.
    static func spin(_ streak: Int, rightward: Bool) -> RautaReaction {
        if streak >= 3 { return .dizzy }
        return rightward ? .spinRight : .spinLeft
    }
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
