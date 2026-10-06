import Foundation

/// How the app's audio session is set while something sounds. Ordered: a
/// later style outranks an earlier one, and once the session is in it, it
/// stays there until it is let go.
nonisolated enum AudioSessionStyle: Int, Comparable, Sendable {
    /// Taps and RAUTA's phrases: mixed in, silenced by the ring switch, and
    /// the person's music never notices.
    case ambient
    /// The workout's own moments — a set logged, a rest starting: heard with
    /// the ring switch on and on a locked phone, on top of the music.
    case mixed
    /// The countdown and the end of a rest: the music dips while they sound,
    /// the way a navigation app speaks a turn.
    case ducking

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// How long the session is held after the last sound in this style.
    /// Short for a dip, so the music comes straight back; long for taps, so
    /// the next one sounds at once instead of waiting for the engine.
    var linger: TimeInterval {
        switch self {
        case .ambient: return 8
        case .mixed: return 1
        case .ducking: return 0.4
        }
    }
}

/// Who gets to be heard when two sounds want the same moment.
nonisolated enum SoundPriority: Int, Comparable, Sendable {
    /// The small sound of touching something.
    case touch
    /// RAUTA's voice, a thought while it works, a page arriving.
    case phrase
    /// The workout's own moments.
    case moment
    /// The countdown and the end of a rest or warm-up.
    case cue

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Decides, before anything is played, which of the app's sounds are heard.
///
/// Pure and clocked from outside, so every rule can be tested without a
/// speaker:
/// - a cue is always heard, and silences anything lesser still sounding;
/// - while a countdown is on, nothing but cues and the workout's own moments
///   is heard — no voice, no taps over the 3-2-1;
/// - a lesser sound never talks over a greater one still sounding;
/// - two of the workout's moments in the same breath — a set logged that also
///   finishes the exercise — are heard as the one that says most.
nonisolated struct SoundArbiter: Sendable {
    nonisolated struct Request: Sendable {
        var priority: SoundPriority
        /// Among the workout's moments, which says most.
        var rank: Int = 0
        var duration: TimeInterval
        /// A phrase that only plays into silence, rather than over another.
        var waitsForSilence = false
    }

    nonisolated enum Decision: Equatable, Sendable {
        /// Play it. Anything below `silencing` still sounding is cut first.
        case play(silencing: SoundPriority?)
        case drop
    }

    /// The window a moment folds into another.
    static let coalescingWindow: TimeInterval = 0.25

    private var soundingUntil: [SoundPriority: Date] = [:]
    private var countdownUntil = Date.distantPast
    private var lastMoment: (rank: Int, at: Date)?

    init() {}

    func isCountingDown(at now: Date) -> Bool { countdownUntil > now }

    /// Opens (or moves) the countdown window: until `until`, only cues and
    /// moments are heard.
    mutating func beginCountdown(until: Date) {
        countdownUntil = until
    }

    mutating func endCountdown() {
        countdownUntil = .distantPast
    }

    /// Whether anything at or above `priority` is still sounding at `now`.
    func isSounding(atLeast priority: SoundPriority, at now: Date) -> Bool {
        soundingUntil.contains { $0.key >= priority && $0.value > now }
    }

    mutating func decide(_ request: Request, at now: Date) -> Decision {
        let louder = soundingUntil.contains { $0.key > request.priority && $0.value > now }
        switch request.priority {
        case .cue:
            record(request, at: now)
            let lesser = soundingUntil.contains { $0.key < .cue && $0.value > now }
            if lesser { clear(below: .cue) }
            return .play(silencing: lesser ? .cue : nil)

        case .moment:
            if louder { return .drop }
            // Two moments in one breath: the one that says more is heard.
            if let last = lastMoment, now.timeIntervalSince(last.at) < Self.coalescingWindow {
                guard request.rank > last.rank else { return .drop }
                record(request, at: now)
                return .play(silencing: .moment)
            }
            record(request, at: now)
            return .play(silencing: nil)

        case .phrase, .touch:
            if louder || countdownUntil > now { return .drop }
            if request.waitsForSilence, isSounding(atLeast: request.priority, at: now) { return .drop }
            record(request, at: now)
            return .play(silencing: nil)
        }
    }

    private mutating func record(_ request: Request, at now: Date) {
        let until = now.addingTimeInterval(request.duration)
        soundingUntil[request.priority] = max(soundingUntil[request.priority] ?? .distantPast, until)
        if request.priority == .moment {
            lastMoment = (request.rank, now)
            // A moment that wins the breath replaces the one before it.
            soundingUntil[.moment] = until
        }
    }

    private mutating func clear(below priority: SoundPriority) {
        for key in soundingUntil.keys where key < priority { soundingUntil[key] = nil }
    }
}

/// When the session can be let go, worked out from what was scheduled rather
/// than from the player telling us it finished: a callback that never comes
/// can no longer leave the person's music turned down.
nonisolated struct AudioTimeline: Sendable {
    /// When the sound queued on each player ends.
    private var queueEnds: [Int: Date] = [:]
    /// The session is held until then.
    private(set) var holdUntil = Date.distantPast
    /// The style the session is held in; nil when it is let go.
    private(set) var style: AudioSessionStyle?

    init() {}

    /// The style the session should be in for a sound in `wanted`: never a
    /// step down while held.
    func styleFor(_ wanted: AudioSessionStyle) -> AudioSessionStyle {
        guard let style else { return wanted }
        return max(style, wanted)
    }

    mutating func enter(_ style: AudioSessionStyle) {
        self.style = style
    }

    /// Books a sound of `duration` on player `node`, starting now or after
    /// what is queued there, and holds the session until it has ended.
    /// Returns when it will end.
    @discardableResult
    mutating func schedule(_ duration: TimeInterval, on node: Int, interrupting: Bool, at now: Date) -> Date {
        let start = interrupting ? now : max(now, queueEnds[node] ?? now)
        let end = start.addingTimeInterval(duration)
        queueEnds[node] = end
        hold(until: end.addingTimeInterval((style ?? .ambient).linger))
        return end
    }

    /// Keeps the session through `until` — the length of a countdown.
    mutating func hold(until: Date) {
        holdUntil = max(holdUntil, until)
    }

    /// Lets a hold go early: nothing queued is cut, only the wait after it.
    mutating func shortenHold(at now: Date) {
        let lastEnd = queueEnds.values.max() ?? now
        holdUntil = max(lastEnd, now).addingTimeInterval((style ?? .ambient).linger)
    }

    /// Players stopped: nothing is queued on them any more.
    mutating func clearQueues() {
        queueEnds.removeAll()
    }

    func releaseIsDue(at now: Date) -> Bool {
        style != nil && now >= holdUntil
    }

    /// The session let go.
    mutating func released() {
        queueEnds.removeAll()
        holdUntil = .distantPast
        style = nil
    }
}

nonisolated extension RautaSound {
    /// Who gets to be heard, and how the session is set to hear it.
    var priority: SoundPriority {
        switch channel {
        case .cue: return .cue
        case .workout: return .moment
        case .interface: return .touch
        }
    }

    var sessionStyle: AudioSessionStyle {
        switch channel {
        case .cue: return .ducking
        case .workout: return .mixed
        case .interface: return .ambient
        }
    }

    /// Among the workout's moments, which says most when two arrive at once.
    var momentRank: Int {
        switch self {
        case .workoutFinish: return 5
        case .exerciseDone: return 4
        case .workoutStart: return 3
        case .setLogged: return 2
        case .restStart: return 1
        default: return 0
        }
    }
}
