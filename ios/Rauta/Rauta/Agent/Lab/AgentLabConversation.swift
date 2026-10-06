#if DEBUG
import Foundation
import FoundationModels
import MLXFoundationModels
import MLXLMCommon

/// One turn of the lab's short conversation, as either session saw it.
nonisolated struct LabTurn: Codable, Sendable {
    var prompt: String
    var seconds: Double
    var calls: [LabToolCall]
    var reply: String
    var error: String?
}

/// Runs FoundationModels tools through MLX's own `ChatSession`, which keeps the
/// conversation's KV cache between turns. The tools stay the same `Tool`
/// values: their schemas are handed over as JSON, and each call's arguments
/// come back through `GeneratedContent(json:)` into the tool's own type.
nonisolated enum NativeToolBridge {
    static func specs(_ tools: [any FoundationModels.Tool]) throws -> [ToolSpec] {
        try tools.map { tool in
            let data = try JSONEncoder().encode(tool.parameters)
            guard let parameters = try JSONSerialization.jsonObject(with: data) as? [String: any Sendable]
            else { throw NativeToolBridgeError.invalidSchema(tool.name) }
            return [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": parameters,
                ] as [String: any Sendable],
            ]
        }
    }

    static func dispatcher(_ tools: [any FoundationModels.Tool]) -> @Sendable (ToolCall) async throws -> String {
        { call in
            guard let tool = tools.first(where: { $0.name == call.function.name }) else {
                return "There is no tool called \(call.function.name)."
            }
            let json = String(decoding: try JSONEncoder().encode(call.function.arguments), as: UTF8.self)
            return try await invoke(tool, json: json)
        }
    }

    private static func invoke<T: FoundationModels.Tool>(_ tool: T, json: String) async throws -> String {
        let arguments = try T.Arguments(GeneratedContent(json: json))
        return String(describing: try await tool.call(arguments: arguments))
    }
}

nonisolated enum NativeToolBridgeError: Error {
    case invalidSchema(String)
}

nonisolated enum LabConversation {
    static let turns = [
        "What's on my plan this week?",
        "Swap the bench press on Monday for something with dumbbells",
        "And move Wednesday's workout to Thursday",
        "Actually I only have 40 minutes per session now, rebuild the week",
        "Thanks!",
    ]

    /// The whole conversation in one FoundationModels session.
    static func runFoundationModels(
        _ model: MLXLanguageModel,
        tools: [any FoundationModels.Tool],
        log: LabToolLog
    ) async -> [LabTurn] {
        let session = LanguageModelSession(model: model, tools: tools, instructions: LabFixtures.instructions)
        var result: [LabTurn] = []
        for prompt in turns {
            _ = await log.reset()
            let started = ContinuousClock.now
            var reply = ""
            var failure: String?
            do {
                reply = try await session.respond(
                    to: prompt, options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 300)
                ).content
            } catch {
                failure = String(describing: error)
            }
            result.append(LabTurn(
                prompt: prompt, seconds: seconds(since: started),
                calls: await log.reset().calls, reply: reply, error: failure
            ))
        }
        return result
    }

    /// The same conversation in one MLX `ChatSession`.
    static func runNative(
        _ model: MLXLanguageModel,
        entry: RautaModelEntry,
        tools: [any FoundationModels.Tool],
        log: LabToolLog
    ) async -> [LabTurn] {
        var result: [LabTurn] = []
        do {
            let container = try await model.loadContainer()
            let session = ChatSession(
                container,
                instructions: LabFixtures.instructions,
                generateParameters: GenerateParameters(maxTokens: 300, temperature: 0.2),
                // Qwen thinks aloud unless told not to; the adapter does the same.
                additionalContext: entry.toolCallFormat == .qwen35 ? ["enable_thinking": false] : nil,
                tools: try NativeToolBridge.specs(tools),
                toolDispatch: NativeToolBridge.dispatcher(tools)
            )
            for prompt in turns {
                _ = await log.reset()
                let started = ContinuousClock.now
                var reply = ""
                var failure: String?
                do {
                    reply = try await session.respond(to: prompt)
                } catch {
                    failure = String(describing: error)
                }
                result.append(LabTurn(
                    prompt: prompt, seconds: seconds(since: started),
                    calls: await log.reset().calls, reply: reply, error: failure
                ))
            }
        } catch {
            result.append(LabTurn(prompt: "(setup)", seconds: 0, calls: [], reply: "", error: String(describing: error)))
        }
        return result
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = ContinuousClock.now - start
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
#endif
