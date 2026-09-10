import Foundation

/// A compiled pattern with JavaScript's `\b` semantics, cached because the
/// classification rules run over the whole catalogue.
struct Pattern {
    private let regex: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = false) {
        // Every rule pattern in the engine is authored against lower-cased text,
        // so the flag only matters for the two that were written with `/i`.
        regex = try! NSRegularExpression(
            pattern: pattern,
            options: caseInsensitive ? [.caseInsensitive] : []
        )
    }

    func test(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
