#if DEBUG
import Foundation
import FoundationModels
import MLX
import MLXFoundationModels
import MLXLMCommon
import SwiftUI
import Synchronization
import os

/// A debug bench for choosing RAUTA's model: downloads each candidate, then
/// measures loading, speed, memory, cancellation, and how well it picks and
/// fills tools on a fixed prompt suite.
///
/// Launch with `--agent-lab`; add `--agent-lab-autorun` to run everything
/// straight away. Results are printed as `AGENTLAB` lines and written to
/// `Documents/agent-lab/`.
enum AgentLab {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("--agent-lab") }
    static var autorun: Bool { ProcessInfo.processInfo.arguments.contains("--agent-lab-autorun") }
    /// `--agent-lab-only <id>` limits the run to one catalogue entry.
    static var only: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--agent-lab-only"), index + 1 < arguments.count
        else { return nil }
        return arguments[index + 1]
    }
}

// MARK: - Results

nonisolated struct LabChatMetrics: Codable, Sendable {
    var firstTokenSeconds: Double
    var totalSeconds: Double
    var outputTokens: Int
    var tokensPerSecond: Double
    var text: String
}

/// Reading the instructions and tool definitions every turn starts with, first
/// on a cold process and then warm.
nonisolated struct LabPrefillMetrics: Codable, Sendable {
    var promptTokens: Int
    var coldSeconds: Double
    var warmSeconds: Double
    var tokensPerSecond: Double
}

nonisolated struct LabCaseResult: Codable, Sendable {
    var id: String
    var prompt: String
    var toolOK: Bool
    var argumentsOK: Bool
    var calls: [LabToolCall]
    var reply: String
    var seconds: Double
    /// When the first tool call arrived; the rest is the model's closing words.
    var firstToolSeconds: Double?
    var error: String?
}

nonisolated struct LabModelResult: Codable, Sendable {
    var model: String
    var repo: String
    var revision: String
    var device: String
    var system: String
    var physicalMemoryGB: Double
    var downloadSeconds: Double?
    var loadSeconds: Double?
    var chat: LabChatMetrics?
    var prefill: LabPrefillMetrics?
    var cancelSeconds: Double?
    /// The same five-turn conversation through FoundationModels, which renders
    /// the whole transcript every turn, and through MLX's `ChatSession`, which
    /// keeps the KV cache between turns.
    var conversationFoundationModels: [LabTurn] = []
    var conversationNative: [LabTurn] = []
    var cases: [LabCaseResult] = []
    var toolAccuracy: Double = 0
    var argumentAccuracy: Double = 0
    var medianCaseSeconds: Double = 0
    var minimumAvailableMB: Int = 0
    var peakFootprintMB: Int = 0
    var mlxPeakMB: Int = 0
    var error: String?
}

// MARK: - Memory

