import Foundation
import FoundationModels
import MLXFoundationModels
import MLX
import Observation

@MainActor @Observable
final class AgentModelStore {
    static let shared = AgentModelStore()

    private(set) var downloading = false
    private(set) var progress: Double = 0
    private(set) var error: String?
    private var loaded: MLXLanguageModel?
    private var task: Task<Void, Never>?

    /// Whether RAUTA has a model to think with. Kept, not computed: views read
    /// it on every redraw, and answering it means scanning the model folder on
    /// an iPhone or asking the system model on the simulator. It changes only
    /// on download, removal, or when the app comes back (see ``refresh()``).
    private(set) var installed = false

    private init() { refresh() }

    /// Checks again whether the model is there.
    func refresh() {
        #if targetEnvironment(simulator)
        let available = SystemLanguageModel.default.availability == .available
        #else
        let available = RautaModelFiles.isInstalled(RautaModelCatalog.qwen35_2b)
        #endif
        if available != installed { installed = available }
    }

    var status: String {
        if downloading {
            guard progress < 1 else { return "Getting ready…" }
            return "Downloading \(Int(progress * 100))% · \(Self.gigabytes(downloadedBytes)) of \(Self.gigabytes(entry.downloadBytes))"
        }
        if let error { return error }
        #if targetEnvironment(simulator)
        return installed ? "Ready" : "Apple's on-device model isn't available on this Mac"
        #else
        return installed ? "Ready · works offline" : "Not set up"
        #endif
    }

    /// The model RAUTA downloads.
    var entry: RautaModelEntry { RautaModelCatalog.qwen35_2b }

    var downloadedBytes: Int64 { Int64(Double(entry.downloadBytes) * min(1, max(0, progress))) }

    /// "1.75 GB".
    static func gigabytes(_ bytes: Int64) -> String {
        let value = Double(bytes) / 1_000_000_000
        return value.formatted(.number.precision(.fractionLength(2))) + " GB"
    }

    /// Memory the model was tested to run in: an iPhone 14 Pro Max, 6 GB.
    static let testedMemoryBytes: UInt64 = 6_000_000_000

    /// Whether this device has the memory the model was tested with. A little
    /// under counts: iPhones report slightly less than their nominal memory.
    var meetsMemoryRequirement: Bool {
        ProcessInfo.processInfo.physicalMemory >= UInt64(Double(Self.testedMemoryBytes) * 0.9)
    }

    /// A failure in words a person can act on.
    static func describe(_ error: Error) -> String? {
        if error is CancellationError { return nil }
        if let url = error as? URLError {
            switch url.code {
            case .cancelled: return nil
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "The download stopped: no internet connection. Connect and try again."
            case .timedOut, .cannotConnectToHost, .cannotFindHost:
                return "The download server didn't answer. Try again in a moment."
            default:
                return "The download didn't finish. Try again."
            }
        }
        if let local = error as? LocalizedError, let text = local.errorDescription { return text }
        return "The download didn't finish. Try again."
    }

    func model() -> MLXLanguageModel? {
        guard RautaModelFiles.isInstalled(RautaModelCatalog.qwen35_2b) else { return nil }
        if let loaded { return loaded }
        let next = RautaModelFiles.languageModel(RautaModelCatalog.qwen35_2b)
        loaded = next
        return next
    }

    func download() {
        guard !downloading else { return }
        #if targetEnvironment(simulator)
        error = "Model downloads are available on iPhone."
        #else
        start(RautaModelCatalog.qwen35_2b)
        #endif
    }

    private func start(_ entry: RautaModelEntry) {
        let free = (try? FileManager.default.attributesOfFileSystem(
            forPath: RautaModelFiles.directory.path(percentEncoded: false))[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        guard free >= entry.downloadBytes + 500_000_000 else {
            error = "Free at least \(Self.gigabytes(entry.downloadBytes + 500_000_000)) of storage, then try again."
            return
        }
        error = nil
        progress = 0
        downloading = true
        task = Task { @MainActor in
            do {
                _ = try await RautaHubDownloader().download(
                    id: entry.repo, revision: entry.revision,
                    matching: RautaModelFiles.downloadPatterns, useLatest: false,
                    progressHandler: { progress in
                        let fraction = progress.fractionCompleted
                        Task { @MainActor in AgentModelStore.shared.progress = fraction }
                    }
                )
                guard !Task.isCancelled else { downloading = false; return }
                guard RautaModelFiles.isInstalled(entry) else {
                    throw AgentModelStoreError.incomplete
                }
                progress = 1
                refresh()
                // One real tool turn now, so the first question a person asks
                // does not pay for the GPU warming up.
                if let model = model() {
                    _ = try? await Self.respond(
                        model: model, tools: [AgentWarmupTool()], instructions: "Call ready once.",
                        prompt: "Get ready", maximumTokens: 16
                    )
                }
                downloading = false
            } catch {
                self.error = Self.describe(error)
                downloading = false
            }
        }
    }

    /// One turn with the local model, off the main actor. A GPU failure comes
    /// back as a Swift error instead of aborting the app.
    @concurrent
    static func respond(
        model: MLXLanguageModel,
        tools: [any Tool],
        instructions: String,
        prompt: String,
        maximumTokens: Int,
        temperature: Double = 0.2
    ) async throws -> String {
        let session = LanguageModelSession(model: model, tools: tools, instructions: instructions)
        return try await MLX.withError {
            try await session.respond(
                to: prompt,
                options: GenerationOptions(temperature: temperature, maximumResponseTokens: maximumTokens)
            ).content
        }
    }

    /// Stops a download. Nothing is half-installed: the model counts as there
    /// only once every file it needs is complete.
    func cancelDownload() {
        task?.cancel()
        task = nil
        downloading = false
        progress = 0
        error = nil
    }
    /// Frees the weights. Dropping the reference is not enough: MLX keeps
    /// loaded models in a process-wide cache until they are evicted from it.
    func evict() {
        guard let model = loaded else { return }
        loaded = nil
        Task { await model.evict() }
    }
    func delete() throws {
        cancelDownload()
        evict()
        try RautaModelFiles.remove(RautaModelCatalog.qwen35_2b)
        progress = 0
        error = nil
        refresh()
    }
}

private nonisolated struct AgentWarmupTool: Tool {
    let name = "ready"
    let description = "Confirm local tool calling is ready."
    @Generable nonisolated struct Arguments {}
    @concurrent func call(arguments: Arguments) async throws -> String { "Ready" }
}

private enum AgentModelStoreError: LocalizedError {
    case incomplete
    var errorDescription: String? { "The model download is incomplete. Try again." }
}
