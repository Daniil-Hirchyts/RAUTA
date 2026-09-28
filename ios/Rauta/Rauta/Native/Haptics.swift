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
        // A success is sounded where it happens, by what it was — a set, a
        // plan — so only a refusal has a sound of its own here.
        if input == .warning { WorkoutAudio.play(.warning) }
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

/// Keeps the display awake while a workout is running.
@MainActor
enum ScreenAwake {
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        UIApplication.shared.isIdleTimerDisabled = enabled
        return true
    }
}
