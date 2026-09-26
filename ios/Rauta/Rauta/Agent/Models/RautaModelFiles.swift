import Foundation
import FoundationModels
import HuggingFace
import MLXFoundationModels
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Where downloaded models live, and how one becomes a `LanguageModel`.
///
/// Weights are kept in Application Support rather than the Hugging Face default
/// under Documents: they are gigabytes the app can download again, so they are
/// excluded from device backups and never mixed with anything a person made.
nonisolated enum RautaModelFiles {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var url = base.appending(path: "Models", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    static var cache: HubCache { HubCache(cacheDirectory: directory) }

    /// The files MLX reads: weights, configuration, tokenizer and chat template.
    static let downloadPatterns = ["*.safetensors", "*.json", "*.jinja"]

    /// The folder holding this entry's pinned revision, whether or not it has
    /// been downloaded yet.
    static func snapshot(for entry: RautaModelEntry) -> URL {
        let cache = cache
        guard let repo = Repo.ID(rawValue: entry.repo) else { return cache.cacheDirectory }
        return (try? cache.snapshotPath(repo: repo, kind: .model, commitHash: entry.revision))
            ?? cache.repoDirectory(repo: repo, kind: .model)
    }

    static func isInstalled(_ entry: RautaModelEntry) -> Bool {
        isComplete(snapshot(for: entry))
    }

    /// Whether a snapshot folder holds what MLX loads: configuration,
    /// tokenizer, and weights that are more than a stub.
    ///
    /// A snapshot's files are symlinks into the cache's blobs, so a size is read
    /// from the file a link points at — the link itself is a few bytes, and
    /// reading that made every finished download look incomplete.
    static func isComplete(_ folder: URL) -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: folder.appending(path: "config.json").path(percentEncoded: false)),
              manager.fileExists(atPath: folder.appending(path: "tokenizer.json").path(percentEncoded: false)),
              let files = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return false }
        return files.contains { file in
            guard file.pathExtension == "safetensors" else { return false }
            let target = file.resolvingSymlinksInPath().path(percentEncoded: false)
            let size = (try? manager.attributesOfItem(atPath: target)[.size] as? NSNumber)?.int64Value ?? 0
            return size > 1_000_000
        }
    }

    /// Removes a model's files. Conversations are kept elsewhere and stay.
    static func remove(_ entry: RautaModelEntry) throws {
        guard let repo = Repo.ID(rawValue: entry.repo) else { return }
        let folder = cache.repoDirectory(repo: repo, kind: .model)
        if FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    /// Removes downloaded models that are no longer in the catalogue, such as an
    /// upload that has since been replaced by a better one.
    static func removeUnlisted(keeping kept: [RautaModelEntry] = RautaModelCatalog.all) {
        let listed = Set(kept.compactMap { entry in
            Repo.ID(rawValue: entry.repo).map { cache.repoDirectory(repo: $0, kind: .model).lastPathComponent }
        })
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        for folder in folders where folder.lastPathComponent.hasPrefix("models--")
            && !listed.contains(folder.lastPathComponent) {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// A `LanguageModel` for `LanguageModelSession`, downloading on first load.
    @available(iOS 27.0, *)
    static func languageModel(
        _ entry: RautaModelEntry,
        capabilities: [LanguageModelCapabilities.Capability] = [.toolCalling, .guidedGeneration]
    ) -> MLXLanguageModel {
        MLXLanguageModel(
            configuration: entry.configuration,
            capabilities: capabilities,
            weightsLocation: { _ in snapshot(for: entry) },
            load: { configuration, progressHandler in
                try await loadModelContainer(
                    from: RautaHubDownloader(),
                    using: RautaTokenizerLoader(),
                    configuration: configuration,
                    progressHandler: progressHandler
                )
            }
        )
    }
}

/// Downloads a pinned model snapshot into ``RautaModelFiles/directory``.
nonisolated struct RautaHubDownloader: MLXLMCommon.Downloader {
    private let client = HubClient(
        host: HubClient.defaultHost, bearerToken: nil, cache: RautaModelFiles.cache
    )

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let repo = Repo.ID(rawValue: id) else {
            throw RautaModelError.invalidRepository(id)
        }
        return try await client.downloadSnapshot(
            of: repo,
            revision: revision ?? "main",
            matching: patterns,
            progressHandler: { @MainActor progress in progressHandler(progress) }
        )
    }
}

/// Loads a model folder's tokenizer and chat template with swift-transformers.
nonisolated struct RautaTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        RautaTokenizer(try await AutoTokenizer.from(modelFolder: directory))
    }
}

nonisolated struct RautaTokenizer: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages, tools: tools, additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

nonisolated enum RautaModelError: LocalizedError {
    case invalidRepository(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepository(let id): "\(id) is not a model repository."
        }
    }
}
