import AVFoundation
import os

/// One thing for the audio to do, in values only, so it can cross from the
/// main actor to the audio owner.
nonisolated enum AudioCommand: Sendable {
    /// The resting session, set before anything can make a sound.
    case configure
    case play(AudioPlay)
    /// A countdown: the music dips now and stays down until `until`.
    case holdCountdown(until: Date)
    /// The countdown was cancelled: let the music back up after what is
    /// already sounding.
    case endCountdown
    /// Dictation takes the session; the continuation answers once it has.
    case beginVoice(CheckedContinuation<Void, any Error>)
    case endVoice
    /// The app left the screen.
    case backgrounded
    /// Another app or a call took the session away.
    case interrupted
    /// The media services restarted: everything built on them is gone.
    case mediaReset
    /// The engine stopped itself for a route or format change.
    case engineChanged
}

/// One sound to play.
nonisolated struct AudioPlay: Sendable {
    nonisolated enum Source: Sendable {
        /// A bundled `rauta-*.caf`.
        case bundled(RautaSound)
        /// Notes made on the spot, rendered on the audio queue.
        case notes([SoundNote], level: Float)
    }

    var source: Source
    var style: AudioSessionStyle
    /// Which player it plays on — see ``AudioOutput/Player``.
    var player: Int
    /// Cuts whatever is on that player, rather than queueing behind it.
    var interrupting: Bool
    /// Cuts every player below this priority first.
    var silencing: SoundPriority?
}

