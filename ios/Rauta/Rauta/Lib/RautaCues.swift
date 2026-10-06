import Foundation

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
        // Between sets it gets its breath back, as the person does.
        case .resting(let until) where until > now: return .recovering
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



/// Meaningful product events RAUTA can answer without coupling screens to the
/// animation. The director notices them by watching the stores and the app's
/// haptics, so a screen never has to say anything at all.
enum RautaCue: String, Sendable {
    case setSaved = "set-saved"
    case hardSetSaved = "hard-set-saved"
    /// A set better than anything this exercise has seen before.
    case personalBest = "personal-best"
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
        case .personalBest: return 82
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
        case .personalBest: return (.proud, 10)
        case .exerciseCompleted: return (.happy, 8)
        // Spent for a moment after an all-out set, then the rest's breathing.
        case .hardSetSaved: return (.exhausted, 6)
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
        .personalBest: [
            RautaResponse(reaction: .personalBest, line: "New best. That's the most you've moved here."),
            RautaResponse(reaction: .personalBest, line: "Personal best. Write that one down — I did."),
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
            RautaResponse(reaction: .cheer, line: "Rest's up. Next set."),
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
            RautaResponse(reaction: .powerUp, line: "Let's train. First set when you're ready."),
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
            RautaResponse(reaction: .idea, line: "Plan updated around what you logged."),
            RautaResponse(reaction: .wink, line: "Schedule reshaped. You're set."),
        ],
        .favoriteAdded: [
            RautaResponse(reaction: .appreciate, line: "Good pick."),
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
