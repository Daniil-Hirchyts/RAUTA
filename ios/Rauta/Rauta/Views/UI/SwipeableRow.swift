import SwiftUI

let swipeRevealWidth: CGFloat = 92
private let dragLockDistance: CGFloat = 8

/// A row that swipes left to reveal an action — typically delete — parked behind
/// it, iOS-list style. `isOpen` is lifted to the caller so a list can keep only
/// one row open at a time.
struct SwipeableRow<Content: View, Action: View>: View {
    @Binding var isOpen: Bool
    /// The card's right-side margin, included in the exposed action area.
    var actionInset: CGFloat = 0
    var revealWidth: CGFloat = swipeRevealWidth
    @ViewBuilder var action: () -> Action
    @ViewBuilder var content: () -> Content

    @State private var drag: CGFloat?
    @State private var locked = false

    private var settledX: CGFloat { isOpen ? -revealWidth : 0 }
    private var offset: CGFloat { drag ?? settledX }

    var body: some View {
        ZStack(alignment: .trailing) {
            action()
                .frame(width: revealWidth + actionInset)
                .opacity(offset < -1 ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: offset < -1)

            content()
                .offset(x: offset)
                .animation(drag == nil ? Theme.Motion.smoothOut(0.28) : nil, value: offset)
                .gesture(
                    DragGesture(minimumDistance: dragLockDistance)
                        .onChanged { value in
                            if !locked {
                                // Vertical intent — let the list scroll instead.
                                guard abs(value.translation.width)
                                    >= abs(value.translation.height)
                                else { return }
                                locked = true
                            }
                            drag = Swift.min(
                                0,
                                Swift.max(-revealWidth, settledX + value.translation.width)
                            )
                        }
                        .onEnded { _ in
                            guard locked else {
                                drag = nil
                                return
                            }
                            let finalX = drag ?? settledX
                            isOpen = finalX <= -revealWidth / 2
                            drag = nil
                            locked = false
                        }
                )
        }
    }
}

/// The delete parked behind a swiped row.
struct SwipeDeleteAction: View {
    var label: String
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.trigger(.warning)
            action()
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.primaryForeground)
                .frame(width: 52, height: 52)
                .background(Theme.primaryGradient, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
