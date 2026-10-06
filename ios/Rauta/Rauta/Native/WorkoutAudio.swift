import AVFoundation
import UIKit

/// The app's sounds: one family, made for Rauta by `scripts/sounds/generate.py`
/// and bundled as `rauta-<name>.caf`. Soft sine tones for the cues and the
/// taps, a marimba where something is completed. What is made on the spot —
/// RAUTA's voice, a thought, a page arriving — is a ``RautaPhrase``.
nonisolated enum RautaSound: String, CaseIterable, Sendable {
    case tick3 = "rauta-tick-3"
    case tick2 = "rauta-tick-2"
    case tick1 = "rauta-tick-1"
    case restOver = "rauta-rest-over"
    case warmupOver = "rauta-warmup-over"
    case restStart = "rauta-rest-start"
    case setLogged = "rauta-set-logged"
    case exerciseDone = "rauta-exercise-done"
    case workoutStart = "rauta-workout-start"
    case workoutFinish = "rauta-workout-finish"
    case menuOpen = "rauta-menu-open"
    case planBuilt = "rauta-plan-built"
    case favoriteOn = "rauta-favorite-on"
    case favoriteOff = "rauta-favorite-off"
    case warning = "rauta-warning"

    /// Which switch in Settings it answers to, and how it is played.
    nonisolated enum Channel: Sendable {
        /// Countdowns and rest: heard with the phone in a pocket, over music.
        case cue
        /// The rest of a workout's moments: a set logged, a workout done.
        case workout
        /// The app's own taps and answers.
        case interface
    }

    var channel: Channel {
        switch self {
        case .tick3, .tick2, .tick1, .restOver, .warmupOver: return .cue
        case .restStart, .setLogged, .exerciseDone, .workoutStart, .workoutFinish: return .workout
        case .menuOpen, .planBuilt, .favoriteOn, .favoriteOff, .warning: return .interface
        }
    }

    /// The tick for each of a countdown's last seconds.
    static func tick(secondsLeft: Int) -> RautaSound {
        switch secondsLeft {
        case ...1: return .tick1
        case 2: return .tick2
        default: return .tick3
        }
    }

    /// The file a notification plays, from the bundle's root.
    var notificationFile: String { rawValue + ".caf" }
}

/// Every sound the app makes, played the way a navigation app speaks: over the
/// person's music, never instead of it.
///
/// - At rest the session is ambient, so nothing the app does can stop what is
///   playing.
/// - The workout's own moments — a set logged, a rest starting — play on top of
///   the music, heard in silent mode and on a locked phone, and leave its
///   volume alone.
/// - Only the countdown and the end of a rest or warm-up dip the music, once
///   for the whole countdown, and let it straight back up after.
///
/// Who is heard when two sounds want the same moment is ``SoundArbiter``'s to
/// decide; ``AudioOutput`` owns the session, the engine and the players, off
/// the main thread.
@MainActor
enum WorkoutAudio {
    /// Commands for the audio owner, in order. Built on first use, with the
    /// owner reading them for the life of the app.
    nonisolated private static let commands: AsyncStream<AudioCommand>.Continuation = {
        let (stream, continuation) = AsyncStream.makeStream(of: AudioCommand.self)
        let output = AudioOutput()
        Task { await output.run(stream) }
        return continuation
    }()

    private static var arbiter = SoundArbiter()
    /// What this tap has set off so far; only the most telling is sounded.
    private static var pendingTouch: RautaPhrase.Touch?
    private static var lastTouchAt = Date.distantPast
    private static var nextTouchPlayer = 0
    private static var nextPhrasePlayer = 0
    /// When the last sound with something to say began. A touch made in the
    /// same moment is left out: the sound is the answer to it.
    private static var soundBegan = Date.distantPast
    private static var durations: [RautaSound: TimeInterval] = [:]
    private static var observing = false

    /// The resting session. Set before anything can make a sound.
    static func configure() {
        guard !AppEnvironment.isRunningTests else { return }
        observeSystem()
        send(.configure)
    }

