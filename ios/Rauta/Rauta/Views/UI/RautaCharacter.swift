import SwiftUI
import RiveRuntime

/// Uses the exact artboard and state machine shipped by the React app.
struct RautaCharacter: View {
    var mood: RautaMood = .calm
    var reactionKey = ""
    var onActivate: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @StateObject private var rig = RiveViewModel(fileName: "Media/rauta", stateMachineName: "KettlebellBotMachine", artboardName: "KettlebellBot", loadCdn: false)
    @State private var drag = CGSize.zero
    @State private var activity = RautaActivity()

    var body: some View {
        rig.view().offset(drag)
            .onAppear(perform: updateMood)
            .onChange(of: mood) { _, _ in updateMood() }
            .onChange(of: reactionKey) { _, _ in react(.acknowledge, source: .explicit) }
            .onTapGesture { react(.tapped, source: .interaction); onActivate?(); Haptics.trigger(.light) }
            .gesture(DragGesture(minimumDistance: 8).onChanged { value in
                drag = value.translation
                rig.setInput("pressed", value: true)
                rig.setInput("gazeX", value: Double(max(-1, min(1, drag.width / 100))))
                rig.setInput("gazeY", value: Double(max(-1, min(1, drag.height / 100))))
            }.onEnded { _ in
                rig.setInput("pressed", value: false)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) { drag = .zero }
                react(.wobble, source: .interaction)
            })
            .task {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1.1)) } catch { return }
                    guard !reducedMotion else { continue }
                    let result = RautaScheduler.idle(activity, now: Date().timeIntervalSince1970 * 1000)
                    activity = result.activity
                    if let reaction = result.play { rig.triggerInput(reaction.rawValue) }
                }
            }
            .accessibilityLabel(onActivate == nil ? "Interact with RAUTA" : "Open RAUTA actions")
            .accessibilityAddTraits(.isButton)
    }
    private func updateMood() {
        rig.setInput("status", value: Double(mood.status))
        rig.setInput("intensity", value: mood.intensity)
    }
    private func react(_ reaction: RautaReaction, source: RautaSource) {
        let result = RautaScheduler.request(activity, source: source, reaction: reaction, now: Date().timeIntervalSince1970 * 1000)
        activity = result.activity
        if let reaction = result.play { rig.triggerInput(reaction.rawValue) }
    }
}

struct CompanionAction: Identifiable {
    var title: String
    var primary = false
    var action: () -> Void
    var id: String { title }
}

struct RautaBottomDock: View {
    var speech: String
    var meta: String?
    var mood: RautaMood = .calm
    var actions: [CompanionAction] = []
    var characterSize: CGFloat = 104
    @State private var open = false

    private var reserve: CGFloat { characterSize * 0.8 }
    private var minimumHeight: CGFloat { max(96, characterSize * 0.92) }

    var body: some View {
        VStack(spacing: 0) {
            if open {
                VStack(spacing: 8) {
                    ForEach(actions) { action in
                        AppButton(action.title, variant: action.primary ? .primary : .secondary, expands: true) {
                            open = false; action.action()
                        }
                    }
                }.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 6)
            }
            Button { if !actions.isEmpty { withAnimation(.easeOut(duration: 0.22)) { open.toggle() } } } label: {
                VStack(spacing: 4) {
                    Text(speech).font(Theme.sans(15, weight: .semibold)).tracking(-0.3).multilineTextAlignment(.center)
                    if let meta { Text(meta).font(Theme.sans(12)).foregroundStyle(Theme.mutedForeground).lineLimit(1) }
                }.foregroundStyle(Theme.foreground).frame(maxWidth: .infinity).padding(.horizontal, reserve).padding(.top, 16).padding(.bottom, 20)
            }.buttonStyle(.plain).accessibilityLabel("RAUTA actions")
        }.frame(minHeight: minimumHeight)
            .background {
                ZStack {
                    Theme.card.opacity(0.94)
                    RadialGradient(colors: [Theme.primary.opacity(0.24), .clear], center: UnitPoint(x: 0.8, y: 1.25), startRadius: 0, endRadius: 230)
                }.clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.surfaceRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.surfaceRadius).strokeBorder(Theme.border))
            }
            .overlay(alignment: .bottomLeading) {
                RautaCharacter(mood: mood, reactionKey: speech, onActivate: { withAnimation { open.toggle() } })
                    .frame(width: characterSize, height: characterSize).offset(y: -8)
            }
    }
}
