import Foundation
import Synchronization

nonisolated let DAY_MS: Double = 86_400_000

nonisolated enum Num {
    static func clamp(_ n: Double, _ min: Double = 0, _ max: Double = 1) -> Double {
        Swift.min(max, Swift.max(min, n))
    }

    static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return (sorted[sorted.count / 2] + sorted[(sorted.count - 1) / 2]) / 2
    }

    /// Six-decimal rounding, the way the engine kept binary float noise out of
    /// values people read back.
    static func round6(_ n: Double) -> Double {
        guard n.isFinite else { return n }
        return (n * 1e6).rounded() / 1e6
    }

    static func isFinite(_ v: Double?, min: Double = 0, max: Double = 1e6) -> Bool {
        guard let v, v.isFinite else { return false }
        return v >= min && v <= max
    }

    /// Renders a double the way `JSON.stringify` would — no trailing `.0`.
    static func trimmed(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded() && abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }
}

// MARK: - ISO time

nonisolated extension String {
    /// FNV-1a over the UTF-8 bytes: the same for the same text on every
    /// launch, which `hashValue` is not.
    var stableHash: UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}

nonisolated extension Date {
    /// The instant `millis` milliseconds after 1970, the unit every stored
    /// time uses.
    init(epochMillis millis: Double) {
        self.init(timeIntervalSince1970: millis / 1000)
    }
}

nonisolated enum ISOTime {
    /// Milliseconds since epoch for an ISO-8601 instant, or nil.
    static func parse(_ iso: String) -> Double? {
        if let date = Formatter.withFraction.withLock({ $0.date(from: iso) }) {
            return date.timeIntervalSince1970 * 1000
        }
        if let date = Formatter.plain.withLock({ $0.date(from: iso) }) {
            return date.timeIntervalSince1970 * 1000
        }
        if let date = Formatter.calendarDay.withLock({ $0.date(from: iso) }) {
            return date.timeIntervalSince1970 * 1000
        }
        return nil
    }

    /// `2026-01-02T03:04:05.678Z` — the shape every stored instant uses.
    static func string(fromMillis millis: Double) -> String {
        string(from: Date(epochMillis: millis))
    }

    static func string(from date: Date) -> String {
        Formatter.withFraction.withLock { $0.string(from: date) }
    }

    static func now() -> String { string(from: Date()) }

    static func addDays(_ iso: String, _ days: Double) -> String {
        guard let millis = parse(iso) else { return iso }
        return string(fromMillis: millis + days * DAY_MS)
    }

    /// Whether the value is an instant in exactly the canonical shape.
    static func valid(_ value: String) -> Bool {
        guard value.count == 20 || value.count == 24 else { return false }
        guard let millis = parse(value) else { return false }
        let canonical = string(fromMillis: millis)
        return value.count == 20 ? canonical == value.replacingOccurrences(of: "Z", with: ".000Z") : canonical == value
    }

    /// Formatters are reference types that are not `Sendable`; the engine
    /// runs off the main actor, so each is reached only under its lock.
    enum Formatter {
        static let withFraction = Mutex(isoFormatter([.withInternetDateTime, .withFractionalSeconds]))
        static let plain = Mutex(isoFormatter([.withInternetDateTime]))
        static let calendarDay = Mutex(calendarDayFormatter())

        private static func isoFormatter(_ options: ISO8601DateFormatter.Options) -> ISO8601DateFormatter {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter
        }

        private static func calendarDayFormatter() -> DateFormatter {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter
        }
    }
}

nonisolated func compareIds(_ a: String, _ b: String) -> Int {
    a < b ? -1 : (a > b ? 1 : 0)
}

// MARK: - Canonical JSON & fingerprints

/// A loosely typed JSON tree, used for canonical serialisation, fingerprints
/// and the persisted-state validator that has to inspect unknown shapes.
nonisolated indirect enum JSONValue: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    var objectValue: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    var numberValue: Double? { if case .number(let v) = self { return v }; return nil }
    var boolValue: Bool? { if case .bool(let v) = self { return v }; return nil }
    var isNull: Bool { if case .null = self { return true }; return false }

    subscript(key: String) -> JSONValue? { objectValue?[key] }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    static func from(_ any: Any?) -> JSONValue {
        switch any {
        case nil, is NSNull: return .null
        case let value as JSONValue: return value
        case let value as Bool where type(of: any!) == type(of: NSNumber(value: true)):
            return .bool(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() { return .bool(value.boolValue) }
            return .number(value.doubleValue)
        case let value as String: return .string(value)
        case let value as [Any?]: return .array(value.map { JSONValue.from($0) })
        case let value as [String: Any]: return .object(value.mapValues { JSONValue.from($0) })
        default: return .null
        }
    }

    var anyValue: Any? {
        switch self {
        case .null: return nil
        case .bool(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let value): return value.map { $0.anyValue ?? NSNull() }
        case .object(let value):
            var result: [String: Any] = [:]
            for (key, item) in value where !item.isNull { result[key] = item.anyValue }
            return result
        }
    }
}

nonisolated extension JSONValue {
    /// `JSON.stringify` with object keys sorted and `undefined` dropped, which
    /// is what the engine's fingerprints are taken over.
    var canonical: String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let value): return Num.trimmed(value)
        case .string(let value): return JSONValue.quote(value)
        case .array(let items): return "[" + items.map(\.canonical).joined(separator: ",") + "]"
        case .object(let entries):
            let body = entries
                .filter { !$0.value.isNull }
                .sorted { compareIds($0.key, $1.key) < 0 }
                .map { JSONValue.quote($0.key) + ":" + $0.value.canonical }
                .joined(separator: ",")
            return "{" + body + "}"
        }
    }

    static func quote(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

/// Non-cryptographic reproducibility identifier, not a security or privacy primitive.
nonisolated func fingerprint(_ value: JSONValue) -> String {
    var hash: UInt32 = 2_166_136_261
    for character in value.canonical.unicodeScalars {
        // The TypeScript original hashes UTF-16 code units.
        for unit in String(character).utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 16_777_619
        }
    }
    return String(format: "%08x", hash)
}

// MARK: - Codable bridging

nonisolated enum JSONCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder = JSONDecoder()

    static func tree<T: Encodable>(_ value: T) -> JSONValue {
        guard let data = try? encoder.encode(value),
              let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return .null }
        return JSONValue.from(any)
    }

    static func value<T: Decodable>(_ tree: JSONValue, as type: T.Type) -> T? {
        guard let any = tree.anyValue,
              let data = try? JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed])
        else { return nil }
        return try? decoder.decode(type, from: data)
    }

    static func parse(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        return JSONValue.from(any)
    }

    static func string(_ tree: JSONValue) -> String { tree.canonical }
}

nonisolated extension Encodable {
    var jsonTree: JSONValue { JSONCoding.tree(self) }
}
