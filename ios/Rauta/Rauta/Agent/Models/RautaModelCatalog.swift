import Foundation
import MLXLMCommon

/// The language models RAUTA can think with, each pinned to one exact upload.
///
/// A model is chosen from this list, never from an arbitrary repository: each
/// entry has been checked to load in MLX and to call tools in the format it
/// names. Revisions are commit hashes so an upstream change can never swap the
/// weights under a model somebody already downloaded.
nonisolated struct RautaModelEntry: Identifiable, Hashable, Sendable {
    /// Short, stable key used in settings and results.
    let id: String
    let name: String
    let repo: String
    let revision: String
    /// What the download adds up to, for the size shown before downloading.
    let downloadBytes: Int64
    let license: String
    let toolCallFormat: ToolCallFormat?
    let extraEOSTokens: Set<String>

    var configuration: ModelConfiguration {
        ModelConfiguration(
            id: repo,
            revision: revision,
            extraEOSTokens: extraEOSTokens,
            toolCallFormat: toolCallFormat
        )
    }
}

nonisolated enum RautaModelCatalog {
    static let qwen35_2b = RautaModelEntry(
        id: "qwen3.5-2b",
        name: "Qwen3.5 2B",
        repo: "mlx-community/Qwen3.5-2B-4bit",
        revision: "674aaa7240b91e8012fcad5d791b7dfe5ba90207",
        downloadBytes: 1_749_000_000,
        license: "Apache-2.0",
        toolCallFormat: .qwen35,
        extraEOSTokens: ["<|im_end|>"]
    )

    static let lfm25_2_6b = RautaModelEntry(
        id: "lfm2.5-2.6b",
        name: "LFM2.5 2.6B",
        // Liquid's own conversion: the mlx-community one wraps the weights in a
        // vision-model layout the text loader cannot read.
        repo: "LiquidAI/LFM2.5-2.6B-MLX-4bit",
        revision: "04efa23776ce61ec34ec95ec34c859854c89542b",
        downloadBytes: 1_601_000_000,
        license: "LFM Open License v1.0",
        toolCallFormat: .lfm2,
        extraEOSTokens: []
    )

    static let qwen35_0_8b = RautaModelEntry(
        id: "qwen3.5-0.8b",
        name: "Qwen3.5 0.8B",
        repo: "mlx-community/Qwen3.5-0.8B-4bit",
        revision: "da28692b5f139cb0ec58a356b437486b7dac7462",
        downloadBytes: 652_000_000,
        license: "Apache-2.0",
        toolCallFormat: .qwen35,
        extraEOSTokens: ["<|im_end|>"]
    )

    /// What RAUTA offers. Chosen on an iPhone 14 Pro Max in the Agent Lab (see
    /// docs/research/agent-model-spike-2026-09-26.md): the others either picked
    /// the wrong tool too often or were slower at the same size.
    static let all: [RautaModelEntry] = [qwen35_2b]

    /// Everything the Agent Lab can measure, shipped or not.
    static let candidates: [RautaModelEntry] = [qwen35_2b, lfm25_2_6b, qwen35_0_8b]

    static func entry(_ id: String) -> RautaModelEntry? { candidates.first { $0.id == id } }
}