/// Samples the process every 100 ms: the least memory iOS would still let the
/// app take, and the most it held.
nonisolated final class LabMemorySampler: Sendable {
    private struct Extremes { var minimumAvailable = Int.max; var peakFootprint = 0 }
    private let extremes = Mutex(Extremes())
    private let task = Mutex<Task<Void, Never>?>(nil)

    func start() {
        let sampling = Task.detached(priority: .utility) { [self] in
            while !Task.isCancelled {
                let available = Int(os_proc_available_memory())
                let footprint = Self.footprint()
                extremes.withLock {
                    $0.minimumAvailable = min($0.minimumAvailable, available)
                    $0.peakFootprint = max($0.peakFootprint, footprint)
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        task.withLock { $0 = sampling }
    }

    func stop() -> (minimumAvailableMB: Int, peakFootprintMB: Int) {
        task.withLock { $0?.cancel() }
        return extremes.withLock {
            ($0.minimumAvailable == .max ? 0 : $0.minimumAvailable / 1_048_576, $0.peakFootprint / 1_048_576)
        }
    }

    static func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }
}

// MARK: - Runner

@MainActor
@Observable
final class AgentLabRunner {
    struct Row: Identifiable {
        let entry: RautaModelEntry
        var status = "Waiting"
        var progress: Double?
        var result: LabModelResult?
        var id: String { entry.id }
    }

    var rows: [Row]
    var lines: [String] = []
    var running = false

    private let clock = ContinuousClock()

    init() {
        let entries = AgentLab.only.flatMap(RautaModelCatalog.entry).map { [$0] } ?? RautaModelCatalog.candidates
        rows = entries.map { Row(entry: $0) }
    }

    func runAll() async {
        guard !running else { return }
        running = true
        ScreenAwake.set(true)
        defer {
            running = false
            ScreenAwake.set(false)
        }
        // The cache MLX keeps between steps is memory a phone does not have.
        Memory.cacheLimit = 64 * 1_048_576
        RautaModelFiles.removeUnlisted(keeping: RautaModelCatalog.candidates)
        say("start device=\(Self.deviceModel) memoryGB=\(Self.physicalMemoryGB)")
        // GPU work is refused once the app leaves the foreground, and MLX then
        // aborts; knowing when that happened explains a crash.
        let center = NotificationCenter.default
        let observers = [
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
                print("AGENTLAB lifecycle will-resign-active")
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                print("AGENTLAB lifecycle did-enter-background")
            },
        ]
        defer { observers.forEach(center.removeObserver) }
        for index in rows.indices {
            await run(index)
        }
        say("done")
    }

    private func run(_ index: Int) async {
        let entry = rows[index].entry
        var result = LabModelResult(
            model: entry.id, repo: entry.repo, revision: entry.revision,
            device: Self.deviceModel, system: UIDevice.current.systemVersion,
            physicalMemoryGB: Self.physicalMemoryGB
        )
        let sampler = LabMemorySampler()
        sampler.start()
        let model = RautaModelFiles.languageModel(entry)

        do {
            if !RautaModelFiles.isInstalled(entry) {
                rows[index].status = "Downloading"
                let started = clock.now
                _ = try await RautaHubDownloader().download(
                    id: entry.repo,
                    revision: entry.revision,
                    matching: RautaModelFiles.downloadPatterns,
                    useLatest: false
                ) { [weak self] progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in self?.rows[index].progress = fraction }
                }
                result.downloadSeconds = seconds(since: started)
                rows[index].progress = nil
                say("\(entry.id) downloaded in \(format(result.downloadSeconds))s")
            }

            rows[index].status = "Loading"
            let loadStarted = clock.now
            try await model.preload()
            result.loadSeconds = seconds(since: loadStarted)
            say("\(entry.id) loaded in \(format(result.loadSeconds))s")

            rows[index].status = "Measuring speed"
            let tokenizer = try await RautaTokenizerLoader().load(from: RautaModelFiles.snapshot(for: entry))
            result.chat = try await measureChat(model, tokenizer: tokenizer)
            say("\(entry.id) chat ttft=\(format(result.chat?.firstTokenSeconds))s tps=\(format(result.chat?.tokensPerSecond))")

            let log = LabToolLog()
            let tools: [any FoundationModels.Tool] = [
                LabScheduleTool(log: log), LabFindExerciseTool(log: log), LabSwapExerciseTool(log: log),
                LabRescheduleTool(log: log), LabProposePlanTool(log: log),
            ]
            rows[index].status = "Measuring prefill"
            result.prefill = try await measurePrefill(model, tools: tools, tokenizer: tokenizer)
            say("\(entry.id) prefill tokens=\(result.prefill?.promptTokens ?? 0) cold=\(format(result.prefill?.coldSeconds))s warm=\(format(result.prefill?.warmSeconds))s tps=\(format(result.prefill?.tokensPerSecond))")
            for (number, labCase) in LabCase.suite.enumerated() {
                rows[index].status = "Tools \(number + 1)/\(LabCase.suite.count)"
                let outcome = await runCase(labCase, model: model, tools: tools, log: log)
                result.cases.append(outcome)
                write(result)
                say("\(entry.id) case=\(labCase.id) tool=\(outcome.toolOK) args=\(outcome.argumentsOK) s=\(format(outcome.seconds)) firstTool=\(format(outcome.firstToolSeconds)) calls=\(outcome.calls.map(\.name)) \(outcome.error ?? "")")
            }
            let count = Double(result.cases.count)
            result.toolAccuracy = Double(result.cases.filter(\.toolOK).count) / count
            result.argumentAccuracy = Double(result.cases.filter(\.argumentsOK).count) / count
            let times = result.cases.map(\.seconds).sorted()
            result.medianCaseSeconds = times[times.count / 2]

            rows[index].status = "Conversation, FoundationModels"
            result.conversationFoundationModels = await LabConversation.runFoundationModels(
                model, tools: tools, log: log
            )
            say("\(entry.id) conversation fm turns=\(result.conversationFoundationModels.map { format($0.seconds) }) calls=\(result.conversationFoundationModels.map { $0.calls.map(\.name) })")
            rows[index].status = "Conversation, native"
            result.conversationNative = await LabConversation.runNative(
                model, entry: entry, tools: tools, log: log
            )
            say("\(entry.id) conversation native turns=\(result.conversationNative.map { format($0.seconds) }) calls=\(result.conversationNative.map { $0.calls.map(\.name) }) \(result.conversationNative.compactMap(\.error).first ?? "")")

            rows[index].status = "Cancelling"
            result.cancelSeconds = await measureCancel(model)
        } catch {
            result.error = String(describing: error)
            say("\(entry.id) error \(error)")
        }

        result.mlxPeakMB = Memory.peakMemory / 1_048_576
        await model.evict()
        Memory.clearCache()
        let memory = sampler.stop()
        result.minimumAvailableMB = memory.minimumAvailableMB
        result.peakFootprintMB = memory.peakFootprintMB

        rows[index].result = result
        rows[index].status = result.error == nil ? "Done" : "Failed"
        write(result)
        say("\(entry.id) summary tool=\(format(result.toolAccuracy)) args=\(format(result.argumentAccuracy)) load=\(format(result.loadSeconds))s peakMB=\(result.peakFootprintMB) minAvailMB=\(result.minimumAvailableMB) cancel=\(format(result.cancelSeconds))s")
    }

    private func measureChat(
        _ model: MLXLanguageModel,
        tokenizer: any MLXLMCommon.Tokenizer
    ) async throws -> LabChatMetrics {
        let session = LanguageModelSession(model: model, instructions: "You are RAUTA, a friendly strength coach. Be concise.")
        let started = clock.now
        var first: Double?
        var text = ""
        let stream = session.streamResponse(
            to: "Explain progressive overload to a beginner in four sentences.",
            options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 220)
        )
        for try await snapshot in stream {
            text = snapshot.content
            if first == nil, !text.isEmpty { first = seconds(since: started) }
        }
        let total = seconds(since: started)
        let tokens = tokenizer.encode(text: text, addSpecialTokens: false).count
        let firstToken = first ?? total
        let generating = max(total - firstToken, 0.001)
        return LabChatMetrics(
            firstTokenSeconds: firstToken,
            totalSeconds: total,
            outputTokens: tokens,
            tokensPerSecond: Double(max(tokens - 1, 0)) / generating,
            text: text
        )
    }

    /// Time to the first token of a turn that carries the full instructions and
    /// tool definitions, which is what every agent turn pays before it can act.
    private func measurePrefill(
        _ model: MLXLanguageModel,
        tools: [any FoundationModels.Tool],
        tokenizer: any MLXLMCommon.Tokenizer
    ) async throws -> LabPrefillMetrics {
        func firstToken() async throws -> Double {
            let session = LanguageModelSession(model: model, tools: tools, instructions: LabFixtures.instructions)
            let started = clock.now
            let stream = session.streamResponse(
                to: "Reply with the single word OK.",
                options: GenerationOptions(temperature: 0, maximumResponseTokens: 4)
            )
            for try await snapshot in stream where !snapshot.content.isEmpty {
                return seconds(since: started)
            }
            return seconds(since: started)
        }
        let schemas = tools.map { tool -> String in
            let parameters = (try? JSONEncoder().encode(tool.parameters)).map { String(decoding: $0, as: UTF8.self) } ?? ""
            return "\(tool.name) \(tool.description) \(parameters)"
        }
        let promptTokens = tokenizer.encode(
            text: ([LabFixtures.instructions] + schemas).joined(separator: "\n"), addSpecialTokens: true
        ).count
        let cold = try await firstToken()
        let warm = try await firstToken()
        return LabPrefillMetrics(
            promptTokens: promptTokens,
            coldSeconds: cold,
            warmSeconds: warm,
            tokensPerSecond: Double(promptTokens) / max(warm, 0.001)
        )
    }

    private func runCase(
        _ labCase: LabCase,
        model: MLXLanguageModel,
        tools: [any FoundationModels.Tool],
        log: LabToolLog
    ) async -> LabCaseResult {
        _ = await log.reset()
        let session = LanguageModelSession(model: model, tools: tools, instructions: LabFixtures.instructions)
        let started = clock.now
        var reply = ""
        var failure: String?
        do {
            let response = try await session.respond(
                to: labCase.prompt,
                options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 300)
            )
            reply = response.content
        } catch {
            failure = String(describing: error)
        }
        let elapsed = seconds(since: started)
        let recorded = await log.reset()
        let score = labCase.score(recorded.calls)
        let firstTool = recorded.firstAt.map { at -> Double in
            let duration = at - started
            return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        }
        return LabCaseResult(
            id: labCase.id, prompt: labCase.prompt,
            toolOK: score.tool, argumentsOK: score.arguments,
            calls: recorded.calls, reply: reply, seconds: elapsed,
            firstToolSeconds: firstTool, error: failure
        )
    }

    /// How long generation takes to stop once it is cancelled mid-answer.
    private func measureCancel(_ model: MLXLanguageModel) async -> Double? {
        let session = LanguageModelSession(model: model)
        let generating = Task {
            let stream = session.streamResponse(
                to: "Write a detailed 800-word guide to training for a first powerlifting meet.",
                options: GenerationOptions(maximumResponseTokens: 1200)
            )
            do { for try await _ in stream {} } catch {}
        }
        try? await Task.sleep(for: .seconds(2))
        let cancelled = clock.now
        generating.cancel()
        await generating.value
        return seconds(since: cancelled)
    }

    // MARK: Output

    private func write(_ result: LabModelResult) {
        let folder = URL.documentsDirectory.appending(path: "agent-lab", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(result) else { return }
        try? data.write(to: folder.appending(path: "\(result.model).json"), options: .atomic)
    }

    private func say(_ line: String) {
        print("AGENTLAB \(line)")
        lines.append(line)
    }

    private func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = clock.now - start
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private func format(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "-"
    }

    private static var deviceModel: String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static var physicalMemoryGB: Double {
        (Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 * 10).rounded() / 10
    }
}

