import Foundation

/// A request plain enough to act on from its words alone.
///
/// Clear requests go straight to the tool host: no model pass, so no wait, no
/// malformed tool call, and no model claiming it can't do something it can.
/// Only what this can't place reaches the model. Nothing here changes data:
/// the host checks every value against the stores again, so a misread request
/// can only ever end in a question back, never a wrong change.
nonisolated enum AgentIntent: Equatable, Sendable {
    case greeting
    case thanks
    case help
    case schedule
    case workoutDetails
    case buildWorkout
    case newPlan(days: Int?, minutes: Int?)
    case adjustWeek
    case reschedule(workout: String, day: String)
    case swap(exercise: String, replacement: String?)
    case alternatives(exercise: String)
    case editExercise(exercise: String, adding: Bool)
    case deleteWorkout
    case startWorkout
    case finishWorkout
    case discardWorkout
    case rest
    case pause
    case resume
    case logSet(exercise: String?, reps: Int?, kilograms: Double?)
    case reminder
    case removeReminder
    case addToCalendar
    case freeSlots
    case readiness
    case progress(exercise: String)
    case findExercises(query: String)
    case equipment
    case priority
    case profile(minutes: Int?)

    private static let sessionWords: Set<String> = ["workout", "workouts", "session", "sessions"]
    private static let questionWords: Set<String> = [
        "what", "whats", "when", "whens", "show", "list", "anything", "which", "do", "does",
    ]

    /// Reads `input`.
    ///
    /// - Parameters:
    ///   - running: a workout is in progress, so live controls are in play.
    ///   - loose: also take weaker readings. Used only after the model failed,
    ///     when a sensible guess beats an apology.
    static func parse(_ input: String, today: String, running: Bool, loose: Bool = false) -> AgentIntent? {
        let lower = input.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let list = AgentWords.words(lower)
        let words = Set(list)
        guard !list.isEmpty else { return nil }
        func has(_ choices: Set<String>) -> Bool { !words.isDisjoint(with: choices) }
        func says(_ phrases: String...) -> Bool { phrases.contains { lower.contains($0) } }
        let session = has(sessionWords)
        let asking = has(questionWords) || lower.hasSuffix("?")
        let muscles = AgentWords.muscles(in: lower)
        let namesDay = AgentWords.day(lower, today: today) != nil

        // Small talk, answered without the model.
        if list.count <= 4, has(["hi", "hello", "hey", "yo", "morning", "evening", "hiya"]) { return .greeting }
        if list.count <= 6, says("thank", "thx", "cheers", "appreciate") { return .thanks }
        if lower == "help" || says("what can you do", "what do you do", "how do you work", "help me use") {
            return .help
        }

        // Reminders and Calendar: their own words, never anything else.
        if has(["remind", "reminder", "reminders", "notify", "notification", "notifications"]) {
            return has(["remove", "delete", "cancel", "stop", "clear"]) || says("turn off", "don't remind", "dont remind")
                ? .removeReminder : .reminder
        }
        if has(["calendar"]) {
            return has(["free", "available", "open", "slot", "slots", "gap", "gaps"]) ? .freeSlots : .addToCalendar
        }
        if says("free time", "free slot", "when can i train", "when am i free", "time to train", "fit a workout") {
            return .freeSlots
        }

        // The week as a whole.
        let reshaping: Set<String> = ["adjust", "adapt", "reshape", "rebalance", "rearrange", "rework",
                                      "lighter", "easier", "harder", "lighten", "deload", "tweak"]
        if has(reshaping), has(["week", "plan", "remaining"]) || says("rest of") {
            return .adjustWeek
        }
        let planNouns: Set<String> = ["plan", "program", "programme", "routine", "split"]
        let making: Set<String> = ["new", "make", "build", "create", "rebuild", "generate", "design",
                                   "give", "want", "need", "set", "start", "redo", "change"]
        if has(planNouns), has(making) || AgentWords.count(of: ["day", "days", "time", "times"], in: lower) != nil,
           !(session && !muscles.isEmpty) {
            return .newPlan(days: AgentWords.count(of: ["day", "days", "time", "times", "x"], in: lower),
                            minutes: AgentWords.minutes(in: lower))
        }

        // Live controls while a workout runs.
        if running {
            if has(["pause"]) { return .pause }
            if has(["resume", "unpause"]) || says("continue my workout", "continue the workout", "keep going") {
                return .resume
            }
            if has(["rest", "timer", "break"]), !says("rest of", "rest day", "rest days") { return .rest }
            if has(["log", "record"]) || has(["reps", "rep"]) && !AgentWords.numbers(in: lower).isEmpty {
                let exercise = subject(of: lower, dropping: ["log", "record", "reps", "rep", "kg", "kilos",
                                                             "kilograms", "at", "x", "set", "sets", "with"])
                return .logSet(exercise: exercise.isEmpty ? nil : exercise,
                               reps: AgentWords.reps(in: lower), kilograms: AgentWords.kilograms(in: lower))
            }
        }
        if has(["finish", "end", "complete", "wrap"]), session || has(["training"]) || says("i'm done", "im done", "i am done") {
            return .finishWorkout
        }
        if has(["discard", "abandon", "quit", "scrap"]), session { return .discardWorkout }
        if !running, has(["pause"]), session { return .pause }

        // Exercises inside workouts.
        if has(["swap", "replace", "substitute", "switch", "change"]), !has(planNouns),
           !has(["goal", "equipment", "length", "duration", "minutes", "min", "day", "date"]) {
            if let parts = swapParts(lower) { return .swap(exercise: parts.exercise, replacement: parts.replacement) }
        }
        if has(["alternative", "alternatives", "instead"])
            || has(["hurt", "hurts", "hurting", "pain", "painful", "injured"]) && !has(["plan", "week"]) {
            return .alternatives(exercise: subject(of: lower))
        }
        if has(["add", "include", "put"]), let target = firstMatch(of: [" to ", " into ", " in "], in: lower),
           session || namesDay {
            let exercise = trimmed(String(lower[..<target.lowerBound]), dropping: ["add", "include", "put", "please", "can", "you"])
            if !exercise.isEmpty, !has(["equipment"]) { return .editExercise(exercise: exercise, adding: true) }
        }
        if has(["remove", "drop", "take"]), let from = lower.range(of: " from ") {
            let exercise = trimmed(String(lower[..<from.lowerBound]), dropping: ["remove", "drop", "take", "out", "please", "can", "you"])
            if !exercise.isEmpty { return .editExercise(exercise: exercise, adding: false) }
        }
        if has(["delete", "remove", "cancel", "drop"]), session { return .deleteWorkout }

        // Moving a workout.
        if has(["move", "reschedule", "shift", "postpone", "push", "bump"]) {
            if let parts = moveParts(lower, today: today) {
                return .reschedule(workout: parts.workout, day: parts.day)
            }
            return .reschedule(workout: lower, day: "")
        }

        if has(["start", "begin"]) || says("let's go", "lets go", "let's train", "lets train") {
            if session || namesDay || has(["it", "now", "next"]) { return .startWorkout }
        }

        // A new workout.
        let building: Set<String> = ["build", "create", "make", "generate", "design", "give", "want",
                                     "need", "suggest", "prepare", "plan", "put", "new", "get"]
        if session, has(building), !muscles.isEmpty || has(["new", "another", "extra", "quick", "short"]) {
            return .buildWorkout
        }
        let requesting = says("can you", "could you", "i want", "i'd like", "let's", "lets", "please")
        if !muscles.isEmpty, has(["train", "hit", "work", "blast", "smash"]), !asking || requesting,
           !says("how do i", "how to") {
            return .buildWorkout
        }
        if session, has(building), !asking || requesting { return .buildWorkout }

        if has(["readiness", "recovered", "recovery", "recover", "sleep", "slept", "hrv", "tired",
                "fatigued", "fatigue", "exhausted"]) || says("train hard", "ready to train", "should i train") {
            return .readiness
        }

        // Looking something up.
        if session, has(["in", "inside", "details", "exercises"]) || says("show me") {
            if namesDay || has(["next", "current", "this"]) { return .workoutDetails }
        }
        let scheduleWords: Set<String> = ["schedule", "upcoming", "coming", "next", "agenda", "planned",
                                          "today", "tomorrow", "week", "weekend"]
        // Advice questions — how, why, should, food — are the model's.
        let advice: Set<String> = ["why", "how", "should", "eat", "food", "protein", "diet", "drink",
                                   "water", "stretch", "warm", "good", "bad", "ok", "okay"]
        if asking || has(["schedule", "agenda"]), session || has(scheduleWords) || AgentWords.weekday(in: lower) != nil,
           !has(["exercise", "exercises", "progress"]), !has(advice) || has(["schedule", "agenda"]) {
            return .schedule
        }

        if has(["progress", "progressing", "improving", "improved", "stronger", "weaker", "trend", "history", "pr"])
            || says("how is my", "how's my", "hows my", "how am i doing with") {
            let exercise = subject(of: lower)
            if !exercise.isEmpty, ExerciseResolver.resolve(exercise, limit: 1).first != nil {
                return .progress(exercise: exercise)
            }
        }
        if has(["exercise", "exercises", "moves", "movements", "movement"])
            || says("what can i do for", "how do i train", "how to train", "something for", "what works") {
            let query = subject(of: lower)
            if !query.isEmpty { return .findExercises(query: query) }
        }

        // Settings RAUTA can change.
        if has(["equipment"]) || has(["have", "own", "got", "only"]) && AgentWords.mentionsEquipment(lower) {
            return .equipment
        }
        if has(["prioritize", "prioritise", "priority", "emphasize", "emphasise"])
            || has(["more", "less"]) && has(["focus", "emphasis"]) {
            if !muscles.isEmpty, !session { return .priority }
        }
        if has(["goal"]) || has(["usually", "usual", "prefer", "longer", "shorter"]) && AgentWords.minutes(in: lower) != nil {
            return .profile(minutes: AgentWords.minutes(in: lower))
        }

        guard loose else { return nil }
        // After a model failure: the most likely reading, still checked by the host.
        if !muscles.isEmpty { return .buildWorkout }
        if session || has(scheduleWords) { return .schedule }
        let query = subject(of: lower)
        if !query.isEmpty, ExerciseResolver.resolve(query, limit: 1).first != nil { return .findExercises(query: query) }
        return nil
    }

    // MARK: Reading the parts of a request

    /// Words that only carry the asking, never what a request is about.
    private static let filler: Set<String> = [
        "how", "hows", "s", "is", "are", "was", "am", "my", "the", "a", "an", "going", "doing",
        "progress", "progressing", "with", "for", "on", "in", "of", "to", "me", "show", "find",
        "search", "what", "whats", "can", "could", "i", "do", "does", "some", "any", "give", "please",
        "exercise", "exercises", "moves", "movements", "movement", "alternative", "alternatives",
        "instead", "it", "that", "this", "today", "todays", "tomorrow", "tomorrows", "workout",
        "session", "hurts", "hurt", "hurting", "pain", "painful", "injured", "knee", "elbow", "wrist",
        "ankle", "lately", "recently", "been", "has", "have", "you", "should", "would", "good",
        "best", "works", "work", "something", "improving", "improved", "stronger", "weaker", "trend",
        "history", "pr", "and", "or", "about", "tell", "like", "at", "up", "use", "using", "train",
        "training", "how's", "suggest", "recommend", "list", "which", "there", "any", "other",
    ]

    /// What a request is about once its asking words are gone: "how's my
    /// bench press going" → "bench press".
    static func subject(of text: String, dropping extra: Set<String> = []) -> String {
        AgentWords.words(text)
            .filter { !filler.contains($0) && !extra.contains($0) && Int($0) == nil }
            .joined(separator: " ")
    }

    /// A phrase as said, trimmed of the words around it but not broken up, so
    /// it can still be found word-for-word in what the person said.
    private static func trimmed(_ phrase: String, dropping leading: Set<String>) -> String {
        var list = phrase.split(separator: " ").map(String.init)
        let articles: Set<String> = ["a", "an", "the", "some", "my"]
        while let first = list.first?.trimmingCharacters(in: .punctuationCharacters),
              leading.contains(first) || articles.contains(first) {
            list.removeFirst()
        }
        return list.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    }

    private static func firstMatch(of separators: [String], in text: String) -> Range<String.Index>? {
        separators.compactMap { text.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }
    }

    /// The exercise to swap and, when one was named, its replacement:
    /// "replace squats with leg press on Friday" → ("squats", "leg press").
    static func swapParts(_ text: String) -> (exercise: String, replacement: String?)? {
        let verbs = ["swap", "replace", "substitute", "switch", "change"]
        guard let verb = verbs.compactMap({ verb -> Range<String.Index>? in
            text.range(of: #"\b\#(verb)\b"#, options: .regularExpression)
        }).min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        var rest = String(text[verb.upperBound...])
        let stops = [" on ", " in ", " at ", " from ", " during ", ",", "."]
        func cut(_ phrase: String) -> String {
            var phrase = phrase
            if let stop = firstMatch(of: stops, in: phrase) { phrase = String(phrase[..<stop.lowerBound]) }
            return phrase
        }
        var replacement: String?
        if let join = firstMatch(of: [" with ", " for ", " to "], in: rest) {
            replacement = trimmed(cut(String(rest[join.upperBound...])), dropping: [])
            rest = String(rest[..<join.lowerBound])
        }
        let exercise = trimmed(cut(rest), dropping: ["out", "up", "please"])
        let generic: Set<String> = ["something", "anything", "else", "another", "other", "alternative",
                                    "different", "one", "similar", "easier", "harder"]
        if let named = replacement, named.isEmpty || !Set(AgentWords.words(named)).isDisjoint(with: generic) {
            replacement = nil
        }
        guard !exercise.isEmpty else { return nil }
        return (exercise, replacement)
    }

    /// Which workout to move and the day it goes to: "move Thursday's workout
    /// to Friday" → ("move thursday's workout", "friday").
    static func moveParts(_ text: String, today: String) -> (workout: String, day: String)? {
        for separator in [" to ", " until ", " till ", " on ", " for "] {
            guard let split = text.range(of: separator, options: .backwards) else { continue }
            let day = String(text[split.upperBound...]).trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            guard AgentWords.day(day, today: today) != nil else { continue }
            return (String(text[..<split.lowerBound]), day)
        }
        return nil
    }
}

// MARK: - Performing an intent

extension AgentToolHost {
    /// Runs a request read by ``AgentIntent`` through the same checked paths the
    /// model's tools use.
    func perform(_ intent: AgentIntent, input: String) async {
        switch intent {
        case .greeting:
            say("Hi! I can move a workout, swap an exercise, build a workout or plan your week. What should we change?")
        case .thanks:
            say("Anytime. Tell me when you need another change.")
        case .help:
            say("I work on your training here on your iPhone: I can show what's coming up, move or delete a workout, swap or add exercises, build a new workout or plan, adjust your week, set reminders and Calendar events, and run rest timers during a workout.")
        case .schedule:
            schedule()
        case .workoutDetails:
            workoutDetails(input)
        case .buildWorkout:
            await proposeWorkout(input)
        case .newPlan(let days, let minutes):
            await proposePlan(daysPerWeek: days, sessionMinutes: minutes)
        case .adjustWeek:
            await proposeAdjustedWeek()
        case .reschedule(let workout, let day):
            reschedule(workoutPhrase: workout, dayPhrase: day)
        case .swap(let exercise, let replacement):
            swap(workoutPhrase: input, exercisePhrase: exercise, replacementPhrase: replacement)
        case .alternatives(let exercise):
            alternatives(exercise, workoutPhrase: input)
        case .editExercise(let exercise, let adding):
            editExercises(workoutPhrase: input, exercisePhrase: exercise, action: adding ? "add" : "remove")
        case .deleteWorkout:
            proposeDelete(input)
        case .startWorkout:
            startWorkout(input)
        case .finishWorkout:
            proposeFinish()
        case .discardWorkout:
            proposeDiscard()
        case .rest:
            startRest(seconds: nil)
        case .pause:
            setPaused(true)
        case .resume:
            setPaused(false)
        case .logSet(let exercise, let reps, let kilograms):
            let current = ActiveWorkoutStore.shared.session?.currentExerciseId
                .flatMap { ExerciseCatalogue.byId[$0]?.name }
            logSet(exercisePhrase: exercise ?? current ?? "", reps: reps, kilograms: kilograms)
        case .reminder:
            await setReminder(input)
        case .removeReminder:
            removeReminder(input)
        case .addToCalendar:
            proposeCalendar(input)
        case .freeSlots:
            freeSlots(input)
        case .readiness:
            await readiness()
        case .progress(let exercise):
            progress(exercise)
        case .findExercises(let query):
            findExercise(query)
        case .equipment:
            setEquipment(ExerciseCatalogue.equipmentOptions.filter { AgentWords.mentions($0, in: input) })
        case .priority:
            setMusclePriority(input)
        case .profile(let minutes):
            updateProfile(goalPhrase: input.localizedCaseInsensitiveContains("goal") ? input : nil, minutes: minutes)
        }
    }
}
