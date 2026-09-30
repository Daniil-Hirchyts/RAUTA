import AVFoundation
import UIKit

/// Every sound the app makes, played the way a navigation app speaks: over the
/// person's music, never instead of it.
///
/// At rest the audio session is ambient and mixable, so nothing the app does —
/// a chime, the animation runtime, anything — can stop what is playing. A
/// workout cue switches to playback for its length: it is heard in silent mode
/// and on a locked screen, lowers other audio while it sounds, and pauses a
/// podcast rather than talking over it. A moment after the last cue the session
/// lets go and the music comes back up.
/// The app's sounds: one family, made for Rauta by `scripts/sounds/generate.py`
/// and bundled as `rauta-<name>.caf`. Soft sine tones for the cues and the
/// taps, a marimba where something is completed. What is made on the spot —
/// RAUTA's voice, a thought, a page arriving — is a ``RautaPhrase``.
enum RautaSound: String, CaseIterable {
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
    enum Channel {
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

@MainActor
enum WorkoutAudio {
    enum Style: Equatable {
        /// An interface chime: quiet, mixed in, silenced by the ring switch.
        case chime
        /// Something the person has to hear mid-workout, phone in pocket.
        case cue
    }

    private static let engine = AVAudioEngine()
    /// Cues and workout moments on one node, the app's taps on another, so a
    /// tap never waits behind a countdown.
    private static let player = AVAudioPlayerNode()
    private static let interfacePlayer = AVAudioPlayerNode()
    /// Touches take turns on a few nodes of their own, so a quick run of them
    /// overlaps instead of queueing up.
    private static let touchPlayers = (0..<3).map { _ in AVAudioPlayerNode() }
    private static var nextTouchPlayer = 0
    /// What this tap has set off so far; only the most telling is sounded.
    private static var pendingTouch: RautaPhrase.Touch?
    private static var lastTouchAt = Date.distantPast
    private static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private static var wired = false
    private static var activeStyle: Style?
    private static var releaseTask: Task<Void, Never>?
    private static var voiceHolds = 0
    /// Buffers still playing; the session lets go once none are.
    private static var playing = 0
    private static var buffers: [RautaSound: AVAudioPCMBuffer] = [:]
    /// When whatever is sounding will be over. RAUTA does not talk over it.
    private static var soundingUntil = Date.distantPast
    /// When the last sound with something to say began. A touch made in the
    /// same moment is left out: the sound is the answer to it.
    private static var soundBegan = Date.distantPast

    /// The resting session. Set before anything can make a sound.
    static func configure() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }

    static func beginVoice() throws {
        voiceHolds += 1
        guard voiceHolds == 1 else { return }
        releaseTask?.cancel()
        stopPlayers()
        engine.stop()
        activeStyle = nil
        playing = 0
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            voiceHolds = 0
            configure()
            throw error
        }
    }

    static func endVoice() {
        voiceHolds = max(0, voiceHolds - 1)
        guard voiceHolds == 0 else { return }
        release()
    }

    // MARK: Sounds

    /// One of the app's moments: its rhythm in the hand, and its sound if
    /// that switch in Settings is on.
    static func play(_ sound: RautaSound) {
        Haptics.play(sound.taps)
        guard allows(sound.channel), let buffer = buffer(for: sound) else { return }
        play(buffer, on: sound.channel)
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
        let now = Date()
        guard !notes.isEmpty, interrupts || now >= soundingUntil else { return }
        if interrupts || now >= Haptics.busyUntil {
            Haptics.play(HapticTap.following(notes, weight: felt))
        }
        guard allows(channel), let format,
              let buffer = SoundSynth.buffer(notes, level: level, format: format)
        else { return }
        play(buffer, on: channel)
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
              !UIAccessibility.isVoiceOverRunning, let format
        else { return }
        var rng = SystemRandomNumberGenerator()
        let (notes, level) = RautaPhrase.touch(touch, using: &rng)
        guard let buffer = SoundSynth.buffer(notes, level: level, format: format) else { return }
        lastTouchAt = now
        nextTouchPlayer = (nextTouchPlayer + 1) % touchPlayers.count
        play(buffer, style: .chime, on: touchPlayers[nextTouchPlayer], options: .interrupts)
    }

    /// One of the last seconds of a countdown.
    static func tick(secondsLeft: Int = 1) {
        play(.tick(secondsLeft: secondsLeft))
    }

    private static func allows(_ channel: RautaSound.Channel) -> Bool {
        switch channel {
        case .cue, .workout: return SettingsStore.shared.workoutSoundsEnabled
        case .interface: return SettingsStore.shared.soundChimesEnabled
        }
    }

