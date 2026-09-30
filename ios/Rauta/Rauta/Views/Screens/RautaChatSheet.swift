import SwiftUI

/// Talking to RAUTA.
///
/// Laid out the way Messages lays out a conversation — RAUTA at the top where
/// the contact sits, bubbles in between, the field at the bottom — on a page
/// lit in RAUTA's own warm glow, which breathes while it thinks. What RAUTA
/// changed arrives as the same cards the rest of the app draws, ready to open
/// or undo.
struct RautaChatSheet: View {
    var startDictation = false
    /// Opened from "Ask me anything…": the field is ready to type into.
    var focusOnOpen = false

    private let agent = RautaAgent.shared
    private let model = AgentModelStore.shared
    private let voice = VoiceIO.shared

    @State private var draft = ""
    @State private var atBottom = true
    /// Answers landed while the chat was open, each sending a pulse of light.
    @State private var answers = 0
    /// Where RAUTA and the bars sit on screen, so the light and its blur line
    /// up with them.
    @State private var rautaCenter = CGPoint(x: 200, y: 110)
    @State private var headerBottom: CGFloat = 170
    @State private var bottomBarHeight: CGFloat = 110
    @FocusState private var composing: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let bottomID = "bottom"

    var body: some View {
        transcript
            .safeAreaBar(edge: .top, spacing: 0) { header }
            .safeAreaBar(edge: .bottom, spacing: 0) { bottomBar }
            .background { surface }
            .onAppear { agent.presented = true }
            .onDisappear {
                agent.presented = false
                voice.cancel()
            }
            .task {
                if startDictation {
                    await voice.start()
                } else if focusOnOpen, model.installed {
                    try? await Task.sleep(for: .milliseconds(450))
                    composing = true
                }
            }
            .onChange(of: agent.phase) { old, new in
                // The answer landing sends one pulse of light out from RAUTA.
                if new == .ready, old == .thinking || old == .working { answers += 1 }
            }
            .onChange(of: draft) { _, text in
                // Return sends; a vertical field would otherwise take it as a new line.
                guard text.contains("\n") else { return }
                draft = text.replacingOccurrences(of: "\n", with: "")
                send()
            }
    }

    /// The page the conversation sits on: RAUTA's light, cut to the screen's
    /// own corners with a hairline edge, and a shadow for while it is carried
    /// back into RAUTA.
    private var surface: some View {
        RautaChatBackdrop(
            thinking: working,
            listening: voice.state == .recording,
            answers: answers,
            source: rautaCenter,
            blurTop: headerBottom,
            blurBottom: bottomBarHeight
        )
        .clipShape(ConcentricRectangle())
        .overlay { ConcentricRectangle().stroke(Theme.border, lineWidth: 2) }
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        .ignoresSafeArea()
    }

    // MARK: RAUTA

    private var mood: RautaMood {
        if voice.state == .recording { return .listening }
        switch agent.phase {
        case .thinking, .working: return .working
        case .ready: return .happy
        case .failed: return .confused
        case .idle:
            if !model.installed { return .sleepy }
            return composing || !draft.isEmpty ? .listening : .calm
        }
    }

    private var reaction: RautaReaction? {
        switch agent.phase {
        case .working: .gearUp
        case .ready: .acknowledge
        case .failed: .wobble
        case .idle, .thinking: nil
        }
    }

