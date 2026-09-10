import Foundation

/// Where a persisted store keeps its state.
///
/// The web app used `localStorage` with a `{ state, version }` envelope under a
/// `gym-lib-*` key, and the iCloud backup is written in those same terms, so the
/// shape is kept exactly: a backup taken on either side restores on the other.
enum Storage {
    private static let defaults = UserDefaults.standard

    static func readEnvelope(_ key: String) -> (state: JSONValue, version: Int)? {
        guard let text = defaults.string(forKey: key),
              let parsed = JSONCoding.parse(text),
              let object = parsed.objectValue
        else { return nil }
        let version = Int(object["version"]?.numberValue ?? -1)
        return (state: object["state"] ?? .null, version: version)
    }

    static func writeEnvelope(_ key: String, state: JSONValue, version: Int) {
        let envelope = JSONValue.object([
            "state": state,
            "version": .number(Double(version)),
        ])
        defaults.set(envelope.canonical, forKey: key)
    }

    static func remove(_ key: String) {
        defaults.removeObject(forKey: key)
    }

    static func readString(_ key: String) -> String? { defaults.string(forKey: key) }
    static func writeString(_ key: String, _ value: String) { defaults.set(value, forKey: key) }
}

/// Sanitisation helpers shared by every store that reads back stored state.
enum Sanitize {
    static func uniqueStrings(_ value: JSONValue?, isValid: (String) -> Bool) -> [String] {
        guard let items = value?.arrayValue else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            guard let text = item.stringValue, isValid(text), !seen.contains(text) else { continue }
            seen.insert(text)
            result.append(text)
        }
        return result
    }

    static func string(_ value: JSONValue?, fallback: String = "") -> String {
        value?.stringValue ?? fallback
    }

    static func toggle<T: Equatable>(_ values: [T], _ value: T) -> [T] {
        values.contains(value) ? values.filter { $0 != value } : values + [value]
    }
}
