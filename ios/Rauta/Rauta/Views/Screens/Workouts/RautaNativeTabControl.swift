import SwiftUI

struct RautaNativeTabControl: View {
    var mood: RautaMood
    @Binding var activeTab: MainTab
    var actionsForTab: (MainTab) -> [CompanionAction]
    var workoutActive = false
    var wrapped = false
    @Binding var isPresented: Bool
    var onPresent: () -> Void
    var onAsk: (Bool) -> Void
    /// Where the character is drawn, in global coordinates.
    var onSeat: (CGRect) -> Void = { _ in }
    var lift: CGFloat = 0
    @State private var reactionKey = ""
    /// The action picked from the menu, run once the thought has folded back
    /// into RAUTA, so the page it opens grows out of the character itself.
    @State private var pendingAction: (() -> Void)?

    static let zoomSourceID = "rauta-menu"

    private var controlSize: CGFloat {
        if wrapped { return 48 }
        return workoutActive ? 68 : 64
    }

    // IMPORTANT: the scroll-wrapped / inline exercise-player RAUTA MUST stay
    // smaller than the expanded version and centered in the SAME native
    // prominent circle. iOS 27 morphs that circle with the tab bar; do not hide
    // it or draw a replacement circle here.
    private var characterSize: CGFloat {
        if wrapped { return 40 }
        return workoutActive ? 56 : 62
    }

    var body: some View {
        let actions = actionsForTab(activeTab)

        Button(action: onPresent) {
            rautaFace
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rauta actions")
        .rautaThoughts(isPresented: $isPresented, lift: lift, onDismissed: runPendingAction) {
            RautaAskRow {
                pendingAction = { onAsk(false) }
                isPresented = false
            }
            ForEach(actions) { action in
                Button {
                    WorkoutAudio.touch(.tap)
                    pendingAction = action.action
                    isPresented = false
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            }
        }
        .onChange(of: isPresented) { _, presented in
            if presented, !actions.isEmpty {
                reactionKey = UUID().uuidString
            }
        }
        .accessibilityHidden(true)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: workoutActive)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: wrapped)
    }

    private func runPendingAction() {
        let action = pendingAction
        pendingAction = nil
        action?()
    }

    private var rautaFace: some View {
        ZStack {
            RautaCharacter(
                mood: mood,
                reactionKey: reactionKey
            )
            .frame(width: characterSize, height: characterSize)
            .offset(y: -3)
            .allowsHitTesting(false)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onSeat($0) }
        }
        .frame(width: controlSize, height: controlSize)
        .contentShape(Circle())
        .appZoomSource(Self.zoomSourceID, cornerRadius: controlSize / 2)
    }
}

/// The first thing in RAUTA's menu: somewhere to start talking. It looks like a
/// field because that is what it opens.
private struct RautaAskRow: View {
    var onAsk: () -> Void

    var body: some View {
        Button(action: onAsk) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                Text("Ask me anything…")
                    .font(Theme.sans(15, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Capsule().fill(Theme.input.opacity(0.55)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask RAUTA")
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }
}