    /// RAUTA where Messages puts the contact: its face, and its name under it.
    /// The name opens the options, as a contact's name does; RAUTA itself is
    /// there to be poked. While it thinks it bobs at its work, as it does when
    /// it builds a plan. What scrolls up under them blurs away progressively,
    /// the way it does above the field.
    private var header: some View {
        VStack(spacing: 0) {
            RautaCharacter(mood: mood, reactionKey: "\(agent.phase)", reaction: reaction)
                .frame(width: 76, height: 76)
                .accessibilityLabel("RAUTA")
                // Measured before the bob, so bobbing never re-lays the page.
                .onGeometryChange(for: CGPoint.self) { proxy in
                    let frame = proxy.frame(in: .global)
                    return CGPoint(x: frame.midX, y: frame.midY)
                } action: { rautaCenter = $0 }
                .modifier(Bob(active: working && !reduceMotion))
            Menu {
                Button {
                    Haptics.trigger(.selection, sound: .delete)
                    agent.startOver()
                    draft = ""
                } label: {
                    Label("Start over", systemImage: "arrow.counterclockwise")
                }
                .disabled(agent.items.isEmpty)
                Divider()
                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
            } label: {
                Text("RAUTA")
                    .font(Theme.sans(13, weight: .heavy))
                    .kerning(0.6)
                    .foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .glassSurface(.regular, in: Capsule(), interactive: true)
                    .contentShape(Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("RAUTA options")
            .offset(y: -6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        // Room under the name, so the blur has faded in fully behind it.
        .padding(.bottom, 12)
        // The header's empty space belongs to the page, not to the messages
        // blurring under it: a drag down there carries the chat back into RAUTA.
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    if value.translation.height > 60 || value.predictedEndTranslation.height > 180 {
                        dismiss()
                    }
                }
        )
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { headerBottom = $0 }
    }

    /// RAUTA bobbing gently at its work.
    private struct Bob: ViewModifier {
        let active: Bool
        @State private var up = false

        func body(content: Content) -> some View {
            content
                .offset(y: up ? -4 : 2)
                .onChange(of: active, initial: true) { _, on in
                    if on {
                        withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) { up = true }
                    } else {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { up = false }
                    }
                }
        }
    }

    // MARK: Conversation

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if agent.items.isEmpty { intro }
                    ForEach(Array(agent.items.enumerated()), id: \.element.id) { index, item in
                        VStack(spacing: 0) {
                            if let stamp = timestamp(before: index) {
                                AgentTimestamp(date: stamp).padding(.top, index == 0 ? 4 : 18).padding(.bottom, 10)
                            }
                            AgentItemView(item: item, fresh: item.id == agent.freshItemId,
                                          tail: tail(at: index), agent: agent)
                        }
                        .padding(.top, gap(before: index))
                        .id(item.id)
                    }
                    if working {
                        AgentThinkingText(text: agent.activity ?? "Thinking…")
                            .padding(.top, 12)
                            .transition(.opacity)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 12)
                .animation(Theme.Motion.settleQuick, value: agent.phase)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxY >= geometry.contentSize.height - 60
            } action: { _, bottom in
                withAnimation(.snappy(duration: 0.2)) { atBottom = bottom }
            }
            .overlay(alignment: .bottom) {
                if !atBottom {
                    Button {
                        Haptics.trigger(.selection)
                        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.foreground)
                            .frame(width: 38, height: 38)
                            .glassSurface(.regular, in: Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .accessibilityLabel("Scroll to the latest")
                }
            }
            .onChange(of: agent.items.last?.id) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            .onChange(of: agent.phase) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
    }

    /// Bubbles from one side sit close; the other side, or a card, a little
    /// further; a new turn further still.
    private func gap(before index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        let item = agent.items[index]
        let previous = agent.items[index - 1]
        switch (previous.content, item.content) {
        case (.user, .user), (.rauta, .rauta): return 3
        case (_, .user): return 16
        case (.user, _): return 10
        default: return 8
        }
    }

    /// The last bubble of a run from one side carries the tail.
    private func tail(at index: Int) -> Bool {
        guard index + 1 < agent.items.count else { return true }
        switch (agent.items[index].content, agent.items[index + 1].content) {
        case (.user, .user), (.rauta, .rauta): return false
        default: return true
        }
    }

    /// A time over the first message, and over any turn begun a while after
    /// the one before it.
    private func timestamp(before index: Int) -> Date? {
        let item = agent.items[index]
        guard index > 0 else { return item.at }
        guard case .user = item.content else { return nil }
        return item.at.timeIntervalSince(agent.items[index - 1].at) > 15 * 60 ? item.at : nil
    }

