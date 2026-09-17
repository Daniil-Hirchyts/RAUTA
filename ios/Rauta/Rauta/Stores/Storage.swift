import Foundation

/// Where a persisted store keeps its state.
///
/// The web app used `localStorage` with a `{ state, version }` envelope under a
/// `gym-lib-*` key, and the iCloud backup is written in those same terms, so the
/// shape is kept exactly: a backup taken on either side restores on the other.
enum Storage {
    /// The standard defaults; tests point this at a suite of their own.
    static var defaults = UserDefaults.standard

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

    // MARK: Files

    /// Large state — the training history grows with every set — is kept in a
    /// file of its own rather than in user defaults, which are meant for small
    /// values and are rewritten as one property list whenever any of them
    /// changes. The envelope is the same `{ state, version }` shape.
    static func readEnvelopeFile(_ name: String, migratingKey key: String) -> (state: JSONValue, version: Int)? {
        let url = fileURL(name)
        if let data = try? Data(contentsOf: url) {
            return envelope(from: String(decoding: data, as: UTF8.self))
        }
        // First launch on this build: move the value out of user defaults,
        // letting it go only once the file holds it.
        guard let text = defaults.string(forKey: key), let migrated = envelope(from: text) else { return nil }
        if (try? write(Data(text.utf8), to: url)) != nil { defaults.removeObject(forKey: key) }
        return migrated
    }

    /// Written atomically before returning: callers rely on a commit being on
    /// disk before they take their next step.
    static func writeEnvelopeFile(_ name: String, state: JSONValue, version: Int) {
        let envelope = JSONValue.object([
            "state": state,
            "version": .number(Double(version)),
        ])
        try? write(Data(envelope.canonical.utf8), to: fileURL(name))
    }

    static func removeFile(_ name: String) {
        try? FileManager.default.removeItem(at: fileURL(name))
    }

    /// Application Support, where app-created data belongs; overridable so
    /// tests do not touch the app's own files.
    static var directory: URL {
        directoryOverride ?? URL.applicationSupportDirectory.appending(path: "Stores", directoryHint: .isDirectory)
    }
    static var directoryOverride: URL?

    static func fileURL(_ name: String) -> URL {
        directory.appending(path: "\(name).json", directoryHint: .notDirectory)
    }

    private static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private static func envelope(from text: String) -> (state: JSONValue, version: Int)? {
        guard let parsed = JSONCoding.parse(text), let object = parsed.objectValue else { return nil }
        let version = Int(object["version"]?.numberValue ?? -1)
        return (state: object["state"] ?? .null, version: version)
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