// MARK: - Screen

struct AgentLabScreen: View {
    @State private var runner = AgentLabRunner()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(runner.rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.entry.name).font(.headline)
                                Spacer()
                                Text(row.status).font(.subheadline).foregroundStyle(.secondary)
                            }
                            if let progress = row.progress {
                                ProgressView(value: progress)
                            }
                            if let result = row.result {
                                Text(summary(result))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Log") {
                    ForEach(Array(runner.lines.suffix(80).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption2.monospaced())
                    }
                }
            }
            .navigationTitle("Agent Lab")
            .toolbar {
                Button(runner.running ? "Running…" : "Run all") {
                    Task { await runner.runAll() }
                }
                .disabled(runner.running)
            }
        }
        .task {
            if AgentLab.autorun { await runner.runAll() }
        }
    }

    private func summary(_ result: LabModelResult) -> String {
        if let error = result.error { return "error: \(error)" }
        let chat = result.chat.map { String(format: "ttft %.2fs · %.1f tok/s", $0.firstTokenSeconds, $0.tokensPerSecond) } ?? ""
        return String(
            format: "tools %.0f%% · args %.0f%% · load %.1fs · %@ · peak %d MB",
            result.toolAccuracy * 100, result.argumentAccuracy * 100, result.loadSeconds ?? 0,
            chat, result.peakFootprintMB
        )
    }
}
#endif
