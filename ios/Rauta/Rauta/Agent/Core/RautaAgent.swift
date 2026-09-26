import Foundation
import FoundationModels
import MLX
import Observation
import os

enum AgentPhase: Equatable { case idle, thinking, working, ready, failed }

/// One conversation, with one generation task at a time. Tool outcomes are the
/// source of truth for actions; the model's own text is used only for replies
/// that did not call a tool.
@MainActor @Observable
final class RautaAgent {
    static let shared = RautaAgent()
    private static let log = Logger(subsystem: "com.hirchyts.gymlib", category: "agent")

    private(set) var items: [AgentItem] = []
    private(set) var phase: AgentPhase = .idle
    /// What RAUTA is doing right now, while a tool runs. Shown live, never kept
    /// in the transcript.
    private(set) var activity: String?
    /// The item that arrived last, so only it animates in.
    private(set) var freshItemId: UUID?
    /// Whether the chat is on screen. When it is not, RAUTA says its answer in
    /// its own bubble on the tab bar instead.
    var presented = false
    @ObservationIgnored private var settle: Task<Void, Never>?
    /// A design review is running on sample items; nothing may be written.
    @ObservationIgnored private var demo = false
    @ObservationIgnored private let host = AgentToolHost()
    @ObservationIgnored private var generation: Task<Void, Never>?
    @ObservationIgnored private var undoActions: [UUID: AgentUndo] = [:]
    @ObservationIgnored private var applyingProposals = Set<String>()
    @ObservationIgnored private var turnNumber = 0

    private struct Archive: Codable { var version: Int; var items: [AgentItem] }

    private init() {
        host.onActivity = { [weak self] title in
            self?.phase = .working
            self?.activity = title
        }
        let url = Storage.fileURL("agent-chat")
        if let data = try? Data(contentsOf: url),
           let archive = try? JSONDecoder().decode(Archive.self, from: data),
           archive.version == 1 {
            items = archive.items.filter { item in
                if case .activity = item.content { return false }
                return true
            }.map { item in
                var copy = item
                if copy.undo != nil { copy.undo = .gone }
                if case .card(.proposal(var card)) = copy.content, card.state == .pending {
                    card.state = .expired
                    copy.content = .card(.proposal(card))
                }
                return copy
            }
        }
    }

    func setBridge(_ bridge: AgentUIBridge?) { host.bridge = bridge }

    /// A workout or exercise shown in the chat, opened where it lives.
    func openWorkout(_ id: String) { host.bridge?.openWorkout(id) }
    func openExercise(_ id: String) { host.bridge?.openExercise(id) }

    var isReady: Bool { AgentModelStore.shared.installed }

    func send(_ raw: String, spoken: Bool = false) {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, generation == nil else { return }
        guard isReady else {
            append(.rauta("Download my brain first, then ask me about your training."))
            append(.card(.download))
            return
        }
        append(.user(input))
        settle?.cancel()
        activity = nil
        phase = .thinking
        turnNumber += 1
        let turn = turnNumber
        let previous = Array(items.dropLast())
        generation = Task { @MainActor in
            await run(input, previous: previous, turn: turn, spoken: spoken)
        }
    }

    private func run(_ input: String, previous: [AgentItem], turn: Int, spoken: Bool) async {
        host.begin(input)
        let today = CalendarDate.today
        let running = ActiveWorkoutStore.shared.session != nil
        var reply: String?
        var failure: Error?

        if let intent = AgentIntent.parse(input, today: today, running: running) {
            // Plain requests never wait on the model, and never fail in it.
            Self.log.info("Intent: \(String(describing: intent), privacy: .public)")
            await host.perform(intent, input: input)
        } else {
            let tools = AgentToolRouter.tools(for: input, host: host)
            let instructions = AgentContext.instructions(items: previous)
            do {
                #if targetEnvironment(simulator)
                let model = SystemLanguageModel.default
                guard model.availability == .available else { throw AgentModelUnavailable() }
                let session = LanguageModelSession(model: model, tools: tools, instructions: instructions)
                reply = try await session.respond(to: input,
                    options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 180)).content
                #else
                guard let model = AgentModelStore.shared.model() else { throw AgentModelUnavailable() }
                reply = try await AgentModelStore.respond(
                    model: model, tools: tools, instructions: instructions,
                    prompt: input, maximumTokens: 180
                )
                #endif
            } catch {
                failure = error
                if !(error is CancellationError) {
                    Self.log.error("Model turn failed: \(String(describing: error), privacy: .public)")
                }
            }

            // No tool ran. A malformed tool call, an empty answer, or words
            // about the model's own limits are never shown: the likeliest
            // reading of the request runs instead, still checked by the host.
            if host.outcome == nil, !(failure is CancellationError), !(failure is AgentModelUnavailable),
               turn == turnNumber, !Task.isCancelled {
                let usable = reply.flatMap(AgentReply.clean)
                let needsAction = AgentToolRouter.requiresTool(input)
                if usable == nil || needsAction || failure != nil,
                   let guess = AgentIntent.parse(input, today: today, running: running, loose: true) {
                    Self.log.info("Fallback intent: \(String(describing: guess), privacy: .public)")
                    host.begin(input)
                    await host.perform(guess, input: input)
                    reply = nil
                } else {
                    reply = needsAction ? nil : usable
                }
            }
        }