/// The one owner of the app's audio session, engine and players.
///
/// Every command runs here, in the order it was sent, on a serial queue of its
/// own: setting a category and activating a session can block for a moment,
/// and that moment no longer comes out of the interface. Each command runs to
/// the end without waiting on anything, so no two can interleave.
///
/// The session is let go when the timeline says the last sound has ended — not
/// when a player reports back — so a report that never comes can no longer
/// leave the person's music turned down.
actor AudioOutput {
    /// The players, one per kind of sound, so a tap never waits behind a
    /// countdown and a countdown never waits behind a tap.
    nonisolated enum Player {
        static let cue = 0
        static let moment = 1
        /// Phrases take turns on two, so one's tail rings on under the next.
        static let phrases = 2..<4
        /// Touches take turns on a few of their own, so a quick run of them
        /// overlaps instead of queueing up.
        static let touches = 4..<7
        static let count = 7

        static func player(for priority: SoundPriority) -> Int {
            switch priority {
            case .cue: return cue
            case .moment: return moment
            case .phrase: return phrases.lowerBound
            case .touch: return touches.lowerBound
            }
        }

        /// Every player a sound of `priority` can be on.
        static func players(for priority: SoundPriority) -> Range<Int> {
            switch priority {
            case .cue: return cue..<(cue + 1)
            case .moment: return moment..<(moment + 1)
            case .phrase: return phrases
            case .touch: return touches
            }
        }
    }

    private let queue = DispatchSerialQueue(label: "com.hirchyts.gymlib.audio", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private static let log = Logger(subsystem: "com.hirchyts.gymlib", category: "audio")

    private var engine = AVAudioEngine()
    private var players = (0..<Player.count).map { _ in AVAudioPlayerNode() }
    private var wired = false
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private var buffers: [RautaSound: AVAudioPCMBuffer] = [:]
    private var timeline = AudioTimeline()
    private var voiceHolds = 0
    private var releaseTask: Task<Void, Never>?

    /// Runs the commands, in order, for the life of the app.
    func run(_ commands: AsyncStream<AudioCommand>) async {
        for await command in commands {
            handle(command)
        }
    }

    private func handle(_ command: AudioCommand) {
        switch command {
        case .configure:
            setResting()
        case .play(let request):
            play(request)
        case .holdCountdown(let until):
            holdCountdown(until: until)
        case .endCountdown:
            guard timeline.style != nil else { return }
            timeline.shortenHold(at: Date())
            armRelease()
        case .beginVoice(let continuation):
            do {
                try beginVoice()
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        case .endVoice:
            voiceHolds = max(0, voiceHolds - 1)
            if voiceHolds == 0 { release() }
        case .backgrounded:
            // A countdown keeps going on a locked phone; anything else lets go.
            guard voiceHolds == 0, timeline.style != .ducking || timeline.releaseIsDue(at: Date()) else { return }
            if timeline.style != nil { release() }
        case .interrupted:
            // The system has already taken the session away.
            stopPlayers()
            engine.stop()
            timeline.released()
            releaseTask?.cancel()
            releaseTask = nil
        case .mediaReset:
            rebuild()
        case .engineChanged:
            // The engine stopped itself; the next sound starts it again and
            // sets every player going.
            timeline.clearQueues()
        }
    }

    // MARK: Playing

    private func play(_ request: AudioPlay) {
        guard voiceHolds == 0, let format else { return }
        let now = Date()
        if let silencing = request.silencing { silence(below: silencing) }
        guard enter(timeline.styleFor(request.style)) else { return }
        guard let buffer = buffer(for: request.source, format: format) else { return }
        do {
            try wireAndStart(format: format)
        } catch {
            Self.log.error("Starting the audio engine failed: \(error.localizedDescription, privacy: .public)")
            release()
            return
        }
        let player = players[request.player]
        player.scheduleBuffer(buffer, at: nil, options: request.interrupting ? .interrupts : [])
        do {
            // Every time: a player stopped with the engine stays stopped until
            // told again, and telling a playing one costs nothing.
            try player.playAudio()
        } catch {
            Self.log.error("A player would not start: \(error.localizedDescription, privacy: .public)")
            player.stop()
            return
        }
        let seconds = Double(buffer.frameLength) / buffer.format.sampleRate
        timeline.schedule(seconds, on: request.player, interrupting: request.interrupting, at: now)
        armRelease()
    }

    private func holdCountdown(until: Date) {
        guard voiceHolds == 0 else { return }
        guard enter(timeline.styleFor(.ducking)) else { return }
        timeline.hold(until: until)
        armRelease()
    }

    /// Stops the players of every kind below `priority`.
    private func silence(below priority: SoundPriority) {
        for kind in [SoundPriority.touch, .phrase, .moment] where kind < priority {
            for index in Player.players(for: kind) { players[index].stop() }
        }
    }

    // MARK: Session

    /// Puts the session in `style`, if it is not already in it. Ducking is
    /// applied when the session goes active, so stepping up into it from an
    /// active session deactivates first.
    private func enter(_ style: AudioSessionStyle) -> Bool {
        if timeline.style == style { return true }
        let session = AVAudioSession.sharedInstance()
        let wasActive = timeline.style != nil
        stopPlayers()
        engine.stop()
        timeline.clearQueues()
        do {
            if wasActive { try session.setActive(false) }
            switch style {
            case .ambient:
                // Ambient is mixable on its own; `.mixWithOthers` is not an
                // option it takes.
                try session.setCategory(.ambient, mode: .default)
            case .mixed:
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            case .ducking:
                try session.setCategory(
                    .playback,
                    mode: .voicePrompt,
                    options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
                )
            }
            try session.setActive(true)
        } catch {
            Self.log.error("Audio session for \(String(describing: style), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            timeline.released()
            setResting()
            return false
        }
        timeline.enter(style)
        return true
    }

    private func beginVoice() throws {
        voiceHolds += 1
        guard voiceHolds == 1 else { return }
        releaseTask?.cancel()
        releaseTask = nil
        stopPlayers()
        engine.stop()
        timeline.released()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            voiceHolds = 0
            setResting()
            throw error
        }
    }

    /// Lets go: deactivating is what brings ducked music back up and resumes
    /// a paused podcast.
    private func release() {
        releaseTask?.cancel()
        releaseTask = nil
        guard voiceHolds == 0 else { return }
        stopPlayers()
        engine.stop()
        timeline.released()
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            Self.log.error("Letting the audio session go failed: \(error.localizedDescription, privacy: .public)")
        }
        setResting()
    }

    /// The resting session: ambient, so nothing the app does can stop what
    /// the person is listening to.
    private func setResting() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        } catch {
            Self.log.error("Setting the resting audio session failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Wakes when the timeline says the last sound is over and lets go, unless
    /// something new has moved the moment on since.
    private func armRelease() {
        releaseTask?.cancel()
        let wait = max(0, timeline.holdUntil.timeIntervalSinceNow)
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait + 0.02))
            guard !Task.isCancelled else { return }
            await self?.releaseIfDue()
        }
    }

    private func releaseIfDue() {
        guard timeline.releaseIsDue(at: Date()) else {
            if timeline.style != nil { armRelease() }
            return
        }
        release()
    }

    // MARK: Engine

    private func wireAndStart(format: AVAudioFormat) throws {
        if !wired {
            for player in players {
                if !engine.attachedNodes.contains(player) { engine.attach(player) }
                try engine.connectNode(player, to: engine.mainMixerNode, format: format)
            }
            wired = true
        }
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    private func stopPlayers() {
        for player in players { player.stop() }
    }

    /// After a media services reset, nothing built before it works: a new
    /// engine and new players, wired on the next sound.
    private func rebuild() {
        releaseTask?.cancel()
        releaseTask = nil
        engine = AVAudioEngine()
        players = (0..<Player.count).map { _ in AVAudioPlayerNode() }
        wired = false
        timeline.released()
        voiceHolds = 0
        setResting()
    }

    // MARK: Buffers

    private func buffer(for source: AudioPlay.Source, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        switch source {
        case .bundled(let sound):
            return bundled(sound, format: format)
        case .notes(let notes, let level):
            return SoundSynth.buffer(notes, level: level, format: format)
        }
    }

    /// The bundled file, read once into memory. A file whose format does not
    /// match the players' would stop the engine, so it is refused and the
    /// sound falls back to a plain tone rather than to nothing.
    private func bundled(_ sound: RautaSound, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if let cached = buffers[sound] { return cached }
        if let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf"),
           let file = try? AVAudioFile(forReading: url),
           file.processingFormat.sampleRate == format.sampleRate,
           file.processingFormat.channelCount == format.channelCount,
           let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
           (try? file.read(into: buffer)) != nil {
            buffers[sound] = buffer
            return buffer
        }
        let fallback = SoundSynth.buffer(
            [SoundNote(at: 0, frequency: sound.channel == .interface ? 740 : 880, decay: 0.06)],
            level: 0.3,
            format: format
        )
        buffers[sound] = fallback
        return fallback
    }
}