    /// Dictation takes the session for as long as it listens. Returns once the
    /// session is ready to record.
    static func beginVoice() async throws {
        try await withCheckedThrowingContinuation { continuation in
            commands.yield(.beginVoice(continuation))
        }
    }

    static func endVoice() {
        commands.yield(.endVoice)
    }

    // MARK: Sounds

    /// One of the app's moments: its rhythm in the hand, and its sound if
    /// that switch in Settings is on. A moment that loses its turn to a
    /// louder one is neither heard nor felt — except a refusal, which is
    /// always felt.
    static func play(_ sound: RautaSound) {
        let now = Date()
        let request = SoundArbiter.Request(priority: sound.priority, rank: sound.momentRank, duration: duration(of: sound))
        guard case .play(let silencing) = arbiter.decide(request, at: now) else {
            if sound == .warning { Haptics.play(sound.taps) }
            return
        }
        Haptics.play(sound.taps)
        guard allows(sound.channel) else { return }
        soundBegan = now
        send(.play(AudioPlay(
            source: .bundled(sound),
            style: sound.sessionStyle,
            player: AudioOutput.Player.player(for: sound.priority),
            // Cues and moments never queue: each one replaces whatever is
            // still sounding on its player, so none of them is heard late.
            interrupting: sound.priority >= .moment,
            silencing: silencing
        )))
    }

    /// Something made on the spot, felt as it is heard. `level` is how loud
    /// its loudest note is and `felt` how much of it reaches the hand. A
    /// phrase that does not `interrupt` waits its turn: it is dropped while
    /// something else is sounding, and kept out of a hand that is busy.
    static func play(
        _ notes: [SoundNote],
        on channel: RautaSound.Channel = .interface,
        level: Float = 0.2,
        felt: Float = 0.5,
        interrupts: Bool = true
    ) {
        guard !notes.isEmpty else { return }
        let now = Date()
        let priority: SoundPriority
        let style: AudioSessionStyle
        switch channel {
        case .cue: (priority, style) = (.cue, .ducking)
        case .workout: (priority, style) = (.moment, .mixed)
        case .interface: (priority, style) = (.phrase, .ambient)
        }
        let request = SoundArbiter.Request(
            priority: priority, duration: SoundSynth.length(notes), waitsForSilence: !interrupts
        )
        guard case .play(let silencing) = arbiter.decide(request, at: now) else { return }
        if interrupts || now >= Haptics.busyUntil {
            Haptics.play(HapticTap.following(notes, weight: felt))
        }
        guard allows(channel) else { return }
        soundBegan = now
        let player: Int
        if priority == .phrase {
            // Phrases take turns on two players, so the tail of one rings on
            // under the next instead of being cut or queued.
            nextPhrasePlayer = (nextPhrasePlayer + 1) % AudioOutput.Player.phrases.count
            player = AudioOutput.Player.phrases.lowerBound + nextPhrasePlayer
        } else {
            player = AudioOutput.Player.player(for: priority)
        }
        send(.play(AudioPlay(
            source: .notes(notes, level: level),
            style: style,
            player: player,
            interrupting: priority >= .moment,
            silencing: silencing
        )))
    }

    /// RAUTA saying a line: a few notes in the rhythm of its words, never the
    /// same twice, and never over another sound.
    static func voice(_ text: String, tone: RautaPhrase.Tone = .plain) {
        // VoiceOver reads the line out; notes over it would only get in the way.
        guard !UIAccessibility.isVoiceOverRunning else { return }
        var rng = SystemRandomNumberGenerator()
        play(RautaPhrase.spoken(text, tone: tone, using: &rng), interrupts: false)
    }

    /// The sound of touching something. A tap that sets off several — a
    /// button that ticks, then opens a page — is heard once, as whichever says
    /// most; and not at all under a sound that started with it.
    static func touch(_ touch: RautaPhrase.Touch) {
        if let pendingTouch {
            if touch.rank > pendingTouch.rank { self.pendingTouch = touch }
            return
        }
        pendingTouch = touch
        // Sounded once everything this tap does has been done.
        Task { @MainActor in flushTouch() }
    }

