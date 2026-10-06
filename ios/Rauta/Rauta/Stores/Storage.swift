import Foundation
import os

/// Where a persisted store keeps its state.
///
/// The web app used `localStorage` with a `{ state, version }` envelope under a
/// `gym-lib-*` key, and the iCloud backup is written in those same terms, so the
/// shape is kept exactly: a backup taken on either side restores on the other.
enum Storage {
    /// The standard defaults; tests point this at a suite of their own.
    static var defaults = UserDefaults.standard

    nonisolated private static let log = Logger(subsystem: "com.hirchyts.gymlib", category: "persistence")

    /// `try?` that leaves a trace: for a step whose failure the caller has
    /// chosen to carry on past, but which should never fail unseen.
    @discardableResult
    nonisolated static func attempt<T>(_ step: String, _ body: () throws -> T) -> T? {
        do {
            return try body()
        } catch {
            report(step, error)
            return nil
        }
    }

    /// Leaves a trace of a step that failed and was carried on past.
    nonisolated static func report(_ step: String, _ error: any Error) {
        let message = (error as? TrainingPersistenceError)?.message ?? error.localizedDescription
        log.error("\(step, privacy: .public) failed: \(message, privacy: .public)")
    }

    static func readEnvelope(_ key: String) -> (state: JSONValue, version: Int)? {
        guard let text = defaults.string(forKey: key),
              let parsed = JSONCoding.parse(text),
              let object = parsed.objectValue
        else { return nil }
        return (state: object["state"] ?? .null, version: version(object["version"]))
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

    /// A stored envelope's version. The number comes from a file anyone could
    /// have written, so one that is not a whole number in range reads as no
    /// version at all rather than trapping on the conversion.
    nonisolated static func version(_ value: JSONValue?) -> Int {
        value?.intValue ?? -1
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
        if attempt("Moving \(name) out of user defaults", { try write(Data(text.utf8), to: url) }) != nil {
            defaults.removeObject(forKey: key)
        }
        return migrated
    }

    /// Written atomically before returning, and throws when it is not: callers
    /// rely on a commit being on disk before they take their next step, so a
    /// write that failed must not look like one that landed.
    static func writeEnvelopeFile(_ name: String, state: JSONValue, version: Int) throws {
        let envelope = JSONValue.object([
            "state": state,
            "version": .number(Double(version)),
        ])
        try write(Data(envelope.canonical.utf8), to: fileURL(name))
    }

    /// Removes a stored file. One that was never written is already gone.
    static func removeFile(_ name: String) {
        let url = fileURL(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        attempt("Removing \(name)") { try FileManager.default.removeItem(at: url) }
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
        return (state: object["state"] ?? .null, version: version(object["version"]))
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
