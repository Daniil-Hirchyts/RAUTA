import CoreHaptics
import UIKit

enum HapticInput: String {
    case selection, light, medium, heavy, success, warning
}

extension HapticInput {
    /// What a haptic sounds like when its caller says nothing more.
    var touch: RautaPhrase.Touch {
        switch self {
        case .selection: return .tick
        case .light: return .tap
        case .medium: return .press
        case .heavy: return .thud
        case .success: return .success
        case .warning: return .delete
        }
    }
}

/// One touch of a pattern: when it lands, how hard and how sharp.
struct HapticTap: Equatable {
    /// Seconds from the start of the pattern.
    var at: TimeInterval
    var intensity: Float
    /// 0 is a dull thud, 1 a crisp tick.
    var sharpness: Float
    /// Above zero it is a swell that fades over this long, not a tap. A swell
    /// is the last thing in its pattern.
    var length: TimeInterval = 0
}

/// What the hand feels. A picker's tick is the system's own; everything with a
/// shape — a sound's rhythm, a success, RAUTA talking — is a pattern, and no
/// pattern is played the same way twice.
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

    /// When the pattern being played will be over.
    private(set) static var busyUntil = Date.distantPast

    private static var engine: CHHapticEngine?
    /// No engine on this device, so nothing asks for one again.
    private static var engineMissing = false

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: ClosedRange<CGFloat>) {
        let generator = impactGenerators[style] ?? {
            let created = UIImpactFeedbackGenerator(style: style)
            created.prepare()
            impactGenerators[style] = created
            return created
        }()
        generator.impactOccurred(intensity: .random(in: intensity))
        generator.prepare()
    }

    /// Something was touched: felt, and heard as the touch it was. `sound`
    /// says more than the kind of haptic can — what was picked, which way a
    /// value went — where the caller knows it.
    static func trigger(_ input: HapticInput, sound: RautaPhrase.Touch? = nil) {
        // Every haptic is the app saying "the person just did something", which
        // is exactly what RAUTA reacts to — whether or not haptics are on.
        RautaDirector.shared.feedback(input)
        // A refusal has a sound of its own, which brings its own taps.
        if input == .warning, sound == nil {
            WorkoutAudio.play(.warning)
            return
        }
        // A moment with a richer sound — a set, a plan — drowns this one out.
        WorkoutAudio.touch(sound ?? input.touch)
        guard SettingsStore.shared.hapticsEnabled else { return }

        switch input {
        case .selection:
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
        // The same knock, never at quite the same strength, and now and then
        // from a neighbouring style.
        case .light: impact(Bool.random() ? .light : .soft, intensity: 0.6...1)
        case .medium: impact(Int.random(in: 0..<3) == 0 ? .rigid : .medium, intensity: 0.7...1)
        case .heavy: impact(.heavy, intensity: 0.8...1)
        case .success:
            var rng = SystemRandomNumberGenerator()
            if !play(success(using: &rng)) {
                notificationGenerator.notificationOccurred(.success)
                notificationGenerator.prepare()
            }
        case .warning:
            play(RautaSound.warning.taps)
        }
    }

    // MARK: Patterns

    /// Plays a pattern, a little differently each time. False when it could
    /// not be played: haptics are off, the app is not in front, or the device
    /// has no engine for it.
    @discardableResult
    static func play(_ taps: [HapticTap]) -> Bool {
        guard !taps.isEmpty, SettingsStore.shared.hapticsEnabled,
              UIApplication.shared.applicationState == .active,
              let engine = readyEngine()
        else { return false }
        var rng = SystemRandomNumberGenerator()
        let played = varied(taps, using: &rng)
        busyUntil = Date().addingTimeInterval((played.map { $0.at + $0.length }.max() ?? 0) + 0.2)

        var events: [CHHapticEvent] = []
        var curves: [CHHapticParameterCurve] = []
        for tap in played {
            let parameters = [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: tap.intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: tap.sharpness),
            ]
            if tap.length > 0 {
                events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: parameters, relativeTime: tap.at, duration: tap.length))
                curves.append(CHHapticParameterCurve(
                    parameterID: .hapticIntensityControl,
                    controlPoints: [.init(relativeTime: 0, value: 1), .init(relativeTime: tap.length, value: 0)],
                    relativeTime: tap.at
                ))
            } else {
                events.append(CHHapticEvent(eventType: .hapticTransient, parameters: parameters, relativeTime: tap.at))
            }
        }
        do {
            // Starting a running engine costs nothing; one the system stopped —
            // the app went away, a call came in — comes back here.
            try engine.start()
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameterCurves: curves))
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            return false
        }
    }

    /// The same pattern with a human hand on it: the whole of it a touch
    /// softer or crisper, each tap a touch stronger, sharper, earlier or later.
    static func varied(_ taps: [HapticTap], using rng: inout some RandomNumberGenerator) -> [HapticTap] {
        let lean = Float.random(in: 0.86...1, using: &rng)
        let tilt = Float.random(in: -0.08...0.08, using: &rng)
        return taps.enumerated().map { index, tap in
            var next = tap
            next.intensity = min(1, max(0.05, tap.intensity * lean * .random(in: 0.88...1.1, using: &rng)))
            next.sharpness = min(1, max(0, tap.sharpness + tilt + .random(in: -0.06...0.06, using: &rng)))
            if index > 0 { next.at = max(0, tap.at + .random(in: -0.006...0.006, using: &rng)) }
            return next
        }
    }

    /// Something went through: one of a few shapes, so it does not wear out.
    static func success(using rng: inout some RandomNumberGenerator) -> [HapticTap] {
        switch Int.random(in: 0..<3, using: &rng) {
        case 0:
            return [
                HapticTap(at: 0, intensity: 0.5, sharpness: 0.4),
                HapticTap(at: .random(in: 0.09...0.12, using: &rng), intensity: 0.9, sharpness: 0.6),
            ]
        case 1:
            return [
                HapticTap(at: 0, intensity: 0.4, sharpness: 0.35),
                HapticTap(at: 0.07, intensity: 0.55, sharpness: 0.5),
                HapticTap(at: 0.15, intensity: 0.9, sharpness: 0.65),
            ]
        default:
            return [
                HapticTap(at: 0, intensity: 0.75, sharpness: 0.5),
                HapticTap(at: 0.03, intensity: 0.45, sharpness: 0.3, length: 0.18),
            ]
        }
    }

    private static func readyEngine() -> CHHapticEngine? {
        if let engine { return engine }
        guard !engineMissing else { return nil }
        engine = makeEngine()
        engineMissing = engine == nil
        return engine
    }

    /// `nonisolated`: nothing the engine calls back on its own queue may be
    /// tied to the main actor.
    private nonisolated static func makeEngine() -> CHHapticEngine? {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = try? CHHapticEngine()
        else { return nil }
        // Taps only: it never touches the audio session the sounds run on.
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        return engine
    }
}

