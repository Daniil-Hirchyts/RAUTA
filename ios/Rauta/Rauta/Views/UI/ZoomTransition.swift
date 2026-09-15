import SwiftUI
import UIKit

// The zoom transition modals grow out of and fall back into.
//
// A view something opens from is marked with `appZoomSource(_:)`; the page it
// opens is presented with `appZoomTransition(from:)` naming the same id. From
// iOS 18 the system then owns the whole gesture: the page grows out of its
// source, follows a finger dragged down on it, and is thrown back into the
// source with the speed it was let go at. The source is tracked live, so a
// grid that scrolls while the page closes still receives it in the right
// place. Before iOS 18 pages present the plain way.

private struct AppZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// The one namespace every zoom source and zoomed page shares, set at the
    /// root so it reaches into every presentation.
    var appZoomNamespace: Namespace.ID? {
        get { self[AppZoomNamespaceKey.self] }
        set { self[AppZoomNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Marks the view a page can grow out of. `cornerRadius` is the shape the
    /// page shrinks back into, so it lands matching the view it came from.
    func appZoomSource(_ id: String, cornerRadius: CGFloat = 0) -> some View {
        modifier(AppZoomSource(id: id, cornerRadius: cornerRadius))
    }

    /// Presents this page growing out of the source named `id`. Without a
    /// source the page presents the ordinary way.
    func appZoomTransition(from id: String?) -> some View {
        modifier(AppZoomTransition(sourceID: id))
    }
}

/// ``View/appZoomSource(_:cornerRadius:)`` for a view that is only sometimes
/// something a page opens from.
struct OptionalZoomSource: ViewModifier {
    let id: String?
    var cornerRadius: CGFloat = 0

    func body(content: Content) -> some View {
        if let id {
            content.appZoomSource(id, cornerRadius: cornerRadius)
        } else {
            content
        }
    }
}

private struct AppZoomSource: ViewModifier {
    let id: String
    let cornerRadius: CGFloat
    @Environment(\.appZoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let namespace {
            content.matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            content
        }
    }
}

private struct AppZoomTransition: ViewModifier {
    let sourceID: String?
    @Environment(\.appZoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let namespace, let sourceID {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}

/// Whether zoomed presentations exist here, and so whether a page can leave
/// dismissal by dragging to the system.
enum AppZoom {
    static var isAvailable: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }
}

// MARK: - Swipe back

extension View {
    /// Keeps the swipe back on a navigation stack whose bar is hidden. UIKit
    /// ties the gesture to its bar and turns it off with it; every page here
    /// draws its own title bar, so it is turned back on — from the leading
    /// edge only, so a drag inside the page stays with the page's own dials,
    /// carousels and swipeable rows.
    func swipeBackEnabled() -> some View {
        background(SwipeBackEnabler().frame(width: 0, height: 0).allowsHitTesting(false))
    }
}

private struct SwipeBackEnabler: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ uiView: ProbeView, context: Context) { uiView.attach() }

    final class ProbeView: UIView {
        private weak var navigation: UINavigationController?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach()
            // A page arriving or leaving changes how deep the stack is; once
            // any transition has settled, hand the edge to the right gesture.
            let navigation = navigation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if let navigation { Self.assignLeadingEdge(in: navigation) }
            }
        }

        func attach() {
            var responder: UIResponder? = self
            while let current = responder, !(current is UINavigationController) {
                responder = current.next
            }
            guard let found = responder as? UINavigationController else { return }
            navigation = found

            // From iOS 26 the swipe back is recognised across the whole page,
            // and that recogniser is the one that receives an edge swipe.
            let swipe: UIGestureRecognizer?
            if #available(iOS 26.0, *) {
                swipe = found.interactiveContentPopGestureRecognizer
            } else {
                swipe = found.interactivePopGestureRecognizer
            }
            swipe?.isEnabled = true
            swipe?.delegate = SwipeBackDelegate.shared
            Self.assignLeadingEdge(in: found)
        }

        /// A zoomed modal also has a leading-edge pan that closes the whole
        /// modal, which would take the edge from going back a step. While there
        /// is a step to go back to, that pan is off; on a modal's first page it
        /// is left to the system.
        static func assignLeadingEdge(in navigation: UINavigationController) {
            let canGoBack = navigation.viewControllers.count > 1
            var view: UIView? = navigation.view
            while let current = view {
                for recognizer in current.gestureRecognizers ?? []
                where recognizer.name?.hasPrefix("com.apple.UIKit.ZoomInteractiveDismissLeadingEdge") == true {
                    recognizer.isEnabled = !canGoBack
                }
                view = current.superview
            }
        }
    }
}

/// Lets a swipe back start only from the leading edge, and only when there is
/// a page to go back to — on a stack's first page it would otherwise leave the
/// stack stuck mid-transition.
private final class SwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeBackDelegate()

    private static let edgeWidth: CGFloat = 28

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // With nothing to go back to, the swipe back must not even look at the
        // touch: it holds touches while it decides, and would starve the
        // modal's own edge pan of the gesture that closes it.
        guard canGoBack(gestureRecognizer), let window = touch.window else { return false }
        let x = touch.location(in: window).x
        return window.effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? x > window.bounds.width - Self.edgeWidth
            : x < Self.edgeWidth
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        canGoBack(gestureRecognizer)
    }

    private func canGoBack(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        var responder: UIResponder? = gestureRecognizer.view
        while let current = responder, !(current is UINavigationController) {
            responder = current.next
        }
        guard let navigation = responder as? UINavigationController else { return false }
        return navigation.viewControllers.count > 1 && navigation.transitionCoordinator == nil
    }
}

// MARK: - UIKit animation

/// Runs a SwiftUI change inside a UIKit animation, for the UIKit-backed pieces
/// SwiftUI hosts — the tab bar above all — whose layout `withAnimation` does
/// not reach. The change is applied and every window laid out while the
/// animation block is open, so UIKit animates the new frames.
@MainActor
enum UIKitAnimation {
    static func spring(duration: TimeInterval, bounce: CGFloat, _ changes: @escaping () -> Void) {
        UIView.animate(springDuration: duration, bounce: bounce, initialSpringVelocity: 0, delay: 0, options: [.allowUserInteraction]) {
            changes()
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                for window in scene.windows where !window.isHidden {
                    window.layoutIfNeeded()
                }
            }
        }
    }
}
