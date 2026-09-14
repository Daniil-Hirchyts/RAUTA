import Combine
import SwiftUI
import UIKit

extension AppAppearance {
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var summary: String {
        switch self {
        case .system: return "Follows your iPhone"
        case .light: return "Always light"
        case .dark: return "Always dark"
        }
    }
}

/// Puts the chosen theme on every window the app has.
///
/// The choice is made at the window, not with `preferredColorScheme`, so
/// everything the window hosts follows it at once — sheets, popovers, menus,
/// alerts and the status bar — and handing the choice back to the system really
/// does return to the iPhone's own setting.
@MainActor
enum AppearanceController {
    private static var cancellables = Set<AnyCancellable>()
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        apply(animated: false)
        SettingsStore.shared.changed
            .map { SettingsStore.shared.appearance }
            .removeDuplicates()
            .sink { _ in apply(animated: true) }
            .store(in: &cancellables)
        // A window that appears later — a new scene — wears the theme too.
        NotificationCenter.default.publisher(for: UIWindow.didBecomeVisibleNotification)
            .sink { _ in apply(animated: false) }
            .store(in: &cancellables)
    }

    static func apply(animated: Bool) {
        let style = SettingsStore.shared.appearance.interfaceStyle
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where window.overrideUserInterfaceStyle != style {
                guard animated else {
                    window.overrideUserInterfaceStyle = style
                    continue
                }
                // One cross-fade for the whole window reads as the room's lights
                // changing, not as every surface repainting on its own.
                UIView.transition(
                    with: window,
                    duration: 0.35,
                    options: [.transitionCrossDissolve, .allowUserInteraction]
                ) {
                    window.overrideUserInterfaceStyle = style
                }
            }
        }
    }
}

/// Applies the theme the moment the root view lands in its window, before the
/// window first draws — so a forced theme never flashes the system one first.
struct AppearanceWindowAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> AnchorView { AnchorView() }
    func updateUIView(_ uiView: AnchorView, context: Context) {}

    final class AnchorView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else { return }
            isUserInteractionEnabled = false
            window.overrideUserInterfaceStyle = SettingsStore.shared.appearance.interfaceStyle
        }
    }
}