    private static func flushTouch() {
        guard let touch = pendingTouch else { return }
        pendingTouch = nil
        let now = Date()
        // A dial spun fast ticks like a dial, not like a buzzer.
        guard allows(.interface), now.timeIntervalSince(soundBegan) > 0.12,
              now.timeIntervalSince(lastTouchAt) > 0.03,
              !UIAccessibility.isVoiceOverRunning
        else { return }
        var rng = SystemRandomNumberGenerator()
        let (notes, level) = RautaPhrase.touch(touch, using: &rng)
        let request = SoundArbiter.Request(priority: .touch, duration: SoundSynth.length(notes))
        guard case .play = arbiter.decide(request, at: now) else { return }
        lastTouchAt = now
        nextTouchPlayer = (nextTouchPlayer + 1) % AudioOutput.Player.touches.count
        send(.play(AudioPlay(
            source: .notes(notes, level: level),
            style: .ambient,
            player: AudioOutput.Player.touches.lowerBound + nextTouchPlayer,
            interrupting: true,
            silencing: nil
        )))
    }

    /// One of the last seconds of a countdown.
    static func tick(secondsLeft: Int = 1) {
        play(.tick(secondsLeft: secondsLeft))
    }

    // MARK: Countdowns

    /// The last seconds of a rest or warm-up, from the first tick to just
    /// after `end` sounds at `deadline`. The music goes down once for all of
    /// it rather than dipping with every tick, and nothing but the countdown
    /// and the workout's own moments is heard over it.
    static func holdCountdown(endingAt deadline: Date, with end: RautaSound) {
        let until = deadline.addingTimeInterval(duration(of: end) + AudioSessionStyle.ducking.linger)
        arbiter.beginCountdown(until: until)
        guard allows(end.channel) else { return }
        send(.holdCountdown(until: until))
    }

    /// The countdown was called off — the rest skipped, ended or replaced.
    static func endCountdown() {
        arbiter.endCountdown()
        send(.endCountdown)
    }

    // MARK: Plumbing

    private static func send(_ command: AudioCommand) {
        // Under the unit tests the decisions are made but nothing sounds.
        guard !AppEnvironment.isRunningTests else { return }
        commands.yield(command)
    }

    private static func allows(_ channel: RautaSound.Channel) -> Bool {
        switch channel {
        case .cue, .workout: return SettingsStore.shared.workoutSoundsEnabled
        case .interface: return SettingsStore.shared.soundChimesEnabled
        }
    }

    /// How long a bundled sound lasts, read from its file's header once.
    static func duration(of sound: RautaSound) -> TimeInterval {
        if let known = durations[sound] { return known }
        var seconds = 0.4
        if let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf"),
           let file = try? AVAudioFile(forReading: url),
           file.fileFormat.sampleRate > 0 {
            seconds = Double(file.length) / file.fileFormat.sampleRate
        }
        durations[sound] = seconds
        return seconds
    }

    /// The system's own news about audio, handed to the owner in order: a call
    /// or another app taking the session, the media services restarting, the
    /// engine stopping for a new route, and the app leaving the screen.
    private static func observeSystem() {
        guard !observing else { return }
        observing = true
        addObservers()
    }

    /// `nonisolated`: these arrive on whatever thread posted them, and each
    /// only forwards a value.
    nonisolated private static func addObservers() {
        let center = NotificationCenter.default
        // A call, an alarm or another app took the session: it is no longer
        // ours. The app letting it go itself is posted too, and ignored.
        center.addObserver(forName: AVAudioSession.didBecomeInactiveNotification, object: nil, queue: nil) { note in
            let context = note.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext
            if context?.source == .system {
                commands.yield(.interrupted)
            }
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { _ in
            commands.yield(.mediaReset)
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { _ in
            commands.yield(.engineChanged)
        }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { _ in
            commands.yield(.backgrounded)
        }
    }
}
