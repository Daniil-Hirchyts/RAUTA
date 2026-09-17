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
@MainActor
enum WorkoutAudio {
    enum Style: Equatable {
        /// An interface chime: quiet, mixed in, silenced by the ring switch.
        case chime
        /// Something the person has to hear mid-workout, phone in pocket.
        case cue
    }

    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private static var wired = false
    private static var activeStyle: Style?
    private static var releaseTask: Task<Void, Never>?

    /// The resting session. Set before anything can make a sound.
    static func configure() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }

    // MARK: Sounds

    /// A short interface chime after a key action.
    static func chime(_ frequency: Double) {
        play(tones: [frequency], note: 0.17, gap: 0, peak: 0.08, style: .chime)
    }

    /// One of the last seconds of a countdown.
    static func tick() {
        play(tones: [880], note: 0.09, gap: 0, peak: 0.32, style: .cue)
    }

    /// Time to go: the countdown is over, the rest is done.
    static func go() {
        play(tones: [660, 990], note: 0.16, gap: 0.04, peak: 0.38, style: .cue)
    }

    // MARK: Playback

    private static func play(tones: [Double], note: Double, gap: Double, peak: Float, style: Style) {
        guard let format, let buffer = makeTone(tones, note: note, gap: gap, peak: peak, format: format)
        else { return }
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
                if !engine.attachedNodes.contains(player) { engine.attach(player) }
                try engine.connectNode(player, to: engine.mainMixerNode, format: format)
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
        player.scheduleBuffer(buffer, at: nil, options: []) {
            Task { @MainActor in scheduleRelease() }
        }
        guard !player.isPlaying else { return }
        do {
            try player.playAudio()
        } catch {
            // No playback means no completion callback to release the
            // session, so let go now rather than leave other audio ducked.
            release()
        }
    }

    /// Lets go of the session a moment after the last sound, so a countdown's
    /// ticks a second apart hold the music down once instead of pumping it.
    private static func scheduleRelease() {
        releaseTask?.cancel()
        releaseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.3))
            guard !Task.isCancelled else { return }
            release()
        }
    }

    private static func release() {
        releaseTask = nil
        player.stop()
        engine.stop()
        let session = AVAudioSession.sharedInstance()
        // Deactivating is what brings ducked music back up and resumes a paused
        // podcast.
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        configure()
        activeStyle = nil
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
