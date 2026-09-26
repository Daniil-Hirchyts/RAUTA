import Foundation

/// The model's own words, made fit to show as RAUTA's.
///
/// A small model writes markdown the bubble can't render, leaks its reasoning
/// and tool-call syntax, and — when it didn't call a tool — explains that it
/// "can't access tools". None of that may reach the person: markdown becomes
/// plain text, the machinery is cut, and a reply about its own limits is
/// dropped so the agent can act or ask instead.
nonisolated enum AgentReply {
    /// What RAUTA says when it could not place a request at all.
    static let fallback = "I didn't catch what to change. Try naming the workout or exercise, like “Move Thursday's workout to Friday” or “Build a leg workout for tomorrow”."

    static let maximumLength = 420

    /// `raw` as plain text, or nil when nothing fit to show is left.
    static func clean(_ raw: String) -> String? {
        var text = raw
        // Reasoning and tool-call syntax.
        text = text.replacing(#/<think>[\s\S]*?</think>/#, with: "")
        if let open = text.range(of: "<think>") { text = String(text[..<open.lowerBound]) }
        text = text.replacing(#/<tool_call>[\s\S]*?</tool_call>/#, with: "")
        text = text.replacing(#/</?(tool_call|tool_response|function|functions)[^>]*>/#, with: "")
        text = text.replacing(#/```[\s\S]*?```/#, with: "")

        // Markdown, line by line: headings lose their marks, list items become
        // bullets, tables and rules go.
        var lines: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("|") || line.wholeMatch(of: #/[-*_=]{3,}/#) != nil { continue }
            line = line.replacing(#/^#{1,6}\s*/#, with: "")
            if line.firstMatch(of: #/^([-*+•]|\d+[.)])\s+/#) != nil {
                line = "• " + line.replacing(#/^([-*+•]|\d+[.)])\s+/#, with: "")
            }
            lines.append(line)
        }
        text = lines.joined(separator: "\n")
        // Inline marks: links keep their text; bold, italics and code lose their marks.
        text = text.replacing(#/\[([^\]]+)\]\([^)]*\)/#) { String($0.1) }
        text = text.replacing(#/(\*\*|__)(.+?)\1/#) { String($0.2) }
        text = text.replacing(#/(^|[^\w*])[*_](\S(?:.*?\S)?)[*_](?![\w*])/#) { String($0.1) + String($0.2) }
        text = text.replacing("`", with: "")
        text = text.replacing(#/\n{3,}/#, with: "\n\n")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty, !talksAboutItself(text) else { return nil }
        return clipped(text)
    }

    /// A reply about the model rather than the training: tools, functions,
    /// access, being an AI. Never true of RAUTA, and never useful.
    static func talksAboutItself(_ text: String) -> Bool {
        let lower = text.lowercased()
        let words = Set(AgentWords.words(lower))
        if !words.isDisjoint(with: ["tool", "tools", "function", "functions", "api", "json"]) { return true }
        return [
            "access to your", "access your", "can't access", "cannot access", "unable to access",
            "don't have access", "do not have access", "as an ai", "language model", "i'm an ai",
            "i am an ai", "i can't directly", "i cannot directly", "i'm not able to", "i am not able to",
            "i don't have the ability", "i do not have the ability",
        ].contains(where: lower.contains)
    }

    /// At most ``maximumLength`` characters, ending on a whole sentence when
    /// one fits.
    private static func clipped(_ text: String) -> String {
        guard text.count > maximumLength else { return text }
        let head = String(text.prefix(maximumLength))
        if let end = head.lastIndex(where: { ".!?".contains($0) }), head.distance(from: head.startIndex, to: end) > 80 {
            return String(head[...end])
        }
        return head.trimmingCharacters(in: .whitespaces) + "…"
    }
}