    private var intro: some View {
        VStack(spacing: 8) {
            Text(model.installed ? "What should we change?" : "I need my brain first.")
                .font(Theme.sans(24, weight: .black))
                .tracking(-0.5)
                .foregroundStyle(Theme.foreground)
            Text(model.installed
                 ? "Move a workout, swap an exercise, rebuild your week. I do it; you can always undo."
                 : "It downloads once and runs on your iPhone, so your training stays private.")
                .font(Theme.sans(15, weight: .medium))
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !model.installed {
                AgentDownloadCard().padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: Composer

    private var working: Bool { agent.phase == .thinking || agent.phase == .working }
    private var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canSend: Bool { model.installed && !working && voice.state == .idle && hasDraft }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if showsSuggestions {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(AgentSuggestion.current()) { suggestion in
                            Button { use(suggestion) } label: {
                                Text(suggestion.title)
                                    .font(Theme.sans(14, weight: .semibold))
                                    .foregroundStyle(Theme.foreground)
                                    .padding(.horizontal, 14)
                                    .frame(height: 36)
                                    .background(Capsule().fill(Theme.foreground.opacity(0.07)))
                                    .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .scrollIndicators(.hidden)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let error = voice.error {
                Text(error)
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }
            composer.padding(.horizontal, 14)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: showsSuggestions)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height + proxy.safeAreaInsets.bottom
        } action: { bottomBarHeight = $0 }
    }

    /// Ready-made asks, while there is no conversation yet to go on from.
    /// After that they live behind the plus.
    private var showsSuggestions: Bool {
        model.installed && agent.items.isEmpty && draft.isEmpty && !working
            && voice.state == .idle
    }

    private static let fieldHeight: CGFloat = 44
    /// Glass for the controls resting on the bright lower edge: darkened just
    /// enough that what is typed and the placeholder stay readable on the glow.
    private static var controlGlass: GlassTone { .tinted(Theme.background.opacity(0.45)) }

    /// The plus, then the field with its one button inside: the microphone
    /// while it is empty, send once there is something to send, stop while
    /// RAUTA works.
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            plus

            HStack(alignment: .bottom, spacing: 6) {
                field
                    .font(Theme.sans(16, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, minHeight: Self.fieldHeight, alignment: .leading)
                fieldButton
                    .padding(.vertical, (Self.fieldHeight - 32) / 2)
            }
            .padding(.leading, 16)
            .padding(.trailing, (Self.fieldHeight - 32) / 2)
            .glassSurface(Self.controlGlass, in: RoundedRectangle(cornerRadius: Self.fieldHeight / 2, style: .continuous))
        }
    }

    @ViewBuilder private var field: some View {
        switch voice.state {
        case .recording:
            AgentListeningLevels()
        case .transcribing, .requesting:
            ShimmerText(text: voice.state == .transcribing ? "Catching that…" : "One moment…",
                        font: Theme.sans(16, weight: .medium))
        case .idle:
            TextField(
                model.installed ? "Ask RAUTA" : "Download my brain to talk",
                text: $draft,
                axis: .vertical
            )
            .lineLimit(1...5)
            .focused($composing)
            .submitLabel(.send)
            .disabled(!model.installed)
            .tint(Theme.primary)
        }
    }

    private var plus: some View {
        Menu {
            Section("Ask RAUTA to…") {
                ForEach(AgentSuggestion.current()) { suggestion in
                    Button { use(suggestion) } label: {
                        Label(suggestion.title, systemImage: suggestion.systemImage)
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.foreground)
                .frame(width: Self.fieldHeight, height: Self.fieldHeight)
                .glassSurface(Self.controlGlass, in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .disabled(!model.installed || working)
        .opacity(model.installed ? 1 : 0.5)
        .accessibilityLabel("Ready-made requests")
    }

    private enum FieldAction { case talk, send, stop, stopDictation, none }

    private var fieldAction: FieldAction {
        if voice.state == .recording { return .stopDictation }
        if working { return .stop }
        if voice.state != .idle || !model.installed { return .none }
        return hasDraft ? .send : .talk
    }

    @ViewBuilder private var fieldButton: some View {
        let action = fieldAction
        Button {
            switch action {
            case .send: send()
            case .stop:
                Haptics.trigger(.selection, sound: .off)
                agent.stop()
            case .talk, .stopDictation: dictate()
            case .none: break
            }
        } label: {
            Group {
                switch action {
                case .talk, .none:
                    Image(systemName: "mic.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: 32, height: 32)
                case .send:
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.primaryForeground)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Theme.primaryGradient))
                case .stop, .stopDictation:
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(action == .stopDictation ? Color.white : Theme.background)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(action == .stopDictation ? Theme.destructive : Theme.foreground))
                }
            }
            .contentShape(Circle())
            .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
        .buttonStyle(.plain)
        .disabled(action == .none)
        .opacity(action == .none ? 0.4 : 1)
        .animation(.snappy(duration: 0.2), value: action)
        .accessibilityLabel(accessibilityLabel(for: action))
    }

    private func accessibilityLabel(for action: FieldAction) -> String {
        switch action {
        case .talk, .none: "Talk to RAUTA"
        case .send: "Send"
        case .stop: "Stop RAUTA"
        case .stopDictation: "Stop dictation"
        }
    }

    // MARK: Actions

    private func send() {
        guard canSend else { return }
        let text = draft
        draft = ""
        Haptics.trigger(.light, sound: .send)
        agent.send(text)
    }

    private func use(_ suggestion: AgentSuggestion) {
        Haptics.trigger(.selection)
        if suggestion.sends {
            agent.send(suggestion.prompt)
        } else {
            draft = suggestion.prompt
            composing = true
        }
    }

    private func dictate() {
        if voice.state == .recording {
            Task {
                if let words = await voice.stop() { agent.send(words, spoken: true) }
            }
        } else {
            composing = false
            Task { await voice.start() }
        }
    }
}

/// Live bars from the microphone's own level while RAUTA listens.
private struct AgentListeningLevels: View {
    private let voice = VoiceIO.shared
    @State private var levels = Array(repeating: 0.0, count: 18)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(Theme.primary)
                        .frame(width: 3, height: 4 + level * 18)
                }
                Text("Listening…")
                    .font(Theme.sans(15, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.leading, 8)
            }
            .frame(height: 22)
            .onChange(of: timeline.date) { _, _ in
                levels.removeFirst()
                levels.append(voice.level())
            }
        }
        .accessibilityLabel("Listening")
    }
}
