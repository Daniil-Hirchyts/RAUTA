import Foundation

/// What RAUTA can express, as a vocabulary rather than a pile of animation
/// names.
///
/// A screen should be able to say "the week was generated" or "this set was
/// hard" without knowing how the character draws it. So the names live here
/// once, the rig binding lives in the character once, and every screen speaks in
/// states.
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
}

/// A one-shot: something happens, RAUTA reacts, the mood underneath returns.
enum RautaReaction: String, CaseIterable, Sendable {
    case acknowledge, surprise, celebrate, frustrated, relieved, wobble
    case gearUp, laugh, tapped, recoil, peek, blink, blinkDouble, wink
    case spinLeft, spinRight, turnaround
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

    /// How long a source holds the floor after it plays, in milliseconds.
    var holdMs: Double {
        switch self {
        // Long enough for the reaction to read as an answer to what happened.
        case .explicit: return 2600
        case .interaction: return 900
        case .ambient: return 700
        }
    }

    /// The shortest gap between two reactions from the same source. Without it a
    /// stream of pointer events becomes a stutter of restarted animations.
    var cooldownMs: Double {
        switch self {
        case .explicit: return 260
        case .interaction: return 620
        case .ambient: return 2400
        }
    }
}

/// Ambient idle picks a new delay in this range each time, so the character
/// neither loops on a fixed beat nor fidgets constantly.
let RAUTA_IDLE_RANGE_MS = (min: 5200.0, max: 12_600.0)

/// Small, unobtrusive things to do while nothing is happening. Weighted by
/// repetition rather than by a table: a blink should be common and a spin should
/// be rare.
private let ambientReactions: [RautaReaction] = [
    .blink, .blink, .blink, .blinkDouble, .peek, .blink, .wink, .blinkDouble,
    .peek, .acknowledge, .relieved, .laugh, .turnaround, .spinLeft, .blink, .spinRight,
]

struct RautaActivity {
    /// The source that currently holds the floor, and until when.
    var holder: RautaSource?
    var holdUntil: Double = 0
    var lastInteraction: RautaReaction?
    /// The previous idle beat, so random choice still never looks like a loop.
    var lastAmbient: RautaReaction?
    /// When each source last played, for its own cooldown.
    var lastPlayedAt: [String: Double] = [
        RautaSource.explicit.rawValue: -.greatestFiniteMagnitude,
        RautaSource.interaction.rawValue: -.greatestFiniteMagnitude,
        RautaSource.ambient.rawValue: -.greatestFiniteMagnitude,
    ]
    /// When ambient idle is next allowed to have a thought.
    var ambientDueAt: Double = 0

    init(now: Double = 0) {
        ambientDueAt = now + RAUTA_IDLE_RANGE_MS.min
    }
}

enum RautaScheduler {
    struct Outcome {
        var activity: RautaActivity
        var play: RautaReaction?
    }

    /// Whether a reaction gets to play, and the activity that follows.
    ///
    /// Pure: the clock and the randomness are arguments, so the same sequence of
    /// requests always resolves the same way.
    ///
    /// A request is refused when a higher- or equal-priority source still holds
    /// the floor, or when its own source is still cooling down. Refusing is the
    /// point — it is what stops an idle blink from cutting off the celebration
    /// of a finished week.
    static func request(
        _ activity: RautaActivity,
        source: RautaSource,
        reaction: RautaReaction,
        now: Double
    ) -> Outcome {
        let holding = activity.holder != nil
            && now < activity.holdUntil
            && activity.holder!.priority >= source.priority
            // A source never blocks itself out of continuing; only its cooldown
            // does.
            && activity.holder != source

        let impactInterrupt = source == .interaction
            && (reaction == .recoil || reaction == .wobble)
            && [RautaReaction.surprise, .peek, .spinLeft, .spinRight]
                .contains(activity.lastInteraction ?? .blink)

        let lastPlayed = activity.lastPlayedAt[source.rawValue] ?? -.greatestFiniteMagnitude
        let cooling = !impactInterrupt && (now - lastPlayed) < source.cooldownMs

        if holding || cooling { return Outcome(activity: activity, play: nil) }

        var next = activity
        next.holder = source
        if source == .interaction { next.lastInteraction = reaction }
        next.holdUntil = now + source.holdMs
        next.lastPlayedAt[source.rawValue] = now
        // Anything happening pushes the character's own next thought back.
        if source != .ambient { next.ambientDueAt = now + RAUTA_IDLE_RANGE_MS.min }
        return Outcome(activity: next, play: reaction)
    }

