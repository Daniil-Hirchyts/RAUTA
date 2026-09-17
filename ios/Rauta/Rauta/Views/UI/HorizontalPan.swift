import SwiftUI
import UIKit

/// A pan that only ever starts sideways.
///
/// SwiftUI's `DragGesture` cannot decline a vertical drag once it has seen the
/// touch, so on a scrolling page it competes with the scroll. A UIKit pan can:
/// it begins only when the finger moves more across than down, and otherwise
/// fails at once and leaves the drag to the scroll view.
struct HorizontalPan: UIGestureRecognizerRepresentable {
    struct Value {
        var translation: CGFloat
        var velocity: CGFloat
    }

    var onChanged: (Value) -> Void
    var onEnded: (Value) -> Void
    /// Taken over by the system — a scroll, an alert — rather than let go.
    var onCancelled: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let value = Value(
            translation: context.converter.localTranslation?.x ?? 0,
            velocity: context.converter.localVelocity?.x ?? 0
        )
        switch recognizer.state {
        case .began, .changed:
            onChanged(value)
        case .ended:
            onEnded(value)
        case .cancelled, .failed:
            onCancelled()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}
