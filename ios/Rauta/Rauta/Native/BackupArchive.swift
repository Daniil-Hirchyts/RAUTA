import CryptoKit
import Foundation

/// How much a backup holds, for a person deciding whether to restore it.
nonisolated struct BackupCounts: Codable, Hashable, Sendable {
    var workouts: Int
    var completedWorkouts: Int
    var sessions: Int
    var programs: Int
    var loadConfigurations: Int
    var favorites: Int

    static let zero = BackupCounts(
        workouts: 0, completedWorkouts: 0, sessions: 0,
        programs: 0, loadConfigurations: 0, favorites: 0
    )
}

/// The label on a complete backup: what it is, when it was made, what it
/// holds, and a checksum over its data so a damaged file is recognised before
/// anything is restored from it.
///
/// It sits beside the `{ app, version, createdAt, data }` shape every RAUTA
/// backup has always had, and the version stays 1, so a build that predates the
/// manifest still restores the file — it simply ignores the label.
nonisolated struct BackupManifest: Codable, Hashable, Sendable {
    static let currentFormat = "rauta-backup"
    static let currentFormatVersion = 2

    var format: String
    var formatVersion: Int
    var createdAt: String
    var appVersion: String
    /// Whether the structured training records are included. The compact
    /// iCloud copy leaves them out; a full backup never does.
    var complete: Bool
    var counts: BackupCounts
    /// SHA-256 of the canonical JSON of `data`.
    var dataChecksum: String
}

/// What a backup file holds, read and checked without changing anything.
nonisolated struct BackupPreview: Hashable, Sendable {
    var createdAt: String?
    var manifest: BackupManifest?
    var counts: BackupCounts
    var hasTraining: Bool
    /// Things a person should know before restoring — written by an older
    /// version, no training history, fields this device will keep its own of.
    var warnings: [String]
    /// The checksum was present and matched. False for older backups, which
    /// carry none; a mismatch is never a preview, it is an error.
    var checksumVerified: Bool
}

nonisolated enum BackupArchiveError: Error, Equatable {
    case notABackup
    case unsupportedVersion
    case noData
    case damaged
    case invalidTraining

    var message: String {
        switch self {
        case .notABackup: return "This file isn't a RAUTA backup."
        case .unsupportedVersion: return "This backup was made by a newer version of RAUTA. Update the app, then try again."
        case .noData: return "This backup doesn't contain any app data."
        case .damaged: return "This backup is damaged: its contents don't match its checksum. Nothing was changed."
        case .invalidTraining: return "This backup's training records can't be read. Nothing was changed."
        }
    }
}

nonisolated enum BackupArchive {
    /// The envelope version every RAUTA backup has carried since the web app.
    static let envelopeVersion = 1

    static func checksum(_ data: JSONValue) -> String {
        let digest = SHA256.hash(data: Data(data.canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// What `data` holds, counted the same way for a backup being written and
    /// one being read.
    static func counts(_ data: [String: JSONValue]) -> BackupCounts {
        let workouts = data["workouts"]?["workouts"]?.arrayValue ?? []
        let training = data["training"]?.objectValue
        return BackupCounts(
            workouts: workouts.count,
            completedWorkouts: workouts.filter { $0["completion"]?.objectValue != nil }.count,
            sessions: training?["sessions"]?.arrayValue?.count ?? 0,
            programs: training?["programs"]?.arrayValue?.count ?? 0,
            loadConfigurations: training?["settings"]?["loadConfigurations"]?.arrayValue?.count ?? 0,
            favorites: data["favorites"]?["favoriteIds"]?.arrayValue?.count ?? 0
        )
    }

    /// Wraps backup data in the envelope every RAUTA backup has, with a
    /// manifest when it is a complete one.
    static func envelope(
        data: [String: JSONValue],
        createdAt: String,
        appVersion: String,
        complete: Bool
    ) -> JSONValue {
        var root: [String: JSONValue] = [
            "app": .string("RAUTA"),
            "createdAt": .string(createdAt),
            "version": .number(Double(envelopeVersion)),
            "data": .object(data),
        ]
        if complete {
            let manifest = BackupManifest(
                format: BackupManifest.currentFormat,
                formatVersion: BackupManifest.currentFormatVersion,
                createdAt: createdAt,
                appVersion: appVersion,
                complete: true,
                counts: counts(data),
                dataChecksum: checksum(.object(data))
            )
            root["manifest"] = manifest.jsonTree
        }
        return .object(root)
    }

    /// Reads a backup and checks it end to end — envelope, version, checksum,
    /// training records — without touching any store. Everything a restore
    /// would refuse, this refuses first.
    static func inspect(_ json: String) throws(BackupArchiveError) -> BackupPreview {
        guard let parsed = JSONCoding.parse(json), let root = parsed.objectValue else {
            throw .notABackup
        }
        let app = root["app"]?.stringValue
        guard app == "RAUTA" || app == "Gym Lib" else { throw .notABackup }
        let version = Storage.version(root["version"])
        guard version == envelopeVersion else {
            throw version > envelopeVersion ? .unsupportedVersion : .notABackup
        }
        guard let data = root["data"]?.objectValue else { throw .noData }

        let manifest = root["manifest"].flatMap { JSONCoding.value($0, as: BackupManifest.self) }
        if let manifest {
            guard manifest.formatVersion <= BackupManifest.currentFormatVersion else {
                throw .unsupportedVersion
            }
            guard manifest.dataChecksum == checksum(.object(data)) else { throw .damaged }
        }

        if let training = data["training"] {
            do { _ = try PersistenceValidation.migrate(training) } catch { throw .invalidTraining }
        }

        var warnings: [String] = []
        let hasTraining = data["training"] != nil
        if !hasTraining {
            warnings.append(
                "It has no set-by-set training history, plans or load settings — it was made by an "
                    + "older version or is a compact copy. Restoring keeps the training history already on this iPhone."
            )
        }
        if manifest == nil {
            warnings.append("It was made by an older version of RAUTA, so it carries no checksum to verify.")
        }
        let filters = data["filters"]?.objectValue ?? [:]
        if data["filters"] != nil, filters["gymEquipment"] == nil {
            warnings.append("It doesn't say which equipment you have; this iPhone keeps its own choice.")
        }
        if data["trainingProfile"] == nil {
            warnings.append("It has no training profile; this iPhone keeps its own.")
        }

        return BackupPreview(
            createdAt: root["createdAt"]?.stringValue,
            manifest: manifest,
            counts: manifest?.counts ?? counts(data),
            hasTraining: hasTraining,
            warnings: warnings,
            checksumVerified: manifest != nil
        )
    }
}
