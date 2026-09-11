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
    var characterSize: CGFloat = 112
    var floating = false
    var showsText = true
    @State private var open = false

    private var reserve: CGFloat { characterSize * 0.82 }
    private var minimumHeight: CGFloat { max(128, characterSize * 1.08) }
    private var expandedActionsHeight: CGFloat {
        let count = CGFloat(actions.count)
        return 20 + count * 44 + max(0, count - 1) * 8
    }
    /// RAUTA is a shell-level surface, so every corner follows the shell's
    /// continuous radius.
    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Metrics.surfaceRadius, style: .continuous)
    }

    var body: some View {
        if floating {
            floatingBody
        } else {
            panelBody
        }
    }

    private var panelBody: some View {
        ZStack(alignment: .bottom) {
            Button { if !actions.isEmpty { withAnimation(.easeOut(duration: 0.22)) { open.toggle() } } } label: {
                VStack(spacing: 4) {
                    Text(speech).font(Theme.sans(15, weight: .semibold)).tracking(-0.3).multilineTextAlignment(.center)
                    if let meta { Text(meta).font(Theme.sans(12)).foregroundStyle(Theme.mutedForeground).lineLimit(1) }
                }.foregroundStyle(Theme.foreground).frame(maxWidth: .infinity).padding(.horizontal, reserve).padding(.top, 22).padding(.bottom, 24)
            }.buttonStyle(.plain).accessibilityLabel("RAUTA actions")
                .frame(height: minimumHeight, alignment: .bottom)
        }
        .frame(height: minimumHeight)
            .background {
                ZStack {
                    Theme.card.opacity(0.94)
                    RadialGradient(colors: [Theme.primary.opacity(0.24), .clear], center: UnitPoint(x: 0.8, y: 1.25), startRadius: 0, endRadius: 230)
                }
                .clipShape(panelShape)
                .overlay(
                    panelShape
                        .strokeBorder(Theme.border)
                )
            }
            .overlay(alignment: .bottomLeading) {
                RautaCharacter(mood: mood, reactionKey: speech, onActivate: { withAnimation { open.toggle() } })
                    .frame(width: characterSize, height: characterSize).offset(x: 4, y: -10)
            }
            .overlay(alignment: .top) {
                if open, !actions.isEmpty {
                    GlassGroup(spacing: 4) {
                        VStack(spacing: 8) {
                            ForEach(actions) { action in
                                AppButton(action.title, variant: action.primary ? .primary : .secondary, expands: true) {
                                    open = false
                                    action.action()
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(
                        Theme.mix(Theme.card, Theme.primary, 0.08).opacity(0.96),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(Theme.Glassware.edge)
                    )
                    .padding(.horizontal, 16)
                    .offset(y: -expandedActionsHeight - 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(20)
                }
            }
            .zIndex(open ? 20 : 0)
    }

    private var floatingBody: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ZStack {
                RautaCharacter(
                    mood: mood,
                    reactionKey: speech,
                    onActivate: {
                        guard !actions.isEmpty else { return }
                        open = true
                    }
                )
                .frame(width: characterSize, height: characterSize)
                .popover(isPresented: $open, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                    AppMenuSurface(dismiss: { open = false }) {
                        ForEach(actions) { action in
                            Button {
                                open = false
                                action.action()
                            } label: {
                                Text(action.title)
                            }
                        }
                    }
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(.clear)
                }
            }
            .frame(width: characterSize + 18, height: characterSize + 10)

            if showsText {
                VStack(alignment: .leading, spacing: 4) {
                    Text(speech)
                        .font(Theme.sans(15, weight: .semibold))
                        .tracking(-0.3)
                        .lineLimit(2)
                    if let meta {
                        Text(meta)
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(Theme.foreground)
                .frame(maxWidth: .infinity, minHeight: characterSize * 0.72, alignment: .center)
                .padding(.trailing, 14)
                .padding(.bottom, 8)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .bottomLeading)
        .background {
            AppGradientBlur(edge: .bottom)
        }
    }
}
