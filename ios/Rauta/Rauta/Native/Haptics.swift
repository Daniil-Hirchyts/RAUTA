import AVFoundation
import UIKit

enum HapticInput: String {
    case selection, light, medium, heavy, success, warning
}

/// Each input maps onto the real UIKit feedback generator it was named for.
@MainActor
enum Haptics {
    private static let selectionGenerator: UISelectionFeedbackGenerator = {
        let generator = UISelectionFeedbackGenerator()
        // A prepared generator is what keeps the tick latency low.
        generator.prepare()
        return generator
    }()

    private static let notificationGenerator: UINotificationFeedbackGenerator = {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        return generator
    }()

    private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = impactGenerators[style] ?? {
            let created = UIImpactFeedbackGenerator(style: style)
            created.prepare()
            impactGenerators[style] = created
            return created
        }()
        generator.impactOccurred()
        generator.prepare()
    }

    static func trigger(_ input: HapticInput) {
        // Every haptic is the app saying "the person just did something", which
        // is exactly what RAUTA reacts to — whether or not haptics are on.
        RautaDirector.shared.feedback(input)
        let settings = SettingsStore.shared
        if settings.soundChimesEnabled, input == .success || input == .warning {
            Chimes.play(input == .success ? 740 : 420)
        }
        guard settings.hapticsEnabled else { return }

        switch input {
        case .selection:
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
        case .light: impact(.light)
        case .medium: impact(.medium)
        case .heavy: impact(.heavy)
        case .success:
            notificationGenerator.notificationOccurred(.success)
            notificationGenerator.prepare()
        case .warning:
            notificationGenerator.notificationOccurred(.warning)
            notificationGenerator.prepare()
        }
    }
}

/// Short synthesised tones for the interface chimes.
enum Chimes {
    private static let engineBox = EngineBox()

    private final class EngineBox: @unchecked Sendable {
        var engine: AVAudioEngine?
        var player: AVAudioPlayerNode?
        let lock = NSLock()
    }

    private static func makeTone(
        frequencies: [Double],
        noteDuration: Double,
        gap: Double,
        peak: Float
    ) -> AVAudioPCMBuffer? {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        else { return nil }
        let total = noteDuration * Double(frequencies.count) + gap * Double(frequencies.count - 1)
        let frameCount = AVAudioFrameCount(sampleRate * Swift.max(total, noteDuration))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frameCount

        for frame in 0..<Int(frameCount) { channel[frame] = 0 }

        for (index, frequency) in frequencies.enumerated() {
            let start = Int(sampleRate * (Double(index) * (noteDuration + gap)))
            let length = Int(sampleRate * noteDuration)
            for offset in 0..<length {
                let frame = start + offset
                guard frame < Int(frameCount) else { break }
                let time = Double(offset) / sampleRate
                // A short exponential swell and decay, so the note reads as a
                // chime rather than a click.
                let attack = Swift.min(1.0, time / 0.015)
                let decay = exp(-time / (noteDuration * 0.35))
                let envelope = Float(attack * decay)
                channel[frame] += Float(sin(2 * .pi * frequency * time)) * envelope * peak
            }
        }
        return buffer
    }

    private static func play(buffer: AVAudioPCMBuffer) {
        engineBox.lock.lock()
        defer { engineBox.lock.unlock() }

        let engine = engineBox.engine ?? AVAudioEngine()
        let player = engineBox.player ?? AVAudioPlayerNode()
        if engineBox.engine == nil {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            engineBox.engine = engine
            engineBox.player = player
        }
        do {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning { try engine.start() }
            player.scheduleBuffer(buffer, at: nil, options: [.interrupts])
            player.play()
        } catch {
            // Audio feedback is optional; blocked playback is harmless.
        }
    }

    static func play(_ frequency: Double) {
        guard let buffer = makeTone(
            frequencies: [frequency], noteDuration: 0.17, gap: 0, peak: 0.08
        ) else { return }
        play(buffer: buffer)
    }
}

/// Keeps the display awake while a workout is running.
@MainActor
enum ScreenAwake {
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        UIApplication.shared.isIdleTimerDisabled = enabled
        return true
    }
}