    /// The bundled file, read once into memory. A file whose format does not
    /// match the player's would stop the engine, so it is refused and the
    /// sound falls back to a plain tone rather than to nothing.
    private static func buffer(for sound: RautaSound) -> AVAudioPCMBuffer? {
        if let cached = buffers[sound] { return cached }
        guard let format else { return nil }
        if let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf"),
           let file = try? AVAudioFile(forReading: url),
           file.processingFormat.sampleRate == format.sampleRate,
           file.processingFormat.channelCount == format.channelCount,
           let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
           (try? file.read(into: buffer)) != nil {
            buffers[sound] = buffer
            return buffer
        }
        let fallback = makeTone([sound.channel == .interface ? 740 : 880], note: 0.12, gap: 0, peak: 0.3, format: format)
        buffers[sound] = fallback
        return fallback
    }

    // MARK: Playback

    private static func play(_ buffer: AVAudioPCMBuffer, on channel: RautaSound.Channel) {
        let seconds = Double(buffer.frameLength) / buffer.format.sampleRate
        soundBegan = Date()
        soundingUntil = max(soundingUntil, soundBegan.addingTimeInterval(seconds + 0.25))
        play(buffer, style: channel == .interface ? .chime : .cue, on: channel == .interface ? interfacePlayer : player)
    }

    private static func play(
        _ buffer: AVAudioPCMBuffer,
        style: Style,
        on node: AVAudioPlayerNode,
        options: AVAudioPlayerNodeBufferOptions = []
    ) {
        guard voiceHolds == 0, let format else { return }
        releaseTask?.cancel()

        let session = AVAudioSession.sharedInstance()
        // A cue outranks a chime: once the session is set for cues it stays so
        // until it is released.
        let wanted: Style = activeStyle == .cue ? .cue : style
        if wanted != activeStyle {
            engine.stop()
            do {
                switch wanted {
                case .chime:
                    try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                case .cue:
                    try session.setCategory(
                        .playback,
                        mode: .voicePrompt,
                        options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
                    )
                }
                try session.setActive(true)
            } catch {
                return
            }
            activeStyle = wanted
        }

        do {
            if !wired {
                for node in [player, interfacePlayer] + touchPlayers {
                    if !engine.attachedNodes.contains(node) { engine.attach(node) }
                    try engine.connectNode(node, to: engine.mainMixerNode, format: format)
                }
                wired = true
            }
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
        } catch {
            release()
            return
        }
        playing += 1
        node.scheduleBuffer(buffer, at: nil, options: options) {
            Task { @MainActor in
                playing = max(0, playing - 1)
                if playing == 0 { scheduleRelease() }
            }
        }
        guard !node.isPlaying else { return }
        do {
            try node.playAudio()
        } catch {
            // No playback means no completion callback to release the
            // session, so let go now rather than leave other audio ducked.
            release()
        }
    }

    /// Lets go of the session a moment after the last sound, so a countdown's
    /// ticks a second apart hold the music down once instead of pumping it.
    /// Chimes hold nothing down, so their session stays a while longer: the
    /// next touch is heard at once instead of waiting for the engine to start.
    private static func scheduleRelease() {
        releaseTask?.cancel()
        let linger: Double = activeStyle == .cue ? 1.3 : 8
        releaseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(linger))
            guard !Task.isCancelled else { return }
            release()
        }
    }

    private static func release() {
        guard voiceHolds == 0 else { return }
        releaseTask = nil
        stopPlayers()
        playing = 0
        engine.stop()
        let session = AVAudioSession.sharedInstance()
        // Deactivating is what brings ducked music back up and resumes a paused
        // podcast.
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        configure()
        activeStyle = nil
    }

    private static func stopPlayers() {
        for node in [player, interfacePlayer] + touchPlayers { node.stop() }
    }

    private static func makeTone(
        _ frequencies: [Double],
        note: Double,
        gap: Double,
        peak: Float,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let total = note * Double(frequencies.count) + gap * Double(max(0, frequencies.count - 1))
        let frameCount = AVAudioFrameCount(sampleRate * max(total, note))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) { channel[frame] = 0 }

        for (index, frequency) in frequencies.enumerated() {
            let start = Int(sampleRate * Double(index) * (note + gap))
            let length = Int(sampleRate * note)
            for offset in 0..<length {
                let frame = start + offset
                guard frame < Int(frameCount) else { break }
                let time = Double(offset) / sampleRate
                // A short swell and decay, so a note reads as a chime rather
                // than a click.
                let attack = min(1.0, time / 0.012)
                let decay = exp(-time / (note * 0.45))
                channel[frame] += Float(sin(2 * .pi * frequency * time)) * Float(attack * decay) * peak
            }
        }
        return buffer
    }
}
