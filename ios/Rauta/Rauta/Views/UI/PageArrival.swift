import SwiftUI

extension EnvironmentValues {
    /// Whether the tab's page has finished arriving since it last came into
    /// view. Off while it is away, on as it appears: its cards arrive against
    /// it, once per visit rather than every time one scrolls back into view.
    @Entry var pageArrived: Bool = true
}

/// A card arriving with its page: rising a little into place as it fades in,
/// one card after another.
struct PageArrival: ViewModifier {
    let order: Int
    @Environment(\.pageArrived) private var arrived
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(arrived ? 1 : 0)
            .offset(y: arrived || reduceMotion ? 0 : 14)
            .animation(
                arrived
                    ? .spring(response: 0.5, dampingFraction: 0.86).delay(Double(order) * 0.06)
                    : nil,
                value: arrived
            )
    }
}

/// A tab's page coming into view: what is on it arrives, to a few quiet notes.
private struct PageArrives: ViewModifier {
    /// Off when the page opens behind something else — a workout already
    /// pushed over its list — so nothing is sounded for what is not seen.
    let sounds: Bool
    @State private var arrived = false

    func body(content: Content) -> some View {
        content
            .environment(\.pageArrived, arrived)
            .onAppear {
                arrived = false
                Task { @MainActor in
                    arrived = true
                    guard sounds else { return }
                    // Never over something else that is sounding.
                    var rng = SystemRandomNumberGenerator()
                    WorkoutAudio.play(RautaPhrase.arrival(using: &rng), level: 0.11, felt: 0.4, interrupts: false)
                }
            }
            .onDisappear { arrived = false }
    }
}

extension View {
    /// Arrives with the page it is on, `order` cards after the first.
    func pageArrival(_ order: Int) -> some View {
        modifier(PageArrival(order: order))
    }

    /// Makes this the page of a tab: each time the tab is opened, everything
    /// marked ``pageArrival(_:)`` on it arrives again.
    func arrivesAsPage(sounds: Bool = true) -> some View {
        modifier(PageArrives(sounds: sounds))
    }
}
