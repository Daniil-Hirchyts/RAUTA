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
        if downloading { return progress < 1 ? "Downloading \(Int(progress * 100))%" : "Getting ready…" }
        if let error { return error }
        #if targetEnvironment(simulator)
        return installed ? "Ready" : "Apple's local model is unavailable in this simulator"
        #else
        return installed ? "Ready" : "Download RAUTA's brain"
        #endif
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
            error = "Free at least 2.3 GB of storage before downloading."
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
                self.error = error.localizedDescription
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

    func cancelDownload() { task?.cancel(); task = nil; downloading = false }
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