        guard turn == turnNumber, !Task.isCancelled else { return }
        activity = nil
        var said: String?
        if let result = host.outcome {
            append(.rauta(result.say))
            said = result.say
            if spoken && !host.dismissAfterTurn { VoiceIO.shared.speak(result.say) }
            if let card = result.card {
                let id = append(.card(card), undo: result.undo == nil ? nil : .available)
                if let undo = result.undo { undoActions[id] = undo }
            }
            finish(.ready)
        } else if let reply {
            append(.rauta(reply))
            said = reply
            if spoken { VoiceIO.shared.speak(reply) }
            finish(.ready)
        } else if failure is CancellationError {
            phase = .idle
        } else if let failure = failure as? AgentModelUnavailable {
            append(.failure(failure.localizedDescription))
            finish(.failed)
        } else {
            append(.rauta(AgentReply.fallback))
            said = AgentReply.fallback
            finish(.failed)
        }
        generation = nil
        if host.dismissAfterTurn { host.bridge?.dismissChat() }
        // The chat was put away while RAUTA worked: it says the answer itself.
        if !presented, let said, !host.dismissAfterTurn {
            RautaSpeech.shared.say(Self.firstSentence(said))
        }
    }

    /// Shows how the turn went for a moment, then settles back to listening.
    private func finish(_ outcome: AgentPhase) {
        phase = outcome
        settle?.cancel()
        settle = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled, let self, self.generation == nil else { return }
            self.phase = .idle
        }
    }

    private static func firstSentence(_ text: String) -> String {
        guard let end = text.firstIndex(where: { ".!?".contains($0) }) else { return text }
        return String(text[...end])
    }

    func stop() {
        guard generation != nil else { return }
        turnNumber += 1
        generation?.cancel()
        generation = nil
        host.cancel()
        activity = nil
        phase = .idle
    }

    func apply(_ proposalId: String) async {
        guard applyingProposals.insert(proposalId).inserted else { return }
        defer { applyingProposals.remove(proposalId) }
        let result = await host.apply(proposalId)
        for index in items.indices {
            guard case .card(.proposal(var card)) = items[index].content, card.id == proposalId else { continue }
            card.state = result.proposalApplied ? .applied
                : host.proposals[proposalId] == nil ? .expired : .pending
            items[index].content = .card(.proposal(card))
        }
        append(.rauta(result.say))
        if let card = result.card {
            let id = append(.card(card), undo: result.undo == nil ? nil : .available)
            if let undo = result.undo { undoActions[id] = undo }
        }
        persist()
    }

    func dismiss(_ proposalId: String) {
        for index in items.indices {
            guard case .card(.proposal(var card)) = items[index].content, card.id == proposalId else { continue }
            card.state = .dismissed
            items[index].content = .card(.proposal(card))
        }
        host.removeProposal(proposalId)
        persist()
    }

    func grant(_ permission: AgentPermission) async {
        switch permission {
        case .health:
            let granted = await HealthService.shared.requestReadinessAccess()
            append(.rauta(granted
                ? "The Health request is complete. Ask about readiness again; I'll use any data you shared."
                : "I couldn't access Health data. You can still plan without it."))
        case .calendar:
            let granted = await CalendarService.shared.requestAccess()
            append(.rauta(granted
                ? "Calendar access is set. Ask me to find a time or add a workout."
                : "I couldn't access your Calendar. You can allow full access in Settings."))
        case .notifications:
            let granted = await WorkoutReminders.shared.requestAccess()
            append(.rauta(granted
                ? "Notifications are ready. Ask me which workout to remind you about."
                : "I couldn't schedule reminders. You can allow notifications in Settings."))
        }
    }

    func undo(_ itemId: UUID) async {
        guard let action = undoActions[itemId],
              let index = items.firstIndex(where: { $0.id == itemId && $0.undo == .available })
        else { return }
        let result = await host.undo(action)
        append(.rauta(result.say))
        if result.say == "Undone." {
            items[index].undo = .undone
            undoActions[itemId] = nil
            persist()
        }
    }

    #if DEBUG
    /// Sample conversation for reviewing the chat's design (`--agent-demo`).
    /// Kept in memory only: the saved conversation is never touched.
    func showDemo(page: Int) {
        demo = true
        stop()
        items = AgentDemo.items(page: page)
        freshItemId = nil
        if page == 3 {
            // Mid-turn, then the answer lands: the hand-off between the two.
            phase = .working
            activity = "Adjusting your week…"
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(9))
                guard let self, self.demo else { return }
                self.activity = nil
                self.append(.rauta("I lightened the rest of your week."))
                self.finish(.ready)
            }
        }
    }
    #endif

    func startOver() {
        stop()
        host.forgetProposals()
        undoActions.removeAll()
        items.removeAll()
        guard !demo else { return }
        Storage.removeFile("agent-chat")
    }

    @discardableResult
    private func append(_ content: AgentItem.Content, undo: AgentItem.UndoState? = nil) -> UUID {
        var item = AgentItem(content: content)
        item.undo = undo
        items.append(item)
        freshItemId = item.id
        if items.count > 120 { items.removeFirst(items.count - 120) }
        persist()
        return item.id
    }

    private func persist() {
        guard !demo else { return }
        let url = Storage.fileURL("agent-chat")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Archive(version: 1, items: items))
            try data.write(to: url, options: .atomic)
        } catch { /* Chat stays available in memory if storage is full. */ }
    }
}

private struct AgentModelUnavailable: LocalizedError {
    var errorDescription: String? { "RAUTA's local model isn't available on this device." }
}