    /// The character's next thought, when it is due and nothing else is going on.
    ///
    /// Returns nil while a reaction still holds the floor or the next idle moment
    /// has not arrived, so idle behaviour stays occasional.
    static func idle(
        _ activity: RautaActivity,
        now: Double,
        random: () -> Double = { Double.random(in: 0..<1) }
    ) -> Outcome {
        if now < activity.ambientDueAt { return Outcome(activity: activity, play: nil) }

        let span = RAUTA_IDLE_RANGE_MS.max - RAUTA_IDLE_RANGE_MS.min
        let nextDueAt = now + RAUTA_IDLE_RANGE_MS.min + (random() * span).rounded(.down)
        let available = ambientReactions.filter { $0 != activity.lastAmbient }
        guard !available.isEmpty else { return Outcome(activity: activity, play: nil) }
        let choice = available[
            Swift.min(available.count - 1, Int(random() * Double(available.count)))
        ]

        var scheduled = activity
        scheduled.ambientDueAt = nextDueAt
        let attempt = request(scheduled, source: .ambient, reaction: choice, now: now)

        // Even when the floor is held, the next thought is rescheduled rather
        // than retried immediately: a blocked idle must not become a busy wait.
        if let played = attempt.play {
            var settled = attempt.activity
            settled.lastAmbient = played
            return Outcome(activity: settled, play: played)
        }
        var deferred = activity
        deferred.ambientDueAt = nextDueAt
        return Outcome(activity: deferred, play: nil)
    }
}

/// Meaningful product events RAUTA can answer without coupling screens to the
/// animation. Deliberately sparse: a workout action gets a response; ordinary
/// navigation does not become chatter.
enum RautaCue: String, Sendable {
    case setSaved = "set-saved"
    case exerciseCompleted = "exercise-completed"
    case exerciseSkipped = "exercise-skipped"
    case workoutPaused = "workout-paused"
    case workoutResumed = "workout-resumed"
    case workoutStarted = "workout-started"
    case workoutFinished = "workout-finished"
    case planAdjusted = "plan-adjusted"
    case actionBlocked = "action-blocked"
}

struct RautaResponse: Sendable {
    var reaction: RautaReaction
    var line: String
}

enum RautaCues {
    private static let responses: [RautaCue: [RautaResponse]] = [
        .setSaved: [
            RautaResponse(reaction: .acknowledge, line: "Set locked in."),
            RautaResponse(reaction: .wink, line: "Got it. Keep moving."),
            RautaResponse(reaction: .gearUp, line: "Recorded. Next one when you're ready."),
            RautaResponse(reaction: .relieved, line: "That's on the board."),
        ],
        .exerciseCompleted: [
            RautaResponse(reaction: .celebrate, line: "Exercise done. Strong work."),
            RautaResponse(reaction: .gearUp, line: "One station cleared."),
            RautaResponse(reaction: .wink, line: "That's finished. Onward."),
        ],
        .exerciseSkipped: [
            RautaResponse(reaction: .acknowledge, line: "Moving on. We can come back."),
            RautaResponse(reaction: .turnaround, line: "Next exercise. Stay warm."),
            RautaResponse(reaction: .peek, line: "Skipping ahead. I've kept your place."),
        ],
        .workoutPaused: [
            RautaResponse(reaction: .relieved, line: "Clock paused. Take the moment."),
            RautaResponse(reaction: .blinkDouble, line: "Paused. I'll hold our place."),
            RautaResponse(reaction: .peek, line: "Break time. I'm still here."),
        ],
        .workoutResumed: [
            RautaResponse(reaction: .gearUp, line: "We're back. Clock is running."),
            RautaResponse(reaction: .acknowledge, line: "Resumed. Pick up where you left off."),
            RautaResponse(reaction: .wink, line: "Back in motion."),
        ],
        .workoutStarted: [
            RautaResponse(reaction: .gearUp, line: "Let's train. First set when you're ready."),
            RautaResponse(reaction: .celebrate, line: "Session started. I'll keep count."),
        ],
        .workoutFinished: [
            RautaResponse(reaction: .celebrate, line: "Session complete. You did the work."),
            RautaResponse(reaction: .laugh, line: "That's a wrap. Nice session."),
            RautaResponse(reaction: .relieved, line: "Finished and saved."),
        ],
        .planAdjusted: [
            RautaResponse(reaction: .celebrate, line: "Week adjusted. The remaining work fits."),
            RautaResponse(reaction: .acknowledge, line: "Plan updated around what you logged."),
            RautaResponse(reaction: .wink, line: "Schedule reshaped. You're set."),
        ],
        .actionBlocked: [
            RautaResponse(reaction: .frustrated, line: "That didn't work. Try once more."),
            RautaResponse(reaction: .recoil, line: "I couldn't save that change."),
            RautaResponse(reaction: .surprise, line: "Something got in the way."),
        ],
    ]

    private static var previousChoice: [RautaCue: Int] = [:]

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

/// The bus a screen posts a cue on, so the character can answer without every
/// screen holding a reference to it.
extension Notification.Name {
    static let rautaCue = Notification.Name("rauta:cue")
}

@MainActor
func cueRauta(_ cue: RautaCue) {
    NotificationCenter.default.post(
        name: .rautaCue, object: nil, userInfo: ["cue": cue.rawValue]
    )
}