extension HapticTap {
    /// A phrase for the hand: a tap where each note lands, stronger for a
    /// louder note and crisper for a higher one. `weight` scales the whole of
    /// it; a murmur is felt less than a cue.
    static func following(_ notes: [SoundNote], weight: Float) -> [HapticTap] {
        guard weight > 0 else { return [] }
        var taps: [HapticTap] = []
        for note in notes.sorted(by: { $0.at < $1.at }) {
            let tap = HapticTap(
                at: note.at,
                intensity: min(1, (0.2 + 0.6 * Float(note.gain)) * weight),
                sharpness: min(1, max(0.1, 0.35 + 0.3 * Float(log2(note.frequency / 587.33))))
            )
            // Notes struck together are one touch.
            if let last = taps.last, note.at - last.at < 0.02 {
                if tap.intensity > last.intensity { taps[taps.count - 1].intensity = tap.intensity }
            } else {
                taps.append(tap)
            }
        }
        return taps
    }
}

extension RautaSound {
    /// The sound's rhythm for the hand: a tap where each of its notes lands.
    var taps: [HapticTap] {
        switch self {
        case .tick3, .tick2:
            return [HapticTap(at: 0, intensity: 0.5, sharpness: 0.6)]
        case .tick1:
            return [HapticTap(at: 0, intensity: 0.65, sharpness: 0.65)]
        case .restOver:
            return [
                HapticTap(at: 0, intensity: 0.7, sharpness: 0.5),
                HapticTap(at: 0.13, intensity: 1, sharpness: 0.7),
                HapticTap(at: 0.16, intensity: 0.5, sharpness: 0.4, length: 0.3),
            ]
        case .warmupOver:
            return [
                HapticTap(at: 0, intensity: 0.6, sharpness: 0.45),
                HapticTap(at: 0.11, intensity: 0.75, sharpness: 0.55),
                HapticTap(at: 0.22, intensity: 1, sharpness: 0.7),
                HapticTap(at: 0.25, intensity: 0.5, sharpness: 0.4, length: 0.3),
            ]
        case .restStart:
            return [
                HapticTap(at: 0, intensity: 0.5, sharpness: 0.55),
                HapticTap(at: 0.14, intensity: 0.4, sharpness: 0.2),
            ]
        case .setLogged:
            return [
                HapticTap(at: 0, intensity: 0.85, sharpness: 0.5),
                HapticTap(at: 0.045, intensity: 0.4, sharpness: 0.7),
            ]
        case .exerciseDone:
            return [
                HapticTap(at: 0, intensity: 0.55, sharpness: 0.4),
                HapticTap(at: 0.075, intensity: 0.65, sharpness: 0.5),
                HapticTap(at: 0.15, intensity: 0.75, sharpness: 0.6),
                HapticTap(at: 0.225, intensity: 1, sharpness: 0.7),
            ]
        case .workoutStart:
            return [
                HapticTap(at: 0, intensity: 0.7, sharpness: 0.35),
                HapticTap(at: 0.18, intensity: 1, sharpness: 0.6),
                HapticTap(at: 0.21, intensity: 0.55, sharpness: 0.4, length: 0.35),
            ]
        case .workoutFinish:
            return [
                HapticTap(at: 0, intensity: 0.55, sharpness: 0.4),
                HapticTap(at: 0.11, intensity: 0.65, sharpness: 0.5),
                HapticTap(at: 0.22, intensity: 0.75, sharpness: 0.6),
                HapticTap(at: 0.36, intensity: 0.95, sharpness: 0.7),
                HapticTap(at: 0.62, intensity: 0.45, sharpness: 0.55),
                HapticTap(at: 0.69, intensity: 0.5, sharpness: 0.55),
                HapticTap(at: 0.76, intensity: 0.55, sharpness: 0.55),
                HapticTap(at: 0.83, intensity: 0.6, sharpness: 0.55),
                HapticTap(at: 0.92, intensity: 1, sharpness: 0.75),
                HapticTap(at: 0.95, intensity: 0.6, sharpness: 0.4, length: 0.45),
            ]
        case .menuOpen:
            return [HapticTap(at: 0, intensity: 0.4, sharpness: 0.35)]
        case .planBuilt:
            return [
                HapticTap(at: 0, intensity: 0.35, sharpness: 0.35),
                HapticTap(at: 0.06, intensity: 0.4, sharpness: 0.4),
                HapticTap(at: 0.12, intensity: 0.45, sharpness: 0.45),
                HapticTap(at: 0.18, intensity: 0.5, sharpness: 0.5),
                HapticTap(at: 0.24, intensity: 0.6, sharpness: 0.55),
                HapticTap(at: 0.33, intensity: 0.95, sharpness: 0.7),
            ]
        case .favoriteOn:
            return [
                HapticTap(at: 0, intensity: 0.4, sharpness: 0.6),
                HapticTap(at: 0.07, intensity: 0.7, sharpness: 0.8),
            ]
        case .favoriteOff:
            return [HapticTap(at: 0, intensity: 0.4, sharpness: 0.25)]
        case .warning:
            return [
                HapticTap(at: 0, intensity: 0.85, sharpness: 0.15),
                HapticTap(at: 0.14, intensity: 0.85, sharpness: 0.1),
            ]
        }
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
